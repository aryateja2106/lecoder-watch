import Foundation
import UserNotifications

/// Usage limit lifecycle notifications: budget tiers at 50% and 25% left, hit at
/// 95% used, session-window-open, scheduled reset alert, ping when a blocked limit
/// clears. Tap a reset/available alert to send `continue` to the pinned session
/// for that provider.
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// True when the user declined alert permission — surfaced in the Monitor tab.
    @Published var authorizationDenied = false

    /// The three kinds of thing an agent alert can be. They are separated because
    /// people want different amounts of each: a blocked agent is the reason this app
    /// exists, and "Claude stopped" fifty times a day is the reason people turn the
    /// whole category off — taking the blocked ones with it.
    enum AlertLane: String, CaseIterable {
        /// The agent is asking and cannot continue without an answer.
        case needsAttention
        /// Something failed.
        case error
        /// A turn ended, a task finished, an FYI. Statements, not questions.
        case turnEnd
    }

    /// A blocked agent is the product; on by default.
    @Published var alertNeedsAttention: Bool {
        didSet { UserDefaults.standard.set(alertNeedsAttention, forKey: Self.laneKey(.needsAttention)) }
    }
    /// A failure you did not ask about is still worth knowing; on by default.
    @Published var alertErrors: Bool {
        didSet { UserDefaults.standard.set(alertErrors, forKey: Self.laneKey(.error)) }
    }
    /// Turn-end chatter. OFF by default, deliberately: meshd 0.5.0 stopped pushing it
    /// at all, and the local poll lane was the other half of the same flood. Anyone who
    /// wants a buzz per finished turn can still ask for one.
    @Published var alertTurnEnd: Bool {
        didSet { UserDefaults.standard.set(alertTurnEnd, forKey: Self.laneKey(.turnEnd)) }
    }

    /// The (host, session) the user has open on screen right now, set by MeshStore.
    /// A banner about the thing you are already looking at is noise with a buzz on it.
    var currentlyViewing: (host: String, session: String)?

    private let firedKeysDefaultsKey = "mesh.notify.firedKeys.v1"
    private let lastBlockedDefaultsKey = "mesh.notify.lastBlocked.v1"
    private let scheduledResetsDefaultsKey = "mesh.notify.scheduledResets.v1"

    private static func laneKey(_ lane: AlertLane) -> String { "mesh.notify.lane.\(lane.rawValue).v1" }

    // Persisted so a relaunch neither re-fires warns nor misses blocked->cleared transitions.
    // event-<id> keys are excluded from persistence: they are one-per-event and would grow
    // the stored array forever, and cross-launch event dedup is already handled by the
    // per-host baseline (initializedEventHosts) in MeshStore, not by this set.
    private var firedKeys: Set<String> = [] {
        didSet { UserDefaults.standard.set(Array(firedKeys.filter { !$0.hasPrefix("event-") }), forKey: firedKeysDefaultsKey) }
    }
    // Gated, not raw: an ungated version of this path once produced 30+ banners in
    // five minutes of connection flapping. The pure gates live in Shared/AlertGating
    // so check-alert-gating.swift can prove the flood stays impossible.
    private var reachabilityGate = ReachabilityAlertGate()
    private var eventDeduper = EventAlertDeduper()
    private var lastBlockedByLimitKey: [String: Bool] = [:] {
        didSet { UserDefaults.standard.set(lastBlockedByLimitKey, forKey: lastBlockedDefaultsKey) }
    }
    private var scheduledResetWindowByKey: [String: String] = [:] {
        didSet { UserDefaults.standard.set(scheduledResetWindowByKey, forKey: scheduledResetsDefaultsKey) }
    }

    private let blockedThreshold = LimitHelpers.blockedThreshold

    /// Resume handler — MeshStore wires this to send `continue` to the pinned session.
    var onLimitResume: ((String) -> Void)?

    /// Answer a blocked agent straight from the notification. MeshStore wires this.
    /// `pane` is the pane the question came from when the payload named one, so an
    /// Approve lands in the agent's own pane rather than whichever pane the session
    /// happens to have active.
    var onAgentAction: ((_ host: String, _ session: String, _ text: String?, _ key: String?, _ pane: String?) -> Void)?

    /// A plain tap on an agent banner — not a button, the banner itself. Routes to the
    /// session the alert is about. Before this existed the default tap opened the app
    /// and went nowhere, which read as "notifications are broken" even though every
    /// button worked: the most natural gesture was the only one that did nothing.
    var onOpenSession: ((_ host: String, _ session: String) -> Void)?

    private override init() {
        // Defaults before `super.init()` because they are stored properties with
        // observers: `object(forKey:)` returning nil is "never chosen", which is the
        // only way to tell a deliberate `false` from an unset key.
        let defaults = UserDefaults.standard
        alertNeedsAttention = defaults.object(forKey: Self.laneKey(.needsAttention)) as? Bool ?? true
        alertErrors = defaults.object(forKey: Self.laneKey(.error)) as? Bool ?? true
        alertTurnEnd = defaults.object(forKey: Self.laneKey(.turnEnd)) as? Bool ?? false
        super.init()
        if let saved = UserDefaults.standard.stringArray(forKey: firedKeysDefaultsKey) {
            firedKeys = Set(saved)
        }
        if let saved = UserDefaults.standard.dictionary(forKey: lastBlockedDefaultsKey) as? [String: Bool] {
            lastBlockedByLimitKey = saved
        }
        if let saved = UserDefaults.standard.dictionary(forKey: scheduledResetsDefaultsKey) as? [String: String] {
            scheduledResetWindowByKey = saved
        }
        UNUserNotificationCenter.current().delegate = self
        AgentNotification.registerCategories()
    }

    /// Ask only once the app has a machine to alert you about.
    ///
    /// iOS shows this prompt exactly once, ever. Firing it on first launch asks a
    /// stranger to accept alerts from an app that has nothing to alert them about
    /// yet — and a denial permanently kills the one loop this product exists for,
    /// with no second prompt and no way back except a trip through Settings. After
    /// pairing there is a real answer to "alerts about what": that machine's agents.
    func requestAuthorizationOncePaired(hasMachines: Bool) {
        guard hasMachines else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                DispatchQueue.main.async {
                    self.authorizationDenied = settings.authorizationStatus == .denied
                }
                return
            }
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { self.authorizationDenied = !granted }
                }
        }
    }

    func evaluate(_ snapshot: MeshSnapshot, pinned: [PinnedLimitSession]) {
        evaluateReachability(snapshot.machines)
        evaluateUsage(snapshot.usage, pinned: pinned)
        // The push lane, retroactively: a banner APNs already delivered cannot be
        // stopped, but it can be taken down. Runs every poll so a lane switched off in
        // Settings stops accumulating within seconds instead of at the next launch.
        sweepMutedAlerts()
    }

    // MARK: - Which alerts the user asked for

    /// Which lane an event belongs to. `cardStateForLevel` grades the level exactly as
    /// meshd's push gate does; anything it shrugs at is graded by the title, because
    /// several producers write "Claude needs attention" at info level and that is a
    /// question however it was labelled.
    func lane(level: String?, title: String) -> AlertLane {
        switch cardStateForLevel(level) {
        case .error:
            return .error
        case .waiting:
            return .needsAttention
        default:
            let text = title.lowercased()
            return (text.contains("needs attention") || text.contains("needs input"))
                ? .needsAttention : .turnEnd
        }
    }

    /// Whether the user wants to hear about this lane at all.
    func wants(_ lane: AlertLane) -> Bool {
        switch lane {
        case .needsAttention: return alertNeedsAttention
        case .error:          return alertErrors
        case .turnEnd:        return alertTurnEnd
        }
    }

    /// True when this session is the one on screen right now.
    func isOnScreen(host: String?, session: String?) -> Bool {
        guard let viewing = currentlyViewing, let session, !session.isEmpty else { return false }
        guard viewing.session == session else { return false }
        // Host names drift between what the daemon calls itself and what the app
        // stored ("Aryas-MacBook-Pro.local" vs "Aryas-MacBook-Pro"), so compare the
        // way every other host comparison in the app does.
        guard let host, !host.isEmpty else { return true }
        return hostNamesMatch(viewing.host, host)
    }

    /// One banner we intend to raise, before the delivered-notification check gets a
    /// veto. Built synchronously so the decisions above stay testable and ordered.
    private struct PendingBanner {
        var id: String
        var title: String
        var body: String
        var userInfo: [String: String]
        var category: String?
    }

    func evaluate(events: [AgentEvent]) {
        var pending: [PendingBanner] = []
        for event in events {
            let key = "event-\(event.id)"
            guard !firedKeys.contains(key) else { continue }
            firedKeys.insert(key)
            // Same text, same session, inside the window = the user already knows.
            // A multi-subagent turn fires SubagentStop per subagent; one banner is plenty.
            guard eventDeduper.shouldAlert(host: event.host, session: event.session,
                                           title: event.title, body: event.body) else { continue }
            // The user's own filter, applied to the poll lane exactly as `sweepMutedAlerts`
            // applies it to the pushed one. Off by default for turn-end noise, which is
            // what made the whole category worth silencing.
            guard wants(lane(level: event.level, title: event.title)) else { continue }
            // Do not buzz about the session already open on screen.
            guard !isOnScreen(host: event.host, session: event.session) else { continue }
            // One banner per session, newest wins. Reusing the identifier makes the OS
            // replace this session's last alert instead of stacking another under it —
            // and it is the same string meshd stamps as `apns-collapse-id`, so the
            // pushed and the local lane share one identifier space and one sweep
            // (`clearResolvedAlerts`) clears both. The per-event-id dedupe above is a
            // different job and still runs: collapsing is about what is on screen,
            // firedKeys is about never re-firing an event we already handled.
            //
            // An event with neither a host nor a session has nothing to collapse
            // against, so it keeps its own id — which also keeps it out of the sweep.
            var id = key
            var info: [String: String] = [:]
            // Every agent banner gets a category. An actionless one is not the same as
            // no category: `infoCategory` is registered with an empty action list, so a
            // statement renders as a statement instead of growing Approve/Decline
            // buttons that would type Enter into a session nobody asked about.
            var category: String? = AgentNotification.infoCategory
            if let host = event.host, !host.isEmpty, let session = event.session, !session.isEmpty {
                id = meshNotificationId(host: host, session: session)
                info = AgentNotification.userInfo(host: host, session: session, pane: event.pane)
                // The same key meshd puts on a pushed payload, so `sweepMutedAlerts`
                // and `willPresent` grade a locally-raised banner exactly as the code
                // above graded the event. Without it a local error banner is graded by
                // its title alone, lands in the turn-end lane, and the very next poll
                // sweeps away the alert this method just decided to raise.
                if let level = event.level, !level.isEmpty { info["level"] = level }
                // Same grading as `isActionable` in push.ts: buttons only where there is
                // a stopped agent to answer. Without the category they never draw, and
                // userInfo alone would be a routing target with nothing to route.
                // replyable == false means the hook already knows no reply can route
                // (agent outside any mux) — banner it, but never offer dead buttons.
                if cardStateForLevel(event.level).wantsAttentionState, event.replyable != false {
                    category = AgentNotification.attentionCategory
                }
            }
            pending.append(PendingBanner(id: id,
                                         title: eventNotificationTitle(event),
                                         body: eventNotificationBody(event),
                                         userInfo: info,
                                         category: category))
        }
        schedule(deduping: pending)
    }

    /// Schedule the survivors, skipping any banner already sitting in Notification
    /// Center with identical text.
    ///
    /// Session banners deliberately reuse one identifier so the newest replaces the
    /// last — but replacing a banner re-alerts, and the poll lane can re-derive the
    /// *same* line from a session whose newest event has not changed. That produced a
    /// buzz per poll for one unanswered question. Same id plus same words means the
    /// user has already been told.
    private func schedule(deduping pending: [PendingBanner]) {
        guard !pending.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            var alreadyShowing: [String: String] = [:]
            for note in delivered {
                alreadyShowing[note.request.identifier] =
                    note.request.content.title + "\u{1}" + note.request.content.body
            }
            DispatchQueue.main.async {
                for banner in pending {
                    if alreadyShowing[banner.id] == banner.title + "\u{1}" + banner.body { continue }
                    self.notifyNow(id: banner.id,
                                   title: banner.title,
                                   body: banner.body,
                                   userInfo: banner.userInfo,
                                   category: banner.category)
                }
            }
        }
    }

    /// Take down delivered agent alerts whose lane the user has switched off, and any
    /// about the session currently on screen.
    ///
    /// APNs delivers before the app gets a say, so this cannot prevent the first buzz
    /// of a muted lane — nothing on the device can. What it can do is stop them piling
    /// up, which is the part that made Notification Center unreadable. meshd 0.5.0's
    /// own push gate already declines to send the info lane, so in a current fleet this
    /// mostly sweeps banners from daemons that have not been updated yet.
    private func sweepMutedAlerts() {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let rows = delivered.map {
                (id: $0.request.identifier,
                 title: $0.request.content.title,
                 host: $0.request.content.userInfo["host"] as? String,
                 session: $0.request.content.userInfo["session"] as? String,
                 level: $0.request.content.userInfo["level"] as? String)
            }
            // Back to the main queue before reading the toggles, which are @Published
            // and written there.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let doomed = rows.filter { row in
                    // Only agent alerts carry a session; limit and reachability banners
                    // are a different vocabulary and are not this filter's business.
                    guard row.session != nil else { return false }
                    if self.isOnScreen(host: row.host, session: row.session) { return true }
                    return !self.wants(self.lane(level: row.level, title: row.title))
                }
                guard !doomed.isEmpty else { return }
                center.removeDeliveredNotifications(withIdentifiers: doomed.map(\.id))
            }
        }
    }

    /// Once the agent stops waiting, the banner about it should stop existing.
    ///
    /// Driven off the poll loop rather than off any single "it finished" event, because
    /// the finish arrives by too many routes to enumerate — a Stop hook, a calmer event
    /// superseding the question, the session being answered from another device, or the
    /// session simply going away. `sessionsNeedingAttention` already collapses all of
    /// those into one answer: who is still waiting. Everything else goes.
    func clearResolvedAlerts(attention: [(host: String, session: String)]) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            center.getPendingNotificationRequests { pending in
                // Pending as well as delivered: local event alerts are scheduled a
                // second out, so a session that finishes between two polls can have a
                // banner queued that has not landed yet. Letting that one through is
                // the exact "it buzzed after I was done" this feature exists to stop.
                let ids = notificationIdsToClear(
                    delivered: delivered.map(\.request.identifier) + pending.map(\.identifier),
                    attention: attention)
                guard !ids.isEmpty else { return }
                center.removeDeliveredNotifications(withIdentifiers: ids)
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    // MARK: - Reachability

    private func evaluateReachability(_ machines: [MachineSnapshot]) {
        for m in machines {
            switch reachabilityGate.evaluate(host: m.host, reachable: m.reachable) {
            case .wentOffline:
                // Retract the opposite claim: "back online" is wrong once it is
                // down again, and two contradictory alerts side by side is noise.
                UNUserNotificationCenter.current().removeDeliveredNotifications(
                    withIdentifiers: ["reach-\(m.host)-true"])
                notifyNow(id: "reach-\(m.host)-false", title: m.host, body: "went offline",
                          thread: "reach-\(m.host)")
            case .backOnline:
                UNUserNotificationCenter.current().removeDeliveredNotifications(
                    withIdentifiers: ["reach-\(m.host)-false"])
                notifyNow(id: "reach-\(m.host)-true", title: m.host, body: "back online",
                          thread: "reach-\(m.host)")
            case nil:
                break
            }
        }
    }

    // MARK: - Usage limits

    private func evaluateUsage(_ usage: UsageSnapshot?, pinned: [PinnedLimitSession]) {
        guard let usage else { return }
        var desiredResetIds = Set<String>()

        for provider in usage.providers {
            for limit in provider.limits {
                let limitKey = LimitHelpers.limitKey(providerId: provider.id, label: limit.label)
                // One normalized identity for this reset window, spliced into every key
                // below. OpenUsage re-derives resetsAt on each poll and it jitters by
                // seconds; the raw ISO minted a brand-new key for 2:29:59 vs 2:30:04
                // while the banner text — rendered at minute resolution — stayed
                // word-for-word identical. That is the hourly re-fire of the same alert,
                // and the reset request that tore itself down and re-armed every poll.
                let window = Self.alertWindow(from: limit.resetsAtISO)
                // nil pct means "unknown", not "cleared" — skip alerts so blocked state
                // doesn't flap, but keep any reset alert already armed for this window alive:
                // a nil poll must NOT cancel the OS-persisted reset notification.
                guard let pct = limit.usedPct else {
                    if scheduledResetWindowByKey[limitKey] == window,
                       let d = LimitHelpers.resetDate(from: limit.resetsAtISO), d.timeIntervalSinceNow > 1 {
                        desiredResetIds.insert("mesh-limit-reset-\(limitKey)")
                    }
                    continue
                }
                let blocked = pct >= blockedThreshold
                let wasBlocked = lastBlockedByLimitKey[limitKey] ?? false

                let remaining = LimitHelpers.remainingPct(usedPct: pct) ?? 100

                // Anything delivered for an earlier window is describing a budget
                // that no longer exists — clear it before adding to the pile.
                pruneDeliveredAlerts(limitKey: limitKey, currentWindow: window)

                // A session window opening is itself worth knowing: it starts the
                // clock you are budgeting against.
                if LimitHelpers.isSessionLimit(label: limit.label), pct > 0 {
                    let startKey = "usage-start-\(limitKey)-\(window)"
                    if !firedKeys.contains(startKey) {
                        firedKeys.insert(startKey)
                        notifyNow(id: startKey,
                                  title: "\(provider.displayName) session started",
                                  body: sessionStartedBody(limit: limit),
                                  thread: "limit-\(limitKey)")
                    }
                }

                // Budget tiers: 50% then 25% left. Firing the lowest crossed tier and
                // suppressing the ones above it means a fast burn produces one alert,
                // not a burst. A blocked limit gets "limit reached" below instead: both
                // at once is the near-identical pair the user screenshotted, and
                // crossedTier(remainingPct: 0) is 25, so the pair even disagreed.
                if !blocked, let tier = LimitHelpers.crossedTier(remainingPct: remaining) {
                    let tierKey = "usage-tier\(tier)-\(limitKey)-\(window)"
                    if !firedKeys.contains(tierKey) {
                        for passed in LimitHelpers.tiersAtOrAbove(tier) {
                            firedKeys.insert("usage-tier\(passed)-\(limitKey)-\(window)")
                        }
                        notifyNow(id: tierKey,
                                  title: Self.tierAlertTitle(provider: provider.displayName,
                                                             label: limit.label,
                                                             remainingPct: remaining),
                                  body: Self.warningBody(limit: limit, pct: pct),
                                  thread: "limit-\(limitKey)")
                    }
                }

                if remaining <= LimitHelpers.remainingAlertTiers.max() ?? 50 {
                    // Pre-arm the OS-persisted reset alert as soon as the budget starts
                    // mattering, so it still fires if the app is backgrounded or killed.
                    if let resetId = scheduleResetNotification(provider: provider,
                                                               limit: limit,
                                                               pinned: pinned) {
                        desiredResetIds.insert(resetId)
                    }
                }

                if blocked {
                    let hitKey = "usage-hit-\(limitKey)-\(window)"
                    if !firedKeys.contains(hitKey) {
                        firedKeys.insert(hitKey)
                        notifyNow(id: hitKey,
                                  title: "\(provider.displayName) limit reached",
                                  body: blockedBody(provider: provider, limit: limit, pinned: pinned),
                                  userInfo: limitUserInfo(providerId: provider.id, action: "limitHit"),
                                  thread: "limit-\(limitKey)")
                    }
                } else if wasBlocked && pct < LimitHelpers.clearedThreshold {
                    let availKey = "usage-available-\(limitKey)-\(window)"
                    if !firedKeys.contains(availKey) {
                        firedKeys.insert(availKey)
                        // The budget warnings and the "limit reached" alert are all
                        // false now — retract them rather than leaving them stacked
                        // above the good news.
                        pruneDeliveredAlerts(limitKey: limitKey, currentWindow: window, clearAll: true)
                        notifyNow(id: availKey,
                                  title: "\(provider.displayName) limit reset",
                                  body: availableBody(provider: provider, limit: limit, pinned: pinned),
                                  userInfo: limitUserInfo(providerId: provider.id, action: "limitAvailable"),
                                  loud: true,
                                  thread: "limit-\(limitKey)")
                    }
                }

                lastBlockedByLimitKey[limitKey] = blocked
            }
        }

        cancelStaleResetNotifications(keeping: desiredResetIds)
    }

    private func scheduleResetNotification(provider: UsageProvider,
                                           limit: UsageLimit,
                                           pinned: [PinnedLimitSession]) -> String? {
        guard let resetDate = LimitHelpers.resetDate(from: limit.resetsAtISO) else { return nil }
        let seconds = resetDate.timeIntervalSinceNow
        guard seconds > 1 else { return nil }

        let limitKey = LimitHelpers.limitKey(providerId: provider.id, label: limit.label)
        let id = "mesh-limit-reset-\(limitKey)"
        let window = Self.alertWindow(from: limit.resetsAtISO)
        if scheduledResetWindowByKey[limitKey] == window {
            return id
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        scheduledResetWindowByKey[limitKey] = window

        let pin = pinned.first { $0.providerId.lowercased() == provider.id.lowercased() }
        let body: String
        if let pin {
            body = "Tap to send continue to \(pin.sessionName) on \(shortHost(pin.host))."
        } else {
            body = "Pin a session in iPhone Settings to auto-continue from alerts."
        }

        var info = limitUserInfo(providerId: provider.id, action: "limitReset")
        info["limitLabel"] = limit.label

        schedule(id: id,
                 title: "\(provider.displayName) limit resets now",
                 body: body,
                 interval: seconds,
                 userInfo: info,
                 loud: true,
                 thread: "limit-\(limitKey)")

        return id
    }

    /// Alert identifiers that describe a *state*, so a delivered one stops being
    /// true the moment that state changes. `usage-available-` is excluded: it
    /// reports an event you may still want to act on.
    private static let statefulAlertPrefixes = ["usage-start-", "usage-tier", "usage-hit-", "usage-warn-"]

    /// Drop delivered alerts for a limit that no longer apply — either they belong
    /// to an earlier reset window, or the limit has since cleared. Without this
    /// every window leaves its alerts stacked in Notification Center and the list
    /// only ever grows, which is exactly what makes them stop being read.
    private func pruneDeliveredAlerts(limitKey: String, currentWindow: String, clearAll: Bool = false) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let stale = delivered.map(\.request.identifier).filter { id in
                guard Self.statefulAlertPrefixes.contains(where: { id.hasPrefix($0) }),
                      id.contains("-\(limitKey)-") else { return false }
                return clearAll || !id.hasSuffix("-\(currentWindow)")
            }
            guard !stale.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    private func cancelStaleResetNotifications(keeping desired: Set<String>) {
        let staleKeys = scheduledResetWindowByKey.keys.filter { key in
            let id = "mesh-limit-reset-\(key)"
            return !desired.contains(id)
        }
        guard !staleKeys.isEmpty else { return }
        let ids = staleKeys.map { "mesh-limit-reset-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        for key in staleKeys { scheduledResetWindowByKey.removeValue(forKey: key) }
    }

    // MARK: - Copy helpers

    // PURE-ALERT-IDENTITY-BEGIN — scripts/check-usage-alert-identity.sh compiles the
    // functions between these markers verbatim and runs them. Keep them free of
    // instance state and of UserNotifications types, or that check stops building.

    /// The identity of one reset window, at the same resolution the banner shows it.
    /// `resetCountdown` renders a far-off reset as "Resets Aug 27, 2026 at 2:30 PM" —
    /// seconds are dropped. OpenUsage re-derives resetsAt every poll and it drifts by
    /// a few seconds, so keying on the raw ISO minted a new key for 2:30:01 vs
    /// 2:30:04 while the text stayed word-for-word identical: the gate saw a new
    /// event, the user saw the same banner again, roughly hourly. Bucketing to the
    /// minute makes the key exactly as fine-grained as what the user can read, so two
    /// polls they cannot tell apart get one alert and a reset time they *can* see
    /// change still gets its own.
    static func alertWindow(from iso: String?) -> String {
        guard let date = LimitHelpers.resetDate(from: iso) else { return iso ?? "none" }
        return "m\(Int((date.timeIntervalSince1970 / 60).rounded(.down)))"
    }

    /// Title for a budget-tier alert. It reports the *remaining* percentage, not the
    /// tier that was crossed: `crossedTier` answers "which threshold did we fall
    /// through" and returns 25 for 0% left, so the old title read "25% left" above a
    /// body that read "0% left" — the banner contradicted itself.
    static func tierAlertTitle(provider: String, label: String, remainingPct: Int) -> String {
        "\(provider) \(label) — \(remainingPct)% left"
    }

    static func warningBody(limit: UsageLimit, pct: Double) -> String {
        let left = LimitHelpers.remainingPct(usedPct: pct).map { "\($0)% left" } ?? String(format: "%.0f%% used", pct)
        let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO).map { " · \($0)" } ?? ""
        return "\(left)\(countdown)"
    }

    // PURE-ALERT-IDENTITY-END

    private func sessionStartedBody(limit: UsageLimit) -> String {
        LimitHelpers.resetCountdown(from: limit.resetsAtISO)
            .map { "Your window is open · \($0)" }
            ?? "Your session window is open."
    }

    private func blockedBody(provider: UsageProvider, limit: UsageLimit, pinned: [PinnedLimitSession]) -> String {
        let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) ?? "Waiting for reset"
        if pinned.contains(where: { $0.providerId.lowercased() == provider.id.lowercased() }) {
            return "\(countdown). You'll get another alert when it's back."
        }
        return "\(countdown). Pin a session in Settings to resume from alerts."
    }

    private func availableBody(provider: UsageProvider, limit: UsageLimit, pinned: [PinnedLimitSession]) -> String {
        if let pin = pinned.first(where: { $0.providerId.lowercased() == provider.id.lowercased() }) {
            return "Tap to send continue to \(pin.sessionName) on \(shortHost(pin.host))."
        }
        return "Session quota is available again for \(provider.displayName) \(limit.label)."
    }

    private func shortHost(_ host: String) -> String {
        host.replacingOccurrences(of: "arya-", with: "").replacingOccurrences(of: "agents", with: "")
    }

    private func limitUserInfo(providerId: String, action: String) -> [String: String] {
        ["providerId": providerId, "action": action]
    }

    // MARK: - Delivery

    private func notifyNow(id: String,
                           title: String,
                           body: String,
                           userInfo: [String: String] = [:],
                           loud: Bool = false,
                           category: String? = nil,
                           thread: String? = nil) {
        schedule(id: id, title: title, body: body, interval: 1,
                 userInfo: userInfo, loud: loud, category: category, thread: thread)
    }

    private func schedule(id: String,
                          title: String,
                          body: String,
                          interval: TimeInterval,
                          userInfo: [String: String] = [:],
                          loud: Bool = false,
                          category: String? = nil,
                          thread: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if loud { content.interruptionLevel = .timeSensitive }
        if let category { content.categoryIdentifier = category }
        // Group per limit/machine so Notification Center collapses a run of
        // alerts into one stack instead of a wall of separate rows.
        if let thread { content.threadIdentifier = thread }
        content.userInfo = userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Agent events

    private func eventNotificationTitle(_ event: AgentEvent) -> String {
        let level = event.level?.lowercased()
        let prefix = (level == "error" || level == "warning") ? "\(level!.capitalized): " : ""
        let source = event.source.map(displaySource) ?? "Agent"
        return "\(prefix)\(source): \(event.title)"
    }

    private func eventNotificationBody(_ event: AgentEvent) -> String {
        let whereText = [event.host, event.session].compactMap { $0 }.joined(separator: " · ")
        let body = event.body ?? whereText
        guard !whereText.isEmpty, event.body != nil else { return body.isEmpty ? "agent event" : body }
        return "\(body)\n\(whereText)"
    }

    private func displaySource(_ source: String) -> String {
        switch source.lowercased() {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "pi", "raspberry-pi": return "Pi"
        default: return source
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// The push lane's one real veto point. A pushed alert the app is awake for still
    /// passes through here before it draws, so a muted lane — or an alert about the
    /// session already filling the screen — can be declined instead of drawn.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        let session = info["session"] as? String
        // Only agent alerts are filtered. A limit reset or a machine going offline is
        // not graded by these toggles and must not be silenced by them.
        if session != nil {
            if isOnScreen(host: info["host"] as? String, session: session) {
                completionHandler([])
                return
            }
            if !wants(lane(level: info["level"] as? String,
                           title: notification.request.content.title)) {
                completionHandler([])
                return
            }
        }
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = info["action"] as? String
        let providerId = info["providerId"] as? String
        if let providerId,
           action == "limitReset" || action == "limitAvailable" {
            onLimitResume?(providerId)
        }
        // A button on an agent alert: Approve (Enter), Decline (Escape), Reply (typed
        // text) or Stop (ctrl-c). The typed text only exists for Reply, and an empty
        // reply is a dismissal, not an empty message — `command(for:typed:)` returns
        // nil for that, and for any identifier this build does not recognise.
        //
        // `pane` routes the answer to the pane the question came from when the payload
        // named one; APNs payloads do not carry it today, locally-raised banners do.
        if let target = AgentNotification.target(from: info),
           let cmd = AgentNotification.command(
               for: response.actionIdentifier,
               typed: (response as? UNTextInputNotificationResponse)?.userText,
           ) {
            onAgentAction?(target.host, target.session, cmd.text, cmd.key,
                           AgentNotification.pane(from: info))
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
                  let target = AgentNotification.target(from: info) {
            // The banner itself was tapped. `command(for:)` deliberately returns nil
            // here — a bare tap must never SEND anything — but it must still LAND
            // somewhere: on the session the alert is about, same as the Live
            // Activity's widgetURL.
            onOpenSession?(target.host, target.session)
        }
        completionHandler()
    }
}

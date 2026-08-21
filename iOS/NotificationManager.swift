import Foundation
import UserNotifications

/// Usage limit lifecycle notifications: warn at 85%, hit at 95%, schedule reset alert,
/// ping when a blocked limit clears. Tap a reset/available alert to send `continue`
/// to the pinned session for that provider.
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// True when the user declined alert permission — surfaced in the Monitor tab.
    @Published var authorizationDenied = false

    private let firedKeysDefaultsKey = "mesh.notify.firedKeys.v1"
    private let lastBlockedDefaultsKey = "mesh.notify.lastBlocked.v1"
    private let scheduledResetsDefaultsKey = "mesh.notify.scheduledResets.v1"

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
    private var scheduledResetISOByKey: [String: String] = [:] {
        didSet { UserDefaults.standard.set(scheduledResetISOByKey, forKey: scheduledResetsDefaultsKey) }
    }

    private let usageThreshold = LimitHelpers.warningThreshold
    private let blockedThreshold = LimitHelpers.blockedThreshold

    /// Resume handler — MeshStore wires this to send `continue` to the pinned session.
    var onLimitResume: ((String) -> Void)?

    /// Answer a blocked agent straight from the notification. MeshStore wires this.
    var onAgentAction: ((_ host: String, _ session: String, _ text: String?, _ key: String?) -> Void)?

    private override init() {
        super.init()
        if let saved = UserDefaults.standard.stringArray(forKey: firedKeysDefaultsKey) {
            firedKeys = Set(saved)
        }
        if let saved = UserDefaults.standard.dictionary(forKey: lastBlockedDefaultsKey) as? [String: Bool] {
            lastBlockedByLimitKey = saved
        }
        if let saved = UserDefaults.standard.dictionary(forKey: scheduledResetsDefaultsKey) as? [String: String] {
            scheduledResetISOByKey = saved
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
    }

    func evaluate(events: [AgentEvent]) {
        for event in events {
            let key = "event-\(event.id)"
            guard !firedKeys.contains(key) else { continue }
            firedKeys.insert(key)
            // Same text, same session, inside the window = the user already knows.
            // A multi-subagent turn fires SubagentStop per subagent; one banner is plenty.
            guard eventDeduper.shouldAlert(host: event.host, session: event.session,
                                           title: event.title, body: event.body) else { continue }
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
            var category: String?
            if let host = event.host, !host.isEmpty, let session = event.session, !session.isEmpty {
                id = meshNotificationId(host: host, session: session)
                info = AgentNotification.userInfo(host: host, session: session)
                // Same grading as `isActionable` in push.ts: buttons only where there is
                // a stopped agent to answer. Without the category they never draw, and
                // userInfo alone would be a routing target with nothing to route.
                if cardStateForLevel(event.level).wantsAttentionState {
                    category = AgentNotification.attentionCategory
                }
            }
            notifyNow(id: id,
                      title: eventNotificationTitle(event),
                      body: eventNotificationBody(event),
                      userInfo: info,
                      category: category)
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
                notifyNow(id: "reach-\(m.host)-false", title: m.host, body: "went offline")
            case .backOnline:
                notifyNow(id: "reach-\(m.host)-true", title: m.host, body: "back online")
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
                // nil pct means "unknown", not "cleared" — skip alerts so blocked state
                // doesn't flap, but keep any reset alert already armed for this window alive:
                // a nil poll must NOT cancel the OS-persisted reset notification.
                guard let pct = limit.usedPct else {
                    if let iso = limit.resetsAtISO,
                       scheduledResetISOByKey[limitKey] == iso,
                       let d = LimitHelpers.resetDate(from: iso), d.timeIntervalSinceNow > 1 {
                        desiredResetIds.insert("mesh-limit-reset-\(limitKey)")
                    }
                    continue
                }
                let blocked = pct >= blockedThreshold
                let wasBlocked = lastBlockedByLimitKey[limitKey] ?? false

                if pct >= usageThreshold {
                    let warnKey = "usage-warn-\(limitKey)-\(limit.resetsAtISO ?? "none")"
                    if !firedKeys.contains(warnKey) {
                        firedKeys.insert(warnKey)
                        notifyNow(id: warnKey,
                                  title: "\(provider.displayName) \(limit.label)",
                                  body: warningBody(provider: provider, limit: limit, pct: pct))
                    }
                    // Pre-arm the OS-persisted reset alert from the warning band so it
                    // still fires if the app is backgrounded or killed before the limit hits.
                    if let resetId = scheduleResetNotification(provider: provider,
                                                               limit: limit,
                                                               pinned: pinned) {
                        desiredResetIds.insert(resetId)
                    }
                }

                if blocked {
                    let hitKey = "usage-hit-\(limitKey)-\(limit.resetsAtISO ?? "none")"
                    if !firedKeys.contains(hitKey) {
                        firedKeys.insert(hitKey)
                        notifyNow(id: hitKey,
                                  title: "\(provider.displayName) limit reached",
                                  body: blockedBody(provider: provider, limit: limit, pinned: pinned),
                                  userInfo: limitUserInfo(providerId: provider.id, action: "limitHit"))
                    }
                } else if wasBlocked && pct < LimitHelpers.clearedThreshold {
                    let availKey = "usage-available-\(limitKey)-\(limit.resetsAtISO ?? "none")"
                    if !firedKeys.contains(availKey) {
                        firedKeys.insert(availKey)
                        notifyNow(id: availKey,
                                  title: "\(provider.displayName) limit reset",
                                  body: availableBody(provider: provider, limit: limit, pinned: pinned),
                                  userInfo: limitUserInfo(providerId: provider.id, action: "limitAvailable"),
                                  loud: true)
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
        guard let iso = limit.resetsAtISO,
              let resetDate = LimitHelpers.resetDate(from: iso) else { return nil }
        let seconds = resetDate.timeIntervalSinceNow
        guard seconds > 1 else { return nil }

        let limitKey = LimitHelpers.limitKey(providerId: provider.id, label: limit.label)
        let id = "mesh-limit-reset-\(limitKey)"
        if scheduledResetISOByKey[limitKey] == iso {
            return id
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        scheduledResetISOByKey[limitKey] = iso

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
                 loud: true)

        return id
    }

    private func cancelStaleResetNotifications(keeping desired: Set<String>) {
        let staleKeys = scheduledResetISOByKey.keys.filter { key in
            let id = "mesh-limit-reset-\(key)"
            return !desired.contains(id)
        }
        guard !staleKeys.isEmpty else { return }
        let ids = staleKeys.map { "mesh-limit-reset-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        for key in staleKeys { scheduledResetISOByKey.removeValue(forKey: key) }
    }

    // MARK: - Copy helpers

    private func warningBody(provider: UsageProvider, limit: UsageLimit, pct: Double) -> String {
        let left = LimitHelpers.remainingPct(usedPct: pct).map { "\($0)% left" } ?? String(format: "%.0f%% used", pct)
        let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO).map { " · \($0)" } ?? ""
        return "\(left)\(countdown)"
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
                           category: String? = nil) {
        schedule(id: id, title: title, body: body, interval: 1,
                 userInfo: userInfo, loud: loud, category: category)
    }

    private func schedule(id: String,
                          title: String,
                          body: String,
                          interval: TimeInterval,
                          userInfo: [String: String] = [:],
                          loud: Bool = false,
                          category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if loud { content.interruptionLevel = .timeSensitive }
        if let category { content.categoryIdentifier = category }
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

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
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
        // A button on an agent alert. The typed text only exists for the Reply action,
        // and an empty reply is a dismissal, not an empty message.
        if let target = AgentNotification.target(from: info),
           let cmd = AgentNotification.command(
               for: response.actionIdentifier,
               typed: (response as? UNTextInputNotificationResponse)?.userText,
           ) {
            onAgentAction?(target.host, target.session, cmd.text, cmd.key)
        }
        completionHandler()
    }
}

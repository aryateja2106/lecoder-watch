import Foundation
import UserNotifications

/// Local notifications for the monitoring layer. Two complementary lanes:
///  1. Usage-limit lifecycle — warn at 85%, hit at 95%, schedule an OS-persisted
///     reset alert, ping when a blocked limit clears. Tap a reset/available alert to
///     send `continue` to the pinned session for that provider (via `onLimitResume`).
///  2. Agent events — turn agent /events into actionable pings (needs-input /
///     finished / error), honoring the user's per-source / per-type toggles, and
///     route a tap back to the machine→session it came from (via `onOpen`).
/// Delivered to the phone (and mirrored to the watch by watchOS automatically).
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
    private var lastReachable: [String: Bool] = [:]
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

    /// Tap routing for agent-event notifications — set by MeshStore. Receives (appHost, session?).
    var onOpen: ((String, String?) -> Void)?

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
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.authorizationDenied = !granted
            }
        }
    }

    func evaluate(_ snapshot: MeshSnapshot, pinned: [PinnedLimitSession]) {
        evaluateReachability(snapshot.machines)
        evaluateUsage(snapshot.usage, pinned: pinned)
    }

    /// Turn fresh agent events into notifications, honoring the user's per-source /
    /// per-type toggles. Routine output (unclassified level) is dropped — only
    /// needs-input / finished / error ping.
    /// `primary` is the pinned session id. Codync rule: only the primary session's
    /// *completion* pings; needs-input and error ping for every session (safety net).
    func evaluate(events: [AgentEvent], prefs: NotifPrefs, primary: String?) {
        for event in events {
            let key = "event-\(event.id)"
            guard !firedKeys.contains(key) else { continue }
            guard let kind = notifKind(for: event.level), prefs.allows(event) else { continue }
            if kind == .finished, let primary, event.session != primary { continue }
            firedKeys.insert(key)
            notify(id: key,
                   title: eventNotificationTitle(event),
                   body: eventNotificationBody(event),
                   kind: kind,
                   host: event.host,
                   session: event.session)
        }
    }

    // MARK: - Reachability

    private func evaluateReachability(_ machines: [MachineSnapshot]) {
        for m in machines {
            if let prev = lastReachable[m.host], prev != m.reachable {
                notifyNow(id: "reach-\(m.host)-\(m.reachable)",
                          title: m.host,
                          body: m.reachable ? "back online" : "went offline")
            }
            lastReachable[m.host] = m.reachable
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
                           loud: Bool = false) {
        schedule(id: id, title: title, body: body, interval: 1, userInfo: userInfo, loud: loud)
    }

    private func schedule(id: String,
                          title: String,
                          body: String,
                          interval: TimeInterval,
                          userInfo: [String: String] = [:],
                          loud: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if loud { content.interruptionLevel = .timeSensitive }
        content.userInfo = userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    /// Agent-event notification: louder + break-through for needs-input/error, quiet
    /// for finished, and carrying host/session so a tap can open the right session.
    private func notify(id: String, title: String, body: String, kind: NotifKind, host: String?, session: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // ponytail: .timeSensitive only breaks through Focus/DND with the matching
        // entitlement; without it iOS quietly downgrades to .active — no crash. Add
        // the entitlement when shipping if DND break-through matters.
        content.interruptionLevel = kind.isLoud ? .timeSensitive : .active
        if let host { content.threadIdentifier = host }
        var info: [String: String] = [:]
        if let host { info["host"] = host }
        if let session, !session.isEmpty { info["session"] = session }
        content.userInfo = info
        let req = UNNotificationRequest(identifier: id, content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Agent-event copy

    private func eventNotificationTitle(_ event: AgentEvent) -> String {
        let source = displaySourceLabel(event.source)
        switch notifKind(for: event.level) {
        case .needsInput: return "\(source) needs input"
        case .finished:   return "Session complete"
        case .error:      return "Error in \(event.session ?? source)"
        case nil:         return "\(source): \(event.title)"
        }
    }

    private func eventNotificationBody(_ event: AgentEvent) -> String {
        let sessionHost = [event.session, event.host].compactMap { $0 }.joined(separator: " · ")
        switch notifKind(for: event.level) {
        case .finished:
            return "\(displaySourceLabel(event.source)) · \(event.session ?? "session") finished"
        case .error:
            let detail = (event.body?.isEmpty == false) ? event.body! : event.title
            return [detail, event.host].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .needsInput, nil:
            if let body = event.body, !body.isEmpty { return body }
            return sessionHost.isEmpty ? event.title : sessionHost
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show the banner even when the app is foregrounded (so a permission ping is
    /// visible while you're already in the app, and verifiable in the simulator).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// Tap routing. Usage-limit reset/available alerts send `continue` to the pinned
    /// session (onLimitResume); agent-event alerts open the machine→session (onOpen).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = info["action"] as? String
        if let providerId = info["providerId"] as? String,
           action == "limitReset" || action == "limitAvailable" {
            onLimitResume?(providerId)
        } else if let host = info["host"] as? String {
            let session = (info["session"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            onOpen?(host, session)
        }
        completionHandler()
    }
}

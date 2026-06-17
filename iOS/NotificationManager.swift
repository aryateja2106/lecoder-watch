import Foundation
import UserNotifications

/// Local notifications for the monitoring layer: usage limits crossing a threshold,
/// a machine dropping offline, and agent count changes. Delivered to the phone (and
/// mirrored to the watch by watchOS automatically). Also turns agent /events into
/// actionable pings (needs-input / finished / error), and routes a tap back to the
/// machine→session it came from.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var firedKeys: Set<String> = []          // de-dupe within a session
    private var lastReachable: [String: Bool] = [:]
    private let usageThreshold = 85.0                  // notify when a limit is >85% used

    /// Tap routing — set by MeshStore. Receives (appHost, session?).
    var onOpen: ((String, String?) -> Void)?
    /// Notification-action routing — set by MeshStore. Reuses the WatchCommand router so a
    /// quick-reply / Enter / Kill from a notification takes the same path as a watch command.
    var onAction: ((WatchCommand) -> Void)?

    // Action identifiers.
    private enum Action { static let reply = "REPLY", enter = "ENTER", kill = "KILL" }

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Self.categories())
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Per-kind action sets: needs-input → Reply + Enter; error → Reply + Kill. Category id
    /// is the NotifKind rawValue, matched to `content.categoryIdentifier` at post time.
    private static func categories() -> Set<UNNotificationCategory> {
        let reply = UNTextInputNotificationAction(
            identifier: Action.reply, title: "Reply", options: [],
            textInputButtonTitle: "Send", textInputPlaceholder: "Reply to the agent")
        let enter = UNNotificationAction(identifier: Action.enter, title: "Press Enter", options: [])
        let kill = UNNotificationAction(identifier: Action.kill, title: "Stop session",
                                        options: [.destructive, .authenticationRequired])
        return [
            UNNotificationCategory(identifier: NotifKind.needsInput.rawValue,
                                   actions: [reply, enter], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: NotifKind.error.rawValue,
                                   actions: [reply, kill], intentIdentifiers: [], options: []),
        ]
    }

    /// Inspect a fresh snapshot and fire notifications for noteworthy changes.
    func evaluate(_ snapshot: MeshSnapshot) {
        // Machine reachability transitions.
        for m in snapshot.machines {
            if let prev = lastReachable[m.host], prev != m.reachable {
                notify(id: "reach-\(m.host)-\(m.reachable)",
                       title: m.host,
                       body: m.reachable ? "back online" : "went offline")
            }
            lastReachable[m.host] = m.reachable
        }
        // Usage thresholds (once per limit per session).
        for p in snapshot.usage?.providers ?? [] {
            for l in p.limits {
                guard let pct = l.usedPct, pct >= usageThreshold else { continue }
                let key = "usage-\(p.id)-\(l.label)"
                if firedKeys.contains(key) { continue }
                firedKeys.insert(key)
                notify(id: key,
                       title: "\(p.displayName) \(l.label)",
                       body: String(format: "%.0f%% used%@", pct, resetSuffix(l)))
            }
        }
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

    private func resetSuffix(_ l: UsageLimit) -> String {
        guard let iso = l.resetsAtISO, let d = ISO8601DateFormatter().date(from: iso) else { return "" }
        let h = Int(max(0, d.timeIntervalSinceNow) / 3600)
        return h < 24 ? " · resets \(h)h" : " · resets \(h/24)d"
    }

    private func notify(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
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
        // Attach quick-reply/Enter/Kill actions for the kinds that have them.
        if kind == .needsInput || kind == .error { content.categoryIdentifier = kind.rawValue }
        if let host { content.threadIdentifier = host }
        var info: [String: String] = [:]
        if let host { info["host"] = host }
        if let session, !session.isEmpty { info["session"] = session }
        content.userInfo = info
        let req = UNNotificationRequest(identifier: id, content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show the banner even when the app is foregrounded (so a permission ping is
    /// visible while you're already in the app, and verifiable in the simulator).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// Tap → hand the host/session back to MeshStore to open that session.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let host = info["host"] as? String
        let session = (info["session"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        switch response.actionIdentifier {
        case Action.reply:
            // Quick-reply text → inject into the originating session.
            if let host, let text = (response as? UNTextInputNotificationResponse)?.userText,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onAction?(WatchCommand(kind: .agentSend, host: host, agent: session, text: text + "\n"))
            }
        case Action.enter:
            if let host { onAction?(WatchCommand(kind: .agentSend, host: host, agent: session, key: "enter")) }
        case Action.kill:
            if let host, let session { onAction?(WatchCommand(kind: .killAgent, host: host, agent: session)) }
        default:
            // Default tap (or any other) → open the session, as before.
            if let host { onOpen?(host, session) }
        }
        completionHandler()
    }
}

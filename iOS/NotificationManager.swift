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

    func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
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
    func evaluate(events: [AgentEvent], prefs: NotifPrefs) {
        for event in events {
            let key = "event-\(event.id)"
            guard !firedKeys.contains(key) else { continue }
            guard let kind = notifKind(for: event.level), prefs.allows(event) else { continue }
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
        if let host = info["host"] as? String {
            let session = (info["session"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            onOpen?(host, session)
        }
        completionHandler()
    }
}

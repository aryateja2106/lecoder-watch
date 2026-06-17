import Foundation
import UserNotifications

/// Local notifications for the monitoring layer: usage limits crossing a threshold,
/// a machine dropping offline, and agent count changes. Delivered to the phone (and
/// mirrored to the watch by watchOS automatically).
final class NotificationManager {
    static let shared = NotificationManager()
    private var firedKeys: Set<String> = []          // de-dupe within a session
    private var lastReachable: [String: Bool] = [:]
    private let usageThreshold = 85.0                  // notify when a limit is >85% used

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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

    func evaluate(events: [AgentEvent]) {
        for event in events {
            let key = "event-\(event.id)"
            guard !firedKeys.contains(key) else { continue }
            firedKeys.insert(key)
            notify(id: key,
                   title: eventNotificationTitle(event),
                   body: eventNotificationBody(event))
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
}

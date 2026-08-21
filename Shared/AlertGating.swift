import Foundation

/// Decides whether a machine-reachability notification may fire. Pure state machine
/// so `check-alert-gating.swift` can prove the flood is impossible: a connection that
/// flaps all afternoon produces at most one "went offline" per cooldown window, and
/// "back online" only ever fires as the answer to an offline alert the user actually
/// saw. (The 2026-08-20 report was 30+ banners in five minutes from exactly this
/// path with no gate at all.)
public struct ReachabilityAlertGate {
    public enum Alert { case wentOffline, backOnline }

    private var lastReachable: [String: Bool] = [:]
    private var lastOfflineAlertAt: [String: Date] = [:]
    private var notifiedOffline: Set<String> = []
    public let cooldown: TimeInterval

    public init(cooldown: TimeInterval = 10 * 60) {
        self.cooldown = cooldown
    }

    /// Feed every poll result in; fire a notification only when this returns non-nil.
    public mutating func evaluate(host: String, reachable: Bool, now: Date = Date()) -> Alert? {
        let previous = lastReachable[host]
        lastReachable[host] = reachable
        // First sighting and steady state are both silence; only transitions matter.
        guard let previous, previous != reachable else { return nil }
        if reachable {
            // Recovery is only news if the outage was announced. A flap cycle whose
            // offline half was suppressed stays entirely silent.
            guard notifiedOffline.remove(host) != nil else { return nil }
            return .backOnline
        }
        if let last = lastOfflineAlertAt[host], now.timeIntervalSince(last) < cooldown {
            return nil
        }
        lastOfflineAlertAt[host] = now
        notifiedOffline.insert(host)
        return .wentOffline
    }
}

/// Mirrors the daemon-side push dedupe (push.ts shouldSend): the same alert text for
/// the same session inside the window buzzes once. Claude's SubagentStop hook fires
/// per subagent, so one multi-agent turn used to land half a dozen identical banners.
public struct EventAlertDeduper {
    private var recent: [String: Date] = [:]
    public let window: TimeInterval

    public init(window: TimeInterval = 10 * 60) {
        self.window = window
    }

    public mutating func shouldAlert(host: String?, session: String?, title: String,
                                     body: String?, now: Date = Date()) -> Bool {
        let key = [host ?? "", session ?? "", title, body ?? ""].joined(separator: "\u{1f}")
        if let last = recent[key], now.timeIntervalSince(last) < window { return false }
        recent[key] = now
        // The map only grows while alerts keep landing; prune on the way through so a
        // long-lived phone process doesn't hoard every alert it ever saw.
        recent = recent.filter { now.timeIntervalSince($0.value) < window }
        return true
    }
}

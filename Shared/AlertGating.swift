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

// MARK: - One banner per session

/// Every alert about one session carries this identifier — meshd stamps it as the
/// `apns-collapse-id` (see `collapseId` in `meshd/push.ts`) and the phone reuses it as
/// the local `UNNotificationRequest` identifier. Two consequences, both the point:
/// APNs *replaces* a banner whose collapse id it has already delivered, so "Claude
/// stopped" overwrites "Claude needs attention" instead of stacking under it; and
/// because pushed and local alerts share one identifier space, one sweep
/// (`notificationIdsToClear`) clears both lanes.
public let meshNotificationPrefix = "mesh-"

/// APNs rejects an oversized collapse id outright — the alert is dropped, not merely
/// left uncollapsed — so the id is clamped rather than trusted to be short.
public let meshNotificationIdMaxBytes = 64

/// The usage-limit lane owns this namespace and arms its alerts hours ahead. Sweeping
/// one because no agent happens to be waiting would delete the "limit resets now"
/// banner the user pinned a session for.
public let meshReservedNotificationPrefix = "mesh-limit-"

/// `mesh-<host>-<session>`, sanitized to an ASCII charset that is safe in an HTTP
/// header value and identical byte-for-byte in TypeScript.
public func meshNotificationId(host: String, session: String) -> String {
    let raw = "\(meshNotificationPrefix)\(meshIdSafe(host))-\(meshIdSafe(session))"
    guard raw.utf8.count > meshNotificationIdMaxBytes else { return raw }
    // Keep a readable head and pin uniqueness with a hash of the whole string, so two
    // long names that share a prefix never collapse into each other's banner.
    return "\(String(raw.prefix(meshNotificationIdMaxBytes - 9)))-\(meshIdHash(raw))"
}

/// Does `id` name this host/session pair's banner?
///
/// Tolerant of the daemon spelling its own hostname differently from the name the app
/// paired under (`dataflowagents` vs `dataflow`) — APNs stamps the id with the daemon's
/// word for the machine, and the phone only ever knows its own. An exact-match-only
/// version of this is how the sweep would silently never fire on a real host.
///
/// `-` separates the two halves and is legal inside both, so an id like
/// `mesh-studio-legacy-api` has two readings and answers true to either. That is the
/// safe direction: the only caller treats a match as "might still be waiting", and a
/// banner that lingers one poll too long beats one that vanishes under a live prompt.
public func meshNotificationId(_ id: String, isFor host: String, session: String) -> Bool {
    if id == meshNotificationId(host: host, session: session) { return true }
    guard id.hasPrefix(meshNotificationPrefix) else { return false }
    let rest = id.dropFirst(meshNotificationPrefix.count)
    // Whole session name, never a suffix of one: `api` must not claim `legacy-api`.
    let tail = "-\(meshIdSafe(session))"
    guard rest.hasSuffix(tail) else { return false }
    return hostNamesMatch(String(rest.dropLast(tail.count)), host)
}

/// Which banners on screen no longer have a session waiting behind them.
///
/// `delivered` is what the OS is showing plus anything still queued — a session that
/// finished between two polls can have a banner scheduled but not yet landed, and one
/// that arrives a second after the work ended is exactly the alert this feature exists
/// to stop. Foreign identifiers are never returned: this sweep deletes notifications,
/// so anything it does not positively recognise stays put.
public func notificationIdsToClear(delivered: [String],
                                   attention: [(host: String, session: String)]) -> [String] {
    delivered.filter { id in
        guard id.hasPrefix(meshNotificationPrefix),
              !id.hasPrefix(meshReservedNotificationPrefix) else { return false }
        return !attention.contains { meshNotificationId(id, isFor: $0.host, session: $0.session) }
    }
}

/// Host and session names are user-chosen; this reduces them to characters that are
/// safe in an HTTP header value and one byte wide, which is also what makes the length
/// clamp above plain arithmetic instead of a UTF-8 boundary walk.
private func meshIdSafe(_ value: String) -> String {
    String(value.map { ch in
        ch.isASCII && (ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-") ? ch : "_"
    })
}

/// FNV-1a/32. Not security, just a short stable fingerprint — chosen because it is six
/// lines in both languages and needs no crypto import on either side.
private func meshIdHash(_ value: String) -> String {
    var hash: UInt32 = 0x811c_9dc5
    for byte in value.utf8 {
        hash ^= UInt32(byte)
        hash = hash &* 0x0100_0193
    }
    return String(format: "%08x", hash)
}

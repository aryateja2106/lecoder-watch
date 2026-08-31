import Foundation
import WidgetKit

/// The handful of facts a watch face can show, written by the watch app and read by
/// its complications.
///
/// Complications run in their own process on a timeline the system schedules, so they
/// cannot poll the mesh — they read the last thing the app knew, through the shared
/// app group container. Every glance therefore carries `updatedISO`: a complication
/// that shows a stale count without saying it is stale is worse than one that says
/// nothing.
struct WatchGlance: Codable, Hashable {
    struct Waiting: Codable, Hashable {
        var host: String
        var session: String
        var line: String
        /// Optional, not defaulted: a default value does NOT make the synthesised
        /// decoder tolerate a missing key, so `Bool = false` would throw on any glance
        /// written by 0.2.0 and blank the complication until the app next refreshed.
        var risky: Bool? = nil

        var isRisky: Bool { risky == true }
    }

    var updatedISO: String
    var waiting: [Waiting]
    var machinesUp: Int
    var machinesTotal: Int
    /// Sessions that were working but have gone quiet past the stall threshold —
    /// meshd 0.5.0's per-session status aged out, or the app's own derivation.
    /// Optional for the same decode-tolerance reason as `Waiting.risky` above: a
    /// glance written by an older app must keep decoding, or the complication
    /// blanks until the next refresh.
    var stalled: Int? = nil

    var stalledCount: Int { stalled ?? 0 }

    static let empty = WatchGlance(updatedISO: "", waiting: [], machinesUp: 0, machinesTotal: 0)

    var updated: Date? {
        parseISO(updatedISO)
    }

    /// Minutes since the app last wrote, or nil when it never has.
    func ageMinutes(now: Date = Date()) -> Int? {
        updated.map { max(0, Int(now.timeIntervalSince($0) / 60)) }
    }

    /// Older than this and the complication stops asserting a count it cannot stand
    /// behind. Fifteen minutes is roughly two of watchOS's background refresh slots.
    static let staleAfterMinutes = 15

    func isStale(now: Date = Date()) -> Bool {
        guard let age = ageMinutes(now: now) else { return true }
        return age >= Self.staleAfterMinutes
    }

    /// What the circular and inline families say, in the fewest characters that still
    /// mean something.
    func shortLabel(now: Date = Date()) -> String {
        if isStale(now: now) { return "—" }
        if !waiting.isEmpty { return String(waiting.count) }
        return machinesTotal == 0 ? "—" : "\(machinesUp)/\(machinesTotal)"
    }

    /// The line the rectangular family leads with.
    func headline(now: Date = Date()) -> String {
        if isStale(now: now) {
            guard let age = ageMinutes(now: now) else { return "Open to connect" }
            return "Last seen \(age)m ago"
        }
        if let first = waiting.first {
            return waiting.count == 1 ? first.session : "\(waiting.count) agents waiting"
        }
        if machinesTotal == 0 { return "No machines" }
        return machinesUp == machinesTotal ? "All machines up" : "\(machinesUp) of \(machinesTotal) up"
    }

    /// The second line, when there is room for one.
    func detail(now: Date = Date()) -> String {
        if isStale(now: now) { return "Tap to reconnect" }
        if let first = waiting.first {
            return waiting.count == 1 ? first.line : first.session
        }
        return machinesTotal == 0 ? "Pair one on your iPhone" : "Nothing waiting"
    }

    /// The three bands the rectangular family renders, with no branching left in the
    /// widget itself — so `check-glance` can assert every state headlessly.
    ///
    /// Exists because `headline`/`detail` drop the question the moment a second agent
    /// blocks: the headline becomes "2 agents waiting" and the detail collapses to a
    /// bare session name. The count is the least useful thing on the face; the question
    /// is the only part you can act on, and it disappeared exactly when things got busy.
    func entry(now: Date = Date()) -> (eyebrow: String, title: String, body: String) {
        if isStale(now: now) {
            guard let age = ageMinutes(now: now) else {
                return ("NOT CONNECTED", "Open LeSearch Mesh", "The watch has never reached your mesh.")
            }
            return ("LAST SEEN \(age)M AGO", "Tap to reconnect", "This count may be out of date.")
        }
        if let first = waiting.first {
            let eyebrow = waiting.count == 1 ? "WAITING ON YOU" : "\(waiting.count) WAITING"
            let title = "\(first.session) · \(shortHostName(first.host))"
            return (eyebrow, title, first.line)
        }
        // Below waiting on purpose: a question outranks a hunch. And only in this
        // rectangular band — the circular count stays reserved for the actionable
        // number, because "2" on a watch face must always mean "2 need you".
        if stalledCount > 0 {
            let eyebrow = stalledCount == 1 ? "1 GONE QUIET" : "\(stalledCount) GONE QUIET"
            return (eyebrow, "No output for a while",
                    machinesTotal == 0 ? "Open to check on it" : "\(machinesUp) of \(machinesTotal) machines up")
        }
        if machinesTotal == 0 {
            return ("NOT PAIRED", "Pair a machine", "Open LeSearch Mesh on your iPhone.")
        }
        return ("ALL CLEAR", "Nothing waiting on you", "\(machinesUp) of \(machinesTotal) machines up")
    }
}

// MARK: - The shared container

enum GlanceStore {
    /// Must match the App Group on both the watch app and its widget extension.
    static let appGroup = "group.com.lecoder.meshwatch"
    private static let key = "mesh.glance.v1"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func write(_ glance: WatchGlance) {
        guard let defaults, let data = try? JSONEncoder().encode(glance) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> WatchGlance {
        guard let defaults, let data = defaults.data(forKey: key),
              let glance = try? JSONDecoder().decode(WatchGlance.self, from: data) else { return .empty }
        return glance
    }
}

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
    }

    var updatedISO: String
    var waiting: [Waiting]
    var machinesUp: Int
    var machinesTotal: Int

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
        if isStale(now: now) { return "Open LeSearch Mesh" }
        if let first = waiting.first {
            return waiting.count == 1 ? first.line : first.session
        }
        return machinesTotal == 0 ? "Pair one on your iPhone" : "Nothing waiting"
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

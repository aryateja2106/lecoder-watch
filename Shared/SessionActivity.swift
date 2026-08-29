import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// The live card for one session: Lock Screen, Dynamic Island, and — on watchOS 11 and
/// later — the watch Smart Stack, for free. Static identity lives in the attributes;
/// everything that changes each poll lives in ContentState.
///
/// The identical type compiles into both the app and the widget extension, since both
/// pull in `Shared/`. ActivityKit is iOS-only, so the `#if` keeps the watch target —
/// which also compiles `Shared/` — building.
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stateRaw: String     // SessionState.rawValue
        var agentType: String    // "claude" / "codex" / "shell"
        var cpuPct: Double?
        var memLabel: String?
        var lastLine: String     // freshest output or event line
        /// Set only when the session is stopped waiting on a human, so the card can
        /// count the wait up on the Lock Screen without an update per second.
        var blockedSince: Date? = nil
        /// The verb for the affirmative and one line of consequence, when answering
        /// would do something destructive. See `classifyRisk`.
        var riskVerb: String? = nil
        var riskWhy: String? = nil
        /// Fleet liveness, so the card also answers "what is up right now" and not only
        /// "what is waiting". Optional and defaulted on purpose: an activity started by
        /// an older build is still in flight with these keys absent from its encoded
        /// state, and a non-optional field would fail its decode mid-life.
        var machinesOnline: Int? = nil
        var machinesTotal: Int? = nil

        var state: SessionState { SessionState(rawValue: stateRaw) ?? .unknown }

        /// Blocked is the only state worth a Lock Screen card that shouts. "Working" is
        /// wallpaper; this is the one that means the machine has stopped.
        var isBlocked: Bool { state.wantsAttentionState }
        var isRisky: Bool { riskWhy != nil }

        /// "2/3 machines online", or nil for a card from a build that did not send it.
        var fleetText: String? {
            guard let machinesOnline, let machinesTotal else { return nil }
            return fleetLine(online: machinesOnline, total: machinesTotal)
        }

        /// "38% · 1.2 GB", or nil when the daemon reported neither.
        var resourceText: String? {
            let cpu = cpuPct.map { String(format: "%.0f%%", $0) }
            let joined = [cpu, memLabel].compactMap { $0 }.joined(separator: " · ")
            return joined.isEmpty ? nil : joined
        }
    }

    var host: String       // as the app displays it
    var session: String    // the multiplexer session name == Agent.name
}
#endif

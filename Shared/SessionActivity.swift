import Foundation
#if canImport(ActivityKit)
import ActivityKit

// Live Activity for the pinned ("primary") coding session. Static identity (host +
// session name) lives in the attributes; everything that changes each poll lives in
// ContentState. The identical type compiles into BOTH the app and the widget
// extension (both pull in Shared/). ActivityKit is iOS-only, so the #if keeps the
// watchOS target — which also compiles Shared/ — building.
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stateRaw: String    // SessionState.rawValue
        var agentType: String   // "claude" / "codex" / "shell"
        var cpuPct: Double?
        var memLabel: String?
        var lastLine: String    // freshest output/event line, for the Lock Screen

        var state: SessionState { SessionState(rawValue: stateRaw) ?? .unknown }

        /// "38% · 1.2 GB" — the honest resource stand-in for Codync's cost line.
        var resourceText: String? {
            let cpu = cpuPct.map { String(format: "%.0f%%", $0) }
            let s = [cpu, memLabel].compactMap { $0 }.joined(separator: " · ")
            return s.isEmpty ? nil : s
        }
    }

    var host: String       // app display host, e.g. "arya-macbook-pro"
    var session: String    // rmux/tmux session == Agent.name
}
#endif

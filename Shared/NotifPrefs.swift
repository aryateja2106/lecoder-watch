import Foundation

// Notification classification + per-source/per-type toggles. Foundation-only and
// pure, so the headless self-check (Tests/NotifLogicCheck.swift) can exercise it
// with plain `swiftc`, and so the watch target can decode the same prefs.

/// The three notify-worthy categories. Any other `level` (routine "info" output)
/// classifies to nil and never raises a notification.
enum NotifKind: String, Codable, CaseIterable {
    case needsInput = "needs-input"
    case finished
    case error

    /// Loud / break-through for the two the human must act on; quiet for completion.
    var isLoud: Bool { self == .needsInput || self == .error }

    var label: String {
        switch self {
        case .needsInput: return "Needs input"
        case .finished:   return "Finished"
        case .error:      return "Errors"
        }
    }
}

/// Map a producer `level` string onto a NotifKind, tolerating synonyms across the
/// claude/codex/pi hooks. nil = routine output → no ping.
func notifKind(for level: String?) -> NotifKind? {
    switch (level ?? "").lowercased() {
    case "needs-input", "needs_input", "input", "permission", "approval", "ask", "waiting", "prompt", "confirm":
        return .needsInput
    case "finished", "done", "complete", "completed", "stop", "success", "idle":
        return .finished
    case "error", "fail", "failed", "failure", "crash", "denied", "warning":
        return .error
    default:
        return nil
    }
}

/// Per-source + per-type notification toggles, persisted as JSON in UserDefaults.
/// Only an explicit `false` silences; unknown keys default to on.
struct NotifPrefs: Codable, Equatable {
    var sources: [String: Bool]   // keyed by lowercased source: claude/codex/pi
    var types: [String: Bool]     // keyed by NotifKind.rawValue

    static let knownSources = ["claude", "codex", "pi"]

    static let `default` = NotifPrefs(
        sources: Dictionary(uniqueKeysWithValues: knownSources.map { ($0, true) }),
        types: Dictionary(uniqueKeysWithValues: NotifKind.allCases.map { ($0.rawValue, true) })
    )

    func sourceEnabled(_ source: String?) -> Bool {
        guard let source, let on = sources[source.lowercased()] else { return true }
        return on
    }

    func typeEnabled(_ kind: NotifKind) -> Bool { types[kind.rawValue] ?? true }

    /// Should this event raise a notification? Routine (unclassified) never does.
    func allows(_ event: AgentEvent) -> Bool {
        guard let kind = notifKind(for: event.level) else { return false }
        return typeEnabled(kind) && sourceEnabled(event.source)
    }
}

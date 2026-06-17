import Foundation

// Headless self-check for the notification classification + toggle gating.
// Run: swiftc Shared/Models.swift Shared/NotifPrefs.swift Tests/NotifLogicCheck.swift -o /tmp/notifcheck && /tmp/notifcheck
// Not part of any app target (Tests/ isn't in project.yml sources).

@main
enum NotifLogicCheck {
    static func main() {
        var failures = 0
        func check(_ cond: Bool, _ msg: String) {
            if !cond { failures += 1; print("FAIL: \(msg)") }
        }
        func ev(_ level: String?, source: String? = "claude") -> AgentEvent {
            AgentEvent(id: "1", host: "my-mac", source: source, session: "watch-shell",
                       level: level, title: "t", body: "b", createdISO: "2026-01-01T00:00:00Z")
        }

        // classify: synonyms + case-insensitivity, routine → nil
        check(notifKind(for: "needs-input") == .needsInput, "needs-input classifies")
        check(notifKind(for: "Permission") == .needsInput, "permission (any case) → needs-input")
        check(notifKind(for: "done") == .finished, "done → finished")
        check(notifKind(for: "error") == .error, "error → error")
        check(notifKind(for: "warning") == .error, "warning → error (loud)")
        check(notifKind(for: "info") == nil, "info is routine → no notification")
        check(notifKind(for: nil) == nil, "missing level is routine")
        check(notifKind(for: "chatter") == nil, "unknown level is routine")

        // loudness: needs-input + error break through; finished is quiet
        check(NotifKind.needsInput.isLoud, "needs-input is loud")
        check(NotifKind.error.isLoud, "error is loud")
        check(!NotifKind.finished.isLoud, "finished is quiet")

        // default prefs: notify the three kinds, never routine
        let def = NotifPrefs.default
        check(def.allows(ev("needs-input")), "default allows needs-input")
        check(def.allows(ev("done")), "default allows finished")
        check(def.allows(ev("error")), "default allows error")
        check(!def.allows(ev("info")), "default drops routine output")

        // per-type toggle off
        var typeOff = NotifPrefs.default
        typeOff.types[NotifKind.error.rawValue] = false
        check(!typeOff.allows(ev("error")), "error type off silences errors")
        check(typeOff.allows(ev("needs-input")), "error type off leaves needs-input")

        // per-source toggle off
        var srcOff = NotifPrefs.default
        srcOff.sources["codex"] = false
        check(!srcOff.allows(ev("needs-input", source: "codex")), "codex off silences codex")
        check(srcOff.allows(ev("needs-input", source: "claude")), "codex off leaves claude")

        // unknown source defaults on
        check(def.allows(ev("error", source: "node")), "unknown source defaults on")
        check(def.allows(ev("error", source: nil)), "nil source defaults on")

        // Codable round-trip (UserDefaults persistence)
        let data = try! JSONEncoder().encode(srcOff)
        let back = try! JSONDecoder().decode(NotifPrefs.self, from: data)
        check(back == srcOff, "prefs survive JSON round-trip")

        if failures == 0 { print("OK: all notification-logic checks passed") }
        exit(failures == 0 ? 0 : 1)
    }
}

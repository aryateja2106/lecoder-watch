import Foundation

// Run: swiftc Shared/Models.swift scripts/check-session-state.swift -o /tmp/css && /tmp/css

@main
struct CheckSessionState {
    static func main() {
        // shell prompts → idle/ready (incl. zsh-theme glyphs)
        assert(sessionState(lines: ["~", "user@mac %"], attached: false) == .idle)
        assert(sessionState(lines: ["$ ls", "file.txt", "$"], attached: true) == .idle)
        assert(sessionState(lines: ["~", "?→"], attached: true) == .idle)
        assert(sessionState(lines: ["~/Projects ❯"], attached: true) == .idle)

        // decision prompt → waiting (needs the human), beats everything
        assert(sessionState(lines: ["Do you want to proceed?", "❯ 1. Yes", "  2. No"], attached: true) == .waiting)
        assert(sessionState(lines: ["Overwrite? (y/n)"], attached: true) == .waiting)

        // busy / thinking → running
        assert(sessionState(lines: ["Running tests...", "compiling"], attached: true) == .running)
        assert(sessionState(lines: ["✻ Baking… (esc to interrupt)"], attached: true) == .running)

        // current failure (no prompt back yet) → error
        assert(sessionState(lines: ["fatal: not a git repository"], attached: true) == .error)

        // error already past, prompt returned → idle, not error
        assert(sessionState(lines: ["bash: foo: command not found", "$"], attached: true) == .idle)

        // nothing → unknown when detached
        assert(sessionState(lines: [], attached: false) == .unknown)

        print("check-session-state: OK")
    }
}

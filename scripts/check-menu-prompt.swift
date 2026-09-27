// check-menu-prompt — a Choose card must carry the question, not just the answers.
//
// The card used to read "Choose · 1. Yes · 2. Yes, and always allow · 3. No" with nothing
// saying what was being allowed: the phone and the watch were asking the owner to approve a
// command they could not see from that screen. These fixtures are verbatim pane captures.
import Foundation

@main struct CheckMenuPrompt {
    static func main() {
        let permission = """
         Bash command

           rm -rf ~/Library/Caches/pip
           Clear the pip cache

         Do you want to proceed?
         ❯ 1. Yes
           2. Yes, and always allow access to ~/Library from this project
           3. No

         Esc to cancel · Tab to amend
        """.components(separatedBy: "\n")
        guard let menu = AgentMenu.parse(lines: permission) else { fail("permission menu not recognised") }
        expect(menu.prompt == "Do you want to proceed?", "the question above the list is the prompt, got \(menu.prompt ?? "nil")")

        // A TUI that draws a box around the question: the edges must not survive.
        let boxed = """
         │ Write config.toml?                        │
         ❯ 1. Yes
           2. No
         Enter to confirm · Esc to cancel
        """.components(separatedBy: "\n")
        guard let boxedMenu = AgentMenu.parse(lines: boxed) else { fail("boxed menu not recognised") }
        expect(boxedMenu.prompt == "Write config.toml?", "box edges stripped, got \(boxedMenu.prompt ?? "nil")")

        // The trust prompt: unnumbered rows, the sentence above them is the question.
        let trust = """
          Claude Code'll be able to read, edit, and execute files here.
         ❯ No, exit
           Yes, I trust this folder
         enter select · esc cancel
        """.components(separatedBy: "\n")
        guard let trustMenu = AgentMenu.parse(lines: trust) else { fail("trust prompt not recognised") }
        expect(trustMenu.prompt?.hasPrefix("Claude Code") == true,
               "the trust sentence is the prompt, got \(trustMenu.prompt ?? "nil")")

        // Claude Code's real trust prompt, captured verbatim from a pane on 2026-09-23.
        // The line immediately above the options is a LINK ("Security guide"); the question
        // is six lines up and wraps mid-sentence. Taking the nearest line put "Security
        // guide" on the card, so the owner was approving a link label.
        let realTrust = """
        ────────────────────────────────────────────────────────────────────────────────
         Accessing workspace:

         /private/tmp/trust-probe-77843

         Quick safety check: Is this a project you created or one you trust? (Like your
         own code, a well-known open source project, or work from your team). If not,
         take a moment to review what's in this folder first.

         Claude Code'll be able to read, edit, and execute files here.

         Security guide

         ❯ No, exit
           Yes, I trust this folder

         Enter to confirm · Esc to cancel
        """.components(separatedBy: "\n")
        guard let realMenu = AgentMenu.parse(lines: realTrust) else { fail("the real trust prompt is not recognised") }
        expect(realMenu.prompt == "Quick safety check: Is this a project you created or one you trust?",
               "the question wins over the nearer link label, cut at the question mark, got \(realMenu.prompt ?? "nil")")
        expect(realMenu.options.count == 2 && realMenu.options[1].label == "Yes, I trust this folder",
               "both trust options survive, got \(realMenu.options.map(\.label))")

        // No question printed: nil, never a stray option or footer masquerading as one.
        let bare = """
         ❯ 1. Yes
           2. No
         Esc to cancel
        """.components(separatedBy: "\n")
        if let bareMenu = AgentMenu.parse(lines: bare) {
            expect(bareMenu.prompt == nil, "no line above the list means no prompt, got \(bareMenu.prompt ?? "nil")")
        }
        print("check-menu-prompt: ok (5 fixtures)")
    }

    static func expect(_ ok: Bool, _ what: String) { if !ok { print("FAIL: \(what)"); exit(1) } }
    static func fail(_ what: String) -> Never { print("FAIL: \(what)"); exit(1) }
}

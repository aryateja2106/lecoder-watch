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

        // No question printed: nil, never a stray option or footer masquerading as one.
        let bare = """
         ❯ 1. Yes
           2. No
         Esc to cancel
        """.components(separatedBy: "\n")
        if let bareMenu = AgentMenu.parse(lines: bare) {
            expect(bareMenu.prompt == nil, "no line above the list means no prompt, got \(bareMenu.prompt ?? "nil")")
        }
        print("check-menu-prompt: ok (4 fixtures)")
    }

    static func expect(_ ok: Bool, _ what: String) { if !ok { print("FAIL: \(what)"); exit(1) } }
    static func fail(_ what: String) -> Never { print("FAIL: \(what)"); exit(1) }
}

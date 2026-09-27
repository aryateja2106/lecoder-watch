// check-agent-menu.swift — AgentMenu recognises the menus real agents print and picks options with the right keys.
//
// Fixtures are verbatim pane captures from Claude Code on the Pi, 2026-09-22: the Bash
// permission list (four numbered rows, ❯ on 1) and the trust-folder prompt (two unnumbered
// rows, ❯ on "No, exit"), plus a y/N question. Pure; compiled by check-all.sh.
import Foundation

@main struct CheckAgentMenu {
    static func main() {
        let permission = """
         Bash command
         Tip: auto mode handles these prompts for you — choose "switch to auto mode"
         below

           date > /tmp/approve-test.txt
           Write current date to /tmp/approve-test.txt

         Do you want to proceed?
         ❯ 1. Yes
           2. Yes, and always allow access to /tmp from this project
           3. Yes, and switch to auto mode · auto mode handles these prompts for you
           4. No

         Esc to cancel · Tab to amend
        """.components(separatedBy: "\n")
        guard let menu = AgentMenu.parse(lines: permission) else { fail("permission menu not recognised") }
        expect(menu.options.map(\.index) == [1, 2, 3, 4], "four numbered options, got \(menu.options.map(\.index))")
        expect(menu.highlighted == 1, "❯ on 1")
        expect(menu.options[3].label == "No", "last label is No, got \(menu.options[3].label)")
        expect(menu.keys(toPick: 1) == ["enter"], "picking the highlighted row is just Enter")
        expect(menu.keys(toPick: 4) == ["down", "down", "down", "enter"], "picking 4 is three Downs then Enter, got \(menu.keys(toPick: 4))")
        expect(menu.footer == "Esc to cancel · Tab to amend", "footer kept, got \(menu.footer ?? "nil")")

        let trust = """
          Claude Code'll be able to read, edit, and execute files
          here.

          Security guide

         ❯ No, exit
           Yes, I trust this folder

         Enter to confirm · Esc to cancel
        """.components(separatedBy: "\n")
        guard let t = AgentMenu.parse(lines: trust) else { fail("trust prompt not recognised") }
        expect(t.options.map(\.label) == ["No, exit", "Yes, I trust this folder"], "trust options, got \(t.options.map(\.label))")
        expect(t.highlighted == 1, "❯ on No, exit")
        expect(t.keys(toPick: 2) == ["down", "enter"], "trusting is Down then Enter, got \(t.keys(toPick: 2))")

        let yn = ["Overwrite build/? [y/N]"]
        guard let y = AgentMenu.parse(lines: yn) else { fail("y/N not recognised") }
        expect(y.typed && y.text(toPick: 1) == "y" && y.text(toPick: 2) == "n" && y.highlighted == 2, "y/N typed answers, default No")

        let idle = ["❯ ", "  ~/lesearch-probe", "  ⏵⏵ accept edits on (shift+tab to cycle) · ← 1 agent"]
        expect(AgentMenu.parse(lines: idle) == nil, "an idle prompt line is not a menu")
        let done = ["● Done — file written.", "", "❯ "]
        expect(AgentMenu.parse(lines: done) == nil, "a bare prompt after output is not a menu")
        let typedPrompt = ["❯ run exactly this bash command", "  ~/lesearch-probe", "  [OMC#4.13.5] | ctx:[#---------]8%", "  ⏸ manual mode on · ← 1 agent"]
        expect(AgentMenu.parse(lines: typedPrompt) == nil, "a typed prompt over the status rows is not a menu")
        print("check-agent-menu: OK")
    }

    static func expect(_ ok: Bool, _ what: String) { if !ok { fail(what) } }
    static func fail(_ what: String) -> Never { print("check-agent-menu: FAIL — \(what)"); exit(1) }
}

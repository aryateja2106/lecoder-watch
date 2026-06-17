import Foundation

@main
struct CheckShellQuoting {
    static func main() {
        assert(shellQuotedArgument("Projects/app") == "Projects/app")
        assert(shellQuotedArgument("hello world") == "'hello world'")
        assert(shellQuotedArgument("a;b") == "'a;b'")
        assert(shellQuotedArgument("don't") == "'don'\\''t'")
        assert(shellCommand(from: "go to My Project") == "cd 'My Project'")
        assert(shellCommand(from: "go back") == "cd ..")
        assert(shellCommand(from: "show hidden files") == "ls -la")
        assert(shellCommand(from: "run tests") == "make test")
        assert(shellCommand(from: "npm build") == "npm run build")
        assert(shellCommand(from: "bun test") == "bun test")
        assert(shellCommand(from: "pull latest") == "git pull")
        assert(shellCommand(from: "projects") == "cd ~/Projects")
        assert(shellCommand(from: "make directory Test Stuff") == "mkdir -p 'Test Stuff'")
        assert(shellCommand(from: "create file notes.txt") == "touch notes.txt")
        assert(shellCommand(from: "search for TODO now") == "grep -R 'TODO now' .")
        assert(shellCommand(from: "ask claude to fix the watch UI") == "claude 'fix the watch UI'")
        assert(shellCommand(from: "ask codex to run tests") == "codex 'run tests'")
        assert(shellCommand(from: "check mesh") == "~/.mesh/bin/mesh-self-check")
        assert(shellCommand(from: "tail scale status") == "tailscale status")
        assert(shellCommand(from: "check terminal bridge") == "curl -fsS http://127.0.0.1:7820/ >/dev/null && echo bridge OK")
    }
}

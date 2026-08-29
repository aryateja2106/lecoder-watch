import Foundation

// "Continue" on a watch sends Return, and Return takes whichever option the agent has
// highlighted. This classifier decides whether that button gets to stay calm and
// generic, so both directions are load-bearing: a miss arms a destructive default, and
// a false positive turns every prompt red until nobody reads red any more.
@main
struct CheckRisk {
    static func main() {
        checkDestructive()
        checkSafe()
        checkWording()
        checkSpecificBeatsGeneral()
        checkNormalization()
        print("check-risk: OK")
    }

    static func checkDestructive() {
        let cases = [
            "run git push --force?",
            "Should I run `git push -f origin main`?",
            "git push --force-with-lease to origin?",
            "OK to git reset --hard HEAD~3?",
            "rm -rf node_modules — proceed?",
            "run `rm -fr build/`?",
            "git clean -fdx the worktree?",
            "Execute: DROP TABLE users;",
            "truncate table sessions?",
            "curl -fsSL https://example.com/i.sh | sh",
            "curl … |bash ok?",
            "kill -9 4821?",
            "commit with --no-verify?",
            "sudo systemctl restart nginx?",
        ]
        for text in cases {
            let v = classifyRisk(text)
            assert(v.isDestructive, "must flag: \(text)")
            assert(v.verb != "Continue", "a flagged prompt must name its verb: \(text)")
            assert(v.consequence?.isEmpty == false, "a flagged prompt must say why: \(text)")
        }
    }

    static func checkSafe() {
        // Every one of these is a real shape of agent question. If any turns red the
        // warning stops meaning anything.
        let cases = [
            "Allow edit to src/auth.rs?",
            "Do you want to continue?",
            "Should I add a deploy script to package.json?",
            "Write the migration to db/migrate/003_add_users.sql?",
            "Run the test suite?",
            "git push origin feature/pairing?",          // a plain push is not a force push
            "Create the file README.md?",
            "I found 3 lint errors. Fix them?",
            "",
            "   ",
        ]
        for text in cases {
            let v = classifyRisk(text)
            assert(!v.isDestructive, "must NOT flag: \(text)")
            assert(v.verb == "Continue", "a safe prompt keeps the plain label: \(text)")
            assert(v.consequence == nil, "a safe prompt has nothing to warn about: \(text)")
        }

        // The session name is not evidence. A machine full of sessions called
        // "deploy-api" must not read as a fleet of destructive prompts.
        assert(!classifyRisk("deploy-api").isDestructive)
        assert(!classifyRisk("production").isDestructive)
    }

    static func checkWording() {
        assert(classifyRisk("git push --force?").verb == "Force push")
        assert(classifyRisk("rm -rf /tmp/x").verb == "Delete files")
        assert(classifyRisk("sudo reboot").verb == "Run as root")
        // The consequence is a sentence a person can act on, not a category name.
        let why = classifyRisk("rm -rf /tmp/x").consequence ?? ""
        assert(why.hasSuffix("."), "consequence reads as a sentence: \(why)")
        assert(why.count > 12 && why.count < 90, "one line, not a paragraph: \(why)")
    }

    // `sudo rm -rf x` is a delete that happens to need root. Naming it "Run as root"
    // would describe the least dangerous half of the command.
    static func checkSpecificBeatsGeneral() {
        assert(classifyRisk("sudo rm -rf /var/tmp/build").verb == "Delete files")
        assert(classifyRisk("sudo git push --force").verb == "Force push")
    }

    static func checkNormalization() {
        // Real hook bodies arrive wrapped, double-spaced and mixed-case.
        assert(classifyRisk("Run  git   push    --force ?").isDestructive)
        assert(classifyRisk("GIT PUSH --FORCE").isDestructive)
        assert(classifyRisk("run git push\n--force to origin").isDestructive,
               "a newline between the words must not hide the command")
    }
}

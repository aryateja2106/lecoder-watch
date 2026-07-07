import Foundation

@main
struct CheckLimitHelpers {
    static func main() {
        assert(LimitHelpers.status(usedPct: nil) == .available)
        assert(LimitHelpers.status(usedPct: 84.9) == .available)
        assert(LimitHelpers.status(usedPct: 85) == .warning)
        assert(LimitHelpers.status(usedPct: 95) == .blocked)
        assert(LimitHelpers.remainingPct(usedPct: 18.2) == 82)
        assert(LimitHelpers.remainingPct(usedPct: 100) == 0)
        assert(LimitHelpers.isSessionLimit(label: "Claude Session"))
        assert(!LimitHelpers.isSessionLimit(label: "Credits"))
        assert(LimitHelpers.isContinueCommand(" continue\n"))
        assert(!LimitHelpers.isContinueCommand("git status"))

        let now = Date(timeIntervalSince1970: 1_000)
        let reset = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_000 + 46 * 60))
        assert(LimitHelpers.resetCountdown(from: reset, now: now) == "Resets in 46m")

        print("check-limit-helpers: OK")
    }
}

import Foundation

// Run: swiftc Shared/Models.swift Shared/LimitHelpers.swift scripts/check-limit-helpers.swift -o /tmp/clh && /tmp/clh

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

        // Reset-aware isBlocked: a passed reset unblocks even at 96%; a future reset stays blocked.
        let past = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 500))
        let future = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 5_000))
        assert(!LimitHelpers.isBlocked(UsageLimit(label: "Session", usedPct: 96, resetsAtISO: past), now: now))
        assert(LimitHelpers.isBlocked(UsageLimit(label: "Session", usedPct: 96, resetsAtISO: future), now: now))
        // No reset info: falls back to pct-only.
        assert(LimitHelpers.isBlocked(UsageLimit(label: "Session", usedPct: 96, resetsAtISO: nil), now: now))

        print("check-limit-helpers: OK")
    }
}

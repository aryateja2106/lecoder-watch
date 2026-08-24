import Foundation

enum LimitStatus: String {
    case available
    case warning
    case blocked

    var label: String {
        switch self {
        case .available: return "Available"
        case .warning: return "Getting close"
        case .blocked: return "Limit reached"
        }
    }
}

enum LimitHelpers {
    static let blockedThreshold = 95.0
    static let warningThreshold = 85.0
    static let clearedThreshold = 90.0

    /// Remaining-budget levels worth interrupting someone for, richest first.
    /// These are about *deciding where to spend* across several subscriptions, so
    /// they fire early — a warning at 15% left arrives after the decision is made.
    static let remainingAlertTiers: [Int] = [50, 25]

    /// The tier a limit has dropped into, or nil while it is still above all of them.
    /// Returns the *lowest* tier crossed so a jump from 60% to 20% left reports 25,
    /// not both — one alert per crossing, not one per tier passed.
    static func crossedTier(remainingPct: Int) -> Int? {
        remainingAlertTiers.filter { remainingPct <= $0 }.min()
    }

    /// Every tier at or above the one crossed. Marking these as already-fired stops
    /// a later poll from re-announcing a level the user has now passed.
    static func tiersAtOrAbove(_ tier: Int) -> [Int] {
        remainingAlertTiers.filter { $0 >= tier }
    }

    static func status(usedPct: Double?) -> LimitStatus {
        guard let pct = usedPct else { return .available }
        if pct >= blockedThreshold { return .blocked }
        if pct >= warningThreshold { return .warning }
        return .available
    }

    static func isBlocked(usedPct: Double?) -> Bool {
        status(usedPct: usedPct) == .blocked
    }

    /// Reset-aware: a limit whose reset time has passed is never blocked, even if a
    /// stale usedPct snapshot still reads >=95% before the next /usage poll lands.
    static func isBlocked(_ limit: UsageLimit, now: Date = Date()) -> Bool {
        if let d = resetDate(from: limit.resetsAtISO), d <= now { return false }
        return isBlocked(usedPct: limit.usedPct)
    }

    static func remainingPct(usedPct: Double?) -> Int? {
        guard let pct = usedPct else { return nil }
        return max(0, min(100, Int((100 - pct).rounded())))
    }

    static func resetDate(from iso: String?) -> Date? {
        guard let iso else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: iso) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso)
    }

    /// Human countdown like OpenUsage: "Resets in 46m" or "Resets 10:40 AM".
    static func resetCountdown(from iso: String?, now: Date = Date()) -> String? {
        guard let date = resetDate(from: iso) else { return nil }
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "Reset now" }
        if seconds < 3600 {
            let minutes = max(1, Int(seconds / 60))
            return "Resets in \(minutes)m"
        }
        if seconds < 86400 {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return minutes > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(hours)h"
        }
        return "Resets \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    static func limitKey(providerId: String, label: String) -> String {
        "\(providerId.lowercased())-\(label.lowercased())"
    }

    static func isSessionLimit(label: String) -> Bool {
        label.lowercased().contains("session")
    }

    static func isContinueCommand(_ command: String) -> Bool {
        command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "continue"
    }

    static func providerId(for agentType: String?) -> String? {
        guard let agentType else { return nil }
        switch agentType.lowercased() {
        case "claude": return "claude"
        case "codex": return "codex"
        default: return nil
        }
    }
}

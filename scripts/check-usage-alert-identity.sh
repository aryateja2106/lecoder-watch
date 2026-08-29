#!/bin/sh
# The usage-alert dedup key must be exactly as fine-grained as the banner the user
# reads. It was not: the key spliced the raw OpenUsage reset ISO (seconds and
# fractional seconds) while the text drops seconds, so a reset time drifting from
# 2:30:01 to 2:30:04 minted a fresh key under a word-for-word identical banner and
# the same alert re-fired roughly hourly.
#
# This does NOT grep for a string. It cuts the pure functions out of
# iOS/NotificationManager.swift between the PURE-ALERT-IDENTITY markers, compiles
# that real source, and runs it — so reverting the fix in the app file fails here.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/iOS/NotificationManager.swift"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sed -n '/PURE-ALERT-IDENTITY-BEGIN/,/PURE-ALERT-IDENTITY-END/p' "$SRC" > "$TMP/extracted.swift"
if ! grep -q 'PURE-ALERT-IDENTITY-END' "$TMP/extracted.swift"; then
  echo "check-usage-alert-identity: markers missing from $SRC — nothing to test"
  exit 1
fi

{
  echo 'import Foundation'
  echo 'enum AlertIdentity {'
  cat "$TMP/extracted.swift"
  echo '}'
} > "$TMP/subject.swift"

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

func iso(_ d: Date, fractional: Bool = false) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
    return f.string(from: d)
}

// A reset three days out renders through resetCountdown's absolute branch —
// "Resets Aug 27, 2026 at 2:30 PM" — which is the text in the user's screenshot.
let now = Date(timeIntervalSince1970: 1_756_000_000)
let base = now.addingTimeInterval(3 * 86_400)

// 1. The invariant that was broken: two polls share a key exactly when they render
//    the same words. Not "close enough" — identical, in both directions.
let offsets: [TimeInterval] = [0, 1, 4, 29, 30, 59, 60, 61, 119, 120, 3600, 5 * 3600]
for a in offsets {
    for b in offsets {
        let da = base.addingTimeInterval(a), db = base.addingTimeInterval(b)
        let sameKey = AlertIdentity.alertWindow(from: iso(da)) == AlertIdentity.alertWindow(from: iso(db))
        let sameText = LimitHelpers.resetCountdown(from: iso(da), now: now)
            == LimitHelpers.resetCountdown(from: iso(db), now: now)
        assert(sameKey == sameText,
               "+\(a)s vs +\(b)s: key-same=\(sameKey) but text-same=\(sameText) — the gate and the banner disagree")
    }
}

// 2. Jitter inside one displayed minute must not re-fire, whatever precision the
//    daemon sends.
let jitterA = base.addingTimeInterval(1), jitterB = base.addingTimeInterval(4)
assert(AlertIdentity.alertWindow(from: iso(jitterA)) == AlertIdentity.alertWindow(from: iso(jitterB)))
assert(AlertIdentity.alertWindow(from: iso(jitterA, fractional: true))
       == AlertIdentity.alertWindow(from: iso(jitterB)))

// 3. Over-suppression is worse than the flood: a genuinely new window still alerts.
let nextWindow = base.addingTimeInterval(5 * 3600)
assert(AlertIdentity.alertWindow(from: iso(base)) != AlertIdentity.alertWindow(from: iso(nextWindow)))
assert(AlertIdentity.alertWindow(from: iso(base)) != AlertIdentity.alertWindow(from: iso(base.addingTimeInterval(60))))

// 4. A missing reset time still yields one stable, non-empty key.
let none = AlertIdentity.alertWindow(from: nil)
assert(!none.isEmpty)
assert(none == AlertIdentity.alertWindow(from: nil))
assert(none != AlertIdentity.alertWindow(from: iso(base)))

// 5. Title and body must state the same number. crossedTier(remainingPct: 0) is 25,
//    so the old tier-interpolated title read "25% left" over a body reading "0% left".
func percent(_ s: String) -> Int? {
    guard let r = s.range(of: #"(\d+)% left"#, options: .regularExpression) else { return nil }
    return Int(s[r].replacingOccurrences(of: "% left", with: ""))
}
let limit = UsageLimit(label: "Fable", usedPct: nil, resetsAtISO: iso(base), periodDurationMs: nil)
for used in [0.0, 40.0, 51.0, 74.6, 80.0, 95.0, 99.9, 100.0] {
    let remaining = LimitHelpers.remainingPct(usedPct: used) ?? 100
    let title = AlertIdentity.tierAlertTitle(provider: "Claude", label: limit.label, remainingPct: remaining)
    let body = AlertIdentity.warningBody(limit: limit, pct: used)
    assert(percent(title) == remaining, "title \"\(title)\" does not report \(remaining)% left")
    assert(percent(title) == percent(body), "title \"\(title)\" contradicts body \"\(body)\"")
}
// The exact banner from the screenshot: 0% left must never be titled 25%.
let zero = AlertIdentity.tierAlertTitle(provider: "Claude", label: "Fable", remainingPct: 0)
assert(percent(zero) == 0, "titled \"\(zero)\" — that is crossedTier, not what is left")
assert(percent(zero) != LimitHelpers.crossedTier(remainingPct: 0))

print("check-usage-alert-identity: ok")
SWIFT

/usr/bin/swiftc -Onone -o "$TMP/run" "$TMP/subject.swift" "$TMP/main.swift" \
  "$ROOT/Shared/Models.swift" "$ROOT/Shared/LimitHelpers.swift" \
  "$ROOT/Shared/RiskClassifier.swift" "$ROOT/Shared/AgentNotifications.swift" 2>"$TMP/err" || {
  echo "check-usage-alert-identity: does not compile"; tail -20 "$TMP/err"; exit 1; }
"$TMP/run"

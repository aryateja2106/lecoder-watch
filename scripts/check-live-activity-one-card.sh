#!/bin/sh
# One card per wait, one banner per event. Guards the routing that let 5-7 stale Live
# Activities pile up: a start for every alert-worthy event, fanned out to every
# push-to-start token, with nothing able to end the cards (no update token was ever
# uploaded for a push-started card) and the keep-one sweep running once per cold launch.
# ponytail: structural greps for the Swift side; ActivityKit is only provable on-device.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "check-live-activity-one-card: FAIL — $*" >&2; exit 1; }

# 1. push.ts routes a start for a live, addressable session as an update; an update
#    with no token reaches nothing instead of starting a second card.
command -v bun >/dev/null 2>&1 || { echo "check-live-activity-one-card: SKIP (bun not installed)"; exit 0; }
cd "$ROOT/install/payload/meshd"
bun -e '
const { laRoute } = await import("./push.ts");
const tok = (kind, session, token) => ({ kind, session, token, env: "prod", addedISO: "" });
const all = [tok("start", undefined, "s1"), tok("start", undefined, "s2"), tok("update", "api", "u-api")];
let r = laRoute(all, "start", "api");
if (r.event !== "update" || r.targets.length !== 1 || r.targets[0].token !== "u-api")
  throw new Error("a start for a live session must become an update to its one token, got " + JSON.stringify(r));
r = laRoute(all, "start", "fresh");
if (r.event !== "start" || r.targets.length !== 2)
  throw new Error("a start for a new session reaches every start token, got " + JSON.stringify(r));
r = laRoute(all, "update", "fresh");
if (r.event !== "update" || r.targets.length !== 0)
  throw new Error("an update with no token must reach nothing, never fall back to a start, got " + JSON.stringify(r));
r = laRoute(all, "end", "api");
if (r.targets.length !== 1) throw new Error("end must reach the session update token");
'
cd "$ROOT"

# 2. server.ts sends ONE Live Activity push per alert-worthy event, and no alert on it.
block="$(sed -n '/const worthPushing = passesPushGate/,/^}/p' install/payload/meshd/server.ts)"
echo "$block" | grep -q 'fresh ? "start" : "update"' || fail "server.ts must start a card once per wait and only update it after"
if echo "$block" | grep -q 'pushLiveActivity("start"'; then fail "server.ts still sends an unconditional start"; fi
if echo "$block" | grep -qE 'alert \}|alert: \{ title'; then fail "the Live Activity push must not carry an alert (the alert push is the one banner)"; fi

# 3. The app reconciles on every snapshot and observes push-started cards.
grep -q 'activityUpdates' iOS/LiveActivityController.swift || fail "LiveActivityController never observes Activity.activityUpdates"
sed -n '/func sync(snapshot/,/^    }/p' iOS/LiveActivityController.swift | grep -q 'reconcile(keeping:' \
  || fail "sync(snapshot:) must reconcile existing activities every time"

# 4. mesh-hook never uses a transcript path as a notification body.
if grep -q 'transcript_path' install/payload/bin/mesh-hook; then fail "mesh-hook still falls back to a transcript path as a body"; fi

echo "check-live-activity-one-card: OK (start once per wait, no alert on the card, reconcile every snapshot, no path bodies)"

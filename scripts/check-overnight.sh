#!/bin/sh
# check-overnight.sh — the 2026-09-21 regression suite: every check the overnight run added, with its live half on.
#
# check-all.sh already runs the structural halves of these (it globs scripts/check-*.sh). This
# runner turns the LIVE halves on — the fleet over Tailscale, the simulators, the local model
# servers — which check-all cannot assume in CI. Run it on the Mac that owns the fleet:
#   sh scripts/check-overnight.sh              # everything
#   MESH_OVERNIGHT_SKIP="sim brain" sh scripts/check-overnight.sh
# Prints one line per check in check-all's FAIL/ok style and exits 1 if any failed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKIP=" ${MESH_OVERNIGHT_SKIP:-} "
fail=0
run() { # name, env..., -- script
  name="$1"; shift
  case "$SKIP" in *" $name "*) echo "skip: $name"; return ;; esac
  if env "$@" sh "$ROOT/scripts/check-$name.sh" >"/tmp/check-overnight-$name.log" 2>&1; then
    echo "ok:   $name — $(tail -1 "/tmp/check-overnight-$name.log")"
  else
    echo "FAIL: $name"; tail -8 "/tmp/check-overnight-$name.log" | sed 's/^/      /'; fail=1
  fi
}
run fleet             MESH_FLEET_LIVE=1 MESH_FLEET_HOSTS="mac pi jetson"
run remote-agent-loop MESH_FLEET_LIVE=1 MESH_REMOTE_HOST=jetson
run remote-agent-loop MESH_FLEET_LIVE=1 MESH_REMOTE_HOST=pi
run cross-host-cp     MESH_FLEET_LIVE=1 MESH_REMOTE_HOST=jetson
run kb-federation     MESH_FLEET_LIVE=1 MESH_REMOTE_HOST=jetson
run brand             X=1
run relay-receiver    X=1
run harness-picker    X=1
run pair-auth         X=1
run intent            X=1
run brain             MESH_FLEET_LIVE=1 MESH_FLEET_HOSTS="mac pi jetson" MESH_BRAIN_LIVE=1
run watch-smoke       MESH_SMOKE_REQUIRED=1
run sim-fleet         MESH_SIM_LIVE=1
[ "$fail" -eq 0 ] && echo "check-overnight: OK — every live check green" || echo "check-overnight: FAIL"
exit "$fail"

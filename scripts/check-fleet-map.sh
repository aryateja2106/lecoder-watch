#!/bin/sh
# `mesh fleet` is what an agent reads before deciding which machine to run on, so the
# fields it depends on have to be there and have to be true:
#   - /stats carries `hw`: the board or chip, cores, total RAM and the accelerator — Apple
#     unified memory, CUDA (a Jetson's GPU shares the CPU's RAM), or none. Hardware is read
#     once, from files the OS already keeps; nothing runs `nvcc` (not on PATH on a Jetson).
#   - `mesh fleet --json` returns one row per machine with free RAM, load, sessions, the
#     installed agent CLIs, the local model servers that answer, and the owner's `role`.
#   - the same machine listed as "local" and under a name on 127.0.0.1 appears once.
# Structural half always; the live half (MESH_FLEET_LIVE=1) checks every paired machine's
# real /stats has `hw` and that `mesh fleet --json` reports every reachable one fully.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/install/payload/meshd/server.ts"
MESH="$ROOT/install/payload/bin/mesh"
fail=0
note() { echo "check-fleet-map: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

grep -q 'async function hardware()' "$SERVER" || bad "meshd lost hardware()"
grep -q 'hardware(),' "$SERVER" || bad "getStats no longer reads hardware — /stats would have no hw"
grep -q 'agentsCount: rmuxCount + cmuxCount + herdrCount, hw }' "$SERVER" || bad "/stats does not return hw"
for kind in '"apple"' '"cuda"' '"none"'; do
  grep -q "kind: $kind" "$SERVER" || bad "hardware() no longer reports accelerator kind $kind"
done
grep -q '/usr/local/cuda/version.json' "$SERVER" || bad "CUDA version must come from version.json (nvcc is not on PATH on a Jetson)"
grep -q '/etc/nv_tegra_release' "$SERVER" || bad "a Jetson's shared GPU memory is no longer detected"
grep -q 'hardwareCache' "$SERVER" || bad "hardware is re-read on every /stats poll"

grep -q 'async function cmdFleet' "$MESH" || bad "mesh fleet is gone"
grep -q 'case "fleet": case "where": return cmdFleet' "$MESH" || bad "mesh fleet is not wired into the command switch"
for field in memFreeMB agents models role hardware sessions; do
  grep -q "$field" "$MESH" || bad "mesh fleet --json lost the $field field"
done
grep -q 'named.some((h) => h.ip === local.ip && h.port === local.port)' "$MESH" \
  || bad "the local machine would be listed twice (as local and by name)"
grep -q 'function cmdHostRole' "$MESH" || bad "mesh host role is gone — nothing records what a machine is for"

if [ "${MESH_FLEET_LIVE:-}" = "1" ]; then
  command -v bun >/dev/null 2>&1 || { bad "live half needs bun"; }
  bun "$MESH" fleet --json > "${TMPDIR:-/tmp}/fleet-map.$$.json" 2>/dev/null || bad "mesh fleet --json failed"
  python3 - "${TMPDIR:-/tmp}/fleet-map.$$.json" <<'PY' || fail=1
import json, sys
rows = json.load(open(sys.argv[1]))
live = [r for r in rows if r.get("reachable")]
if not live:
    print("FAIL: no reachable machine in mesh fleet"); sys.exit(1)
bad = 0
for r in live:
    hw = r.get("hardware")
    if not hw or not hw.get("board") or not hw.get("cores") or not hw.get("ramMB"):
        print(f"FAIL: {r['host']} has no hardware identity — its meshd predates hw"); bad = 1; continue
    if r.get("memFreeMB") is None or r.get("agents") is None or r.get("models") is None:
        print(f"FAIL: {r['host']} row is missing live fields"); bad = 1; continue
    print(f"check-fleet-map: ok   {r['host']}: {hw['board']} · {hw['accel']['kind']} · {r['memFreeMB']} MB free · {len(r['agents'])} agent CLIs · {sum(len(m['models']) for m in r['models'])} local model(s)")
hosts = [r["host"] for r in rows]
if len(hosts) != len(set(hosts)):
    print(f"FAIL: a machine is listed twice: {hosts}"); bad = 1
sys.exit(bad)
PY
  rm -f "${TMPDIR:-/tmp}/fleet-map.$$.json"
fi

[ "$fail" = 0 ] && echo "check-fleet-map: OK" || exit 1

#!/bin/sh
# check-fleet.sh — every machine in ~/.mesh/hosts.json runs THIS tree's meshd and is usable.
#
# The fleet is three machines on one tailnet (a Mac, a Jetson, a Raspberry Pi) and until
# 2026-09-21 no check ever contacted a second host: the Pi sat on 0.2.0 for weeks while every
# check here was green. This one asks each host, over the wire, the four things a phone asks:
#   /health   meshdVersion == the VERSION in install/payload/meshd/server.ts
#   /doctor   parses, and no row is `ok:false`
#   /input    ok:true (xdotool + X display on Linux; Accessibility on the Mac)
#   /screen.jpg  image/jpeg, > 5 KB, with an x-mesh-rect header when a region is asked for
#
# Structural half (always runs): the Linux screen path exists in input-linux.ts and the old
# "screen peek is macOS only" 404 is gone from input.ts.
#
# Live half (opt-in, MESH_FLEET_LIVE=1): needs ~/.mesh/hosts.json and the tailnet. Opt-in
# because CI has no fleet and check-all must not depend on someone else's machines being up.
# MESH_FLEET_HOSTS="pi jetson" limits it; MESH_FLEET_SKIP_SCREEN=1 tolerates hosts without X.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINUX="$ROOT/install/payload/meshd/input-linux.ts"
INPUT="$ROOT/install/payload/meshd/input.ts"

fail=0
if ! grep -q 'linuxCaptureScreen' "$LINUX"; then
  echo "check-fleet: FAIL — input-linux.ts has no linuxCaptureScreen; Linux hosts have no screen"
  fail=1
fi
if grep -q 'screen peek is macOS only' "$INPUT"; then
  echo "check-fleet: FAIL — input.ts still 404s /screen.jpg off macOS"
  fail=1
fi
[ "$fail" -eq 0 ] || exit 1

if [ "${MESH_FLEET_LIVE:-}" != "1" ]; then
  echo "check-fleet: OK (structural; set MESH_FLEET_LIVE=1 to probe every host in ~/.mesh/hosts.json)"
  exit 0
fi

HOSTS_FILE="${MESH_HOSTS_FILE:-$HOME/.mesh/hosts.json}"
[ -r "$HOSTS_FILE" ] || { echo "check-fleet: SKIP live (no $HOSTS_FILE)"; exit 0; }
WANT="$(sed -n 's/^const VERSION = "\([^"]*\)".*/\1/p' "$ROOT/install/payload/meshd/server.ts" | head -1)"
[ -n "$WANT" ] || { echo "check-fleet: FAIL — cannot read VERSION from server.ts"; exit 1; }

python3 - "$HOSTS_FILE" "$WANT" "${MESH_FLEET_HOSTS:-}" "${MESH_FLEET_SKIP_SCREEN:-0}" <<'PY'
import json, sys, urllib.request, urllib.error
hosts_file, want, only, skip_screen = sys.argv[1], sys.argv[2], sys.argv[3].split(), sys.argv[4] == "1"
cfg = json.load(open(hosts_file))
hosts = cfg.get("hosts", {})
names = only or [n for n in hosts if n not in ("dataflow",)]  # dataflow is a retired box, offline since 2026-09-03
bad = 0
def get(h, path, raw=False, timeout=8):
    req = urllib.request.Request(f"http://{h['ip']}:{h['port']}{path}", headers={"Authorization": f"Bearer {h['token']}"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
        return (data, dict(r.headers)) if raw else json.loads(data)
for name in names:
    h = hosts[name]
    problems = []
    try:
        health = get(h, "/health")
        v = health.get("meshdVersion")
        if v != want: problems.append(f"version {v} != {want}")
        platform = health.get("platform", "?")
    except Exception as e:
        print(f"check-fleet: FAIL {name} unreachable: {e}"); bad += 1; continue
    try:
        doc = get(h, "/doctor")
        checks = doc.get("checks", doc)
        red = [k for k, r in checks.items() if isinstance(r, dict) and r.get("ok") is False]
        if red: problems.append("doctor red: " + ",".join(red))
    except Exception as e:
        problems.append(f"/doctor: {e}")
    try:
        st = get(h, "/input")
        if not st.get("ok"): problems.append(f"/input not ok: {st.get('hint') or st.get('error')}")
    except Exception as e:
        problems.append(f"/input: {e}")
    if not skip_screen:
        try:
            data, hdr = get(h, "/screen.jpg?x=0.1&y=0.1&w=0.5&h=0.5", raw=True, timeout=20)
            ct = {k.lower(): v for k, v in hdr.items()}
            if not ct.get("content-type", "").startswith("image/jpeg"): problems.append(f"/screen.jpg content-type {ct.get('content-type')}")
            elif len(data) < 5000: problems.append(f"/screen.jpg only {len(data)} bytes")
            elif "x-mesh-rect" not in ct: problems.append("/screen.jpg region served without x-mesh-rect")
        except urllib.error.HTTPError as e:
            problems.append(f"/screen.jpg HTTP {e.code}")
        except Exception as e:
            problems.append(f"/screen.jpg: {e}")
    if problems:
        bad += 1
        print(f"check-fleet: FAIL {name} ({platform}): " + "; ".join(problems))
    else:
        print(f"check-fleet: ok   {name} ({platform}) meshd {want}, doctor green, input ok, screen ok")
sys.exit(1 if bad else 0)
PY
status=$?
[ "$status" -eq 0 ] && echo "check-fleet: OK (live)"
exit "$status"

#!/bin/sh
# check-linux-desktop.sh — a Linux machine is a full Remote peer: running apps listed and
# activatable (xprop/xdotool), clipboard writes return at once (xclip's forked child no longer
# holds the daemon's pipe), `screenshot` puts a PNG on the clipboard, and sleep/screensaver
# exist so the phone's and the watch's power lists can be one list. Also: the Mac gets the
# same `screenshot` action, the web console's same-origin POSTs are no longer 401'd, and
# /screen.jpg honours `width` on Linux.
#
# Structural half always; live half with MESH_FLEET_LIVE=1 against MESH_REMOTE_HOST (default pi)
# from ~/.mesh/hosts.json — token read into a header file, never printed.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
L="$ROOT/install/payload/meshd/input-linux.ts"; M="$ROOT/install/payload/meshd/input.ts"; S="$ROOT/install/payload/meshd/server.ts"
grep -q 'export async function linuxListApps' "$L" || { echo "FAIL: linuxListApps missing"; exit 1; }
grep -q 'export async function linuxActivateApp' "$L" || { echo "FAIL: linuxActivateApp missing"; exit 1; }
grep -q 'return linuxListApps()' "$M" || { echo "FAIL: /apps not routed to Linux"; exit 1; }
for a in sleep screensaver screenshot; do grep -q "^  $a: \[" "$L" || { echo "FAIL: Linux system action $a missing"; exit 1; }; done
grep -q 'screenshot: \["/usr/sbin/screencapture", "-c"' "$M" || { echo "FAIL: Mac screenshot-to-clipboard missing"; exit 1; }
grep -q 'stdout: "ignore", stderr: "ignore" });' "$L" || { echo "FAIL: xclip write still pipes stdout"; exit 1; }
grep -q '"-resize", `${width}x`' "$L" || { echo "FAIL: Linux /screen.jpg ignores width"; exit 1; }
grep -q 'origin.toLowerCase() !== `${new URL(req.url).protocol}//${host}`' "$S" || { echo "FAIL: same-origin browser POSTs still cross-site"; exit 1; }
# Sessions must outlive the daemon: the unit's cgroup kill took every tmux session with a restart.
grep -q '^KillMode=process' "$ROOT/install/install.sh" || { echo "FAIL: systemd unit lacks KillMode=process (sessions die on upgrade)"; exit 1; }
[ "${MESH_FLEET_LIVE:-}" = "1" ] || { echo "check-linux-desktop: ok (structural; MESH_FLEET_LIVE=1 for the live half)"; exit 0; }

HOST="${MESH_REMOTE_HOST:-pi}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$HOST" "$TMP/hdr" "$TMP/addr" <<'PY'
import json, sys, os
host, hdr, addr = sys.argv[1:]
d = json.load(open(os.path.expanduser("~/.mesh/hosts.json")))
rows = d["hosts"] if isinstance(d, dict) else d
h = rows[host] if isinstance(rows, dict) else next(x for x in rows if x.get("name") == host)
open(hdr, "w").write(f"authorization: Bearer {h['token']}\n")
open(addr, "w").write(f"http://{h['ip']}:{h.get('port', 8899)}")
PY
chmod 600 "$TMP/hdr"; BASE="$(cat "$TMP/addr")"
api() { curl -s -m 20 -H @"$TMP/hdr" "$@"; }
plat=$(api "$BASE/health" | python3 -c 'import sys,json;print(json.load(sys.stdin)["platform"])')
[ "$plat" = "linux" ] || { echo "FAIL: $HOST is $plat, not linux"; exit 1; }

start=$(python3 -c 'import time;print(time.time())')
api -X POST -H 'content-type: application/json' -d '{"text":"check-linux-desktop"}' "$BASE/clipboard" | grep -q '"ok":true' || { echo "FAIL: clipboard write"; exit 1; }
ms=$(python3 -c "import time;print(int((time.time()-$start)*1000))")
[ "$ms" -lt 5000 ] || { echo "FAIL: clipboard write took ${ms} ms (xclip pipe hang)"; exit 1; }
api "$BASE/clipboard" | grep -q 'check-linux-desktop' || { echo "FAIL: clipboard read-back"; exit 1; }
api -X POST -H 'content-type: application/json' -d '{"action":"screenshot"}' "$BASE/system" | grep -q '"ok":true' || { echo "FAIL: screenshot action"; exit 1; }
api "$BASE/apps" | python3 -c 'import sys,json;d=json.load(sys.stdin);assert d.get("ok") and isinstance(d.get("running"),list), d' || { echo "FAIL: /apps on linux"; exit 1; }
api -o "$TMP/s.jpg" "$BASE/screen.jpg?width=320"
python3 - "$TMP/s.jpg" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read(); i = d.find(b"\xff\xc0"); w = struct.unpack(">H", d[i+7:i+9])[0]
assert w == 320, f"width {w}"
PY
echo "check-linux-desktop: ok — $HOST: clipboard write ${ms} ms, screenshot on clipboard, apps listed, screen.jpg width honoured"

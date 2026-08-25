#!/bin/sh
# The 0.5.0 daemon contract, end to end against a throwaway meshd:
#   - push gate: an info event is stored for pollers but never queued for APNs;
#     a warning is queued (observed via the alertsQueued/alertsGated counters on /push)
#   - /agents rows carry status / lastEventLevel / lastEventISO
#   - GET output accepts join=1 (soft-wrapped lines unwrapped) and plain=1 (box
#     drawing stripped, space runs collapsed)
#   - POST /agents/new honors cols/rows (asserted via tmux display-message)
#   - POST send with paste:true lands multiline text in the pane
#   - /screen.jpg region params (x/y/w/h/q) are accepted, announced via x-mesh-rect,
#     and a sliver-thin rect is rejected 400
#   - POST /system answers the truthful {ok, exitCode, stderr} shape and never a
#     fake ok (exercised with an unknown action, which reaches the same response
#     builder; no action with a real side effect — lock, sleep, shutdown, restart —
#     is ever executed by this suite, only inspected)
#   - POST /open rejects every non-http(s) URL with 400
#   - POST /la/token stores start/update tokens in memory and on disk
#   - mesh-agent-run posts its Failed event at level error
#
# Everything is throwaway: meshd on :8896 with HOME and the events file in a temp
# dir, tmux on a private socket with no user config. The real daemon on :8899, the
# real tmux server and ~/.mesh are never touched. No token value is ever printed.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-daemon-050: SKIP (no bun)"; exit 0; }
command -v tmux >/dev/null 2>&1 || { echo "check-daemon-050: SKIP (no tmux)"; exit 0; }
[ "$(uname)" = "Darwin" ] || { echo "check-daemon-050: SKIP (macOS-only assertions)"; exit 0; }

PORT=8896
if curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/health" 2>/dev/null; then
  echo "check-daemon-050: SKIP (something already listens on :$PORT — not killing it)"
  exit 0
fi

TMP="$(mktemp -d)"
SOCK="mesh-050-$$"
DAEMON_PID=""
cleanup() {
  if [ -n "$DAEMON_PID" ]; then
    kill "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true
  fi
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TMP/.mesh"
head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TMP/.mesh/token"
chmod 600 "$TMP/.mesh/token"
printf 'authorization: Bearer %s\n' "$(cat "$TMP/.mesh/token")" > "$TMP/hdr"
chmod 600 "$TMP/hdr"

# The tmux server starts from OUR first command so it runs with no user config.
tmux -L "$SOCK" -f /dev/null new-session -d -s mesh-boot "exec cat"

MESHD_TOKEN="$(cat "$TMP/.mesh/token")" \
HOME="$TMP" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" \
MESHD_EVENTS_PATH="$TMP/events.jsonl" MESH_MUX="tmux -L $SOCK" \
MESHD_TELEMETRY=off \
  bun "$ROOT/install/payload/meshd/server.ts" >"$TMP/meshd.log" 2>&1 &
DAEMON_PID=$!

i=0
until curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -lt 50 ] || { echo "FAIL: throwaway meshd never came up"; cat "$TMP/meshd.log"; exit 1; }
  sleep 0.2
done

api() { curl -sf -m 20 -H @"$TMP/hdr" "$@"; }

# ---- /health: version, new capabilities, ipv4+netmask ----
api "http://127.0.0.1:$PORT/health" > "$TMP/health.json"
/usr/bin/python3 - "$TMP/health.json" <<'PY'
import json, sys
h = json.load(open(sys.argv[1]))
fail = []
if h.get("meshdVersion") != "0.5.0":
    fail.append(f"meshdVersion is {h.get('meshdVersion')!r}, want 0.5.0")
want = {"screenRegion", "openUrl", "power", "laPush", "sessionStatus", "paste", "captureJoin"}
missing = want - set(h.get("capabilities", []))
if missing:
    fail.append(f"capabilities missing {sorted(missing)}")
for key in ("ipv4", "netmask"):
    if key not in h:
        fail.append(f"/health lacks the {key} key")
for f in fail: print("FAIL:", f)
sys.exit(1 if fail else 0)
PY
echo "check-daemon-050: health OK (0.5.0, capabilities, ipv4/netmask)"

# ---- push gate + /agents status fields ----
# A warning must be queued for push AND flip the session row to "waiting";
# a following info event must be stored (visible to pollers) but gated, and the
# row becomes "working" (a fresh calm event = someone just finished a turn).
api -X POST -d '{"title":"Claude needs attention","body":"Allow edit?","session":"mesh-boot","level":"warning","replyable":true}' \
  "http://127.0.0.1:$PORT/events" > /dev/null
api "http://127.0.0.1:$PORT/agents" > "$TMP/agents-waiting.json"
api -X POST -d '{"title":"Claude stopped","session":"mesh-boot","level":"info"}' \
  "http://127.0.0.1:$PORT/events" > /dev/null
api "http://127.0.0.1:$PORT/agents" > "$TMP/agents-working.json"
api "http://127.0.0.1:$PORT/push" > "$TMP/push-status.json"
api "http://127.0.0.1:$PORT/events" > "$TMP/events-1.json"
/usr/bin/python3 - "$TMP/agents-waiting.json" "$TMP/agents-working.json" "$TMP/push-status.json" "$TMP/events-1.json" <<'PY'
import json, sys
waiting, working, push, events = (json.load(open(p)) for p in sys.argv[1:5])
fail = []
def row(agents, name):
    return next((a for a in agents if a.get("name") == name), None)
w = row(waiting, "mesh-boot")
if not w: fail.append("mesh-boot row missing from /agents")
elif w.get("status") != "waiting":
    fail.append(f"after a warning the row status is {w.get('status')!r}, want waiting")
elif w.get("lastEventLevel") != "warning" or not w.get("lastEventISO"):
    fail.append(f"row lacks lastEventLevel/lastEventISO: {w}")
g = row(working, "mesh-boot")
if g and g.get("status") != "working":
    fail.append(f"after a fresh info the row status is {g.get('status')!r}, want working")
if push.get("alertsQueued") != 1:
    fail.append(f"alertsQueued is {push.get('alertsQueued')!r}, want 1 (only the warning)")
if push.get("alertsGated") != 1:
    fail.append(f"alertsGated is {push.get('alertsGated')!r}, want 1 (the info event)")
stored = [e for e in events if e.get("title") == "Claude stopped"]
if len(stored) != 1:
    fail.append("the gated info event must still be stored for pollers")
for f in fail: print("FAIL:", f)
sys.exit(1 if fail else 0)
PY
echo "check-daemon-050: push gate + /agents status OK (info stored but gated; warning queued)"

# ---- join=1 unwraps soft-wrapped lines; plain=1 strips TUI chrome ----
LONG="$(printf 'J%.0s' $(seq 1 118))END"   # 121 chars: wraps in an 80-col pane
api -X POST -d "{\"text\":\"$LONG\"}" "http://127.0.0.1:$PORT/agents/mesh-boot/send" > /dev/null
sleep 1
api "http://127.0.0.1:$PORT/agents/mesh-boot/output?lines=40" > "$TMP/out-plainless.json"
api "http://127.0.0.1:$PORT/agents/mesh-boot/output?lines=40&join=1" > "$TMP/out-join.json"
api -X POST -d '{"text":"box─│drawing  and   runs"}' "http://127.0.0.1:$PORT/agents/mesh-boot/send" > /dev/null
sleep 1
api "http://127.0.0.1:$PORT/agents/mesh-boot/output?lines=40&plain=1" > "$TMP/out-plain.json"
LONG="$LONG" /usr/bin/python3 - "$TMP/out-plainless.json" "$TMP/out-join.json" "$TMP/out-plain.json" <<'PY'
import json, os, sys
bare, joined, plain = (json.load(open(p)) for p in sys.argv[1:4])
long_line = os.environ["LONG"]
fail = []
if any(long_line in l for l in bare["lines"]):
    fail.append("the 121-char line fit unwrapped in a bare capture — widen it, the join assert proves nothing")
if not any(long_line in l for l in joined["lines"]):
    fail.append("join=1 did not unwrap the soft-wrapped line")
flat = "\n".join(plain["lines"])
if "─" in flat or "│" in flat:
    fail.append("plain=1 left box-drawing characters in place")
if not any("boxdrawing and runs" in l for l in plain["lines"]):
    fail.append(f"plain=1 did not collapse space runs as expected: {plain['lines'][-8:]}")
for f in fail: print("FAIL:", f)
sys.exit(1 if fail else 0)
PY
echo "check-daemon-050: join=1 unwraps, plain=1 strips OK"

# ---- new-session cols/rows honored ----
api -X POST -d '{"name":"mesh-sized","cols":100,"rows":30}' "http://127.0.0.1:$PORT/agents/new" > /dev/null
SIZE="$(tmux -L "$SOCK" display-message -p -t mesh-sized '#{window_width}x#{window_height}')"
[ "$SIZE" = "100x30" ] || { echo "FAIL: sized session is $SIZE, want 100x30"; exit 1; }
echo "check-daemon-050: new-session cols/rows OK ($SIZE)"

# ---- paste:true lands multiline text ----
api -X POST -d '{"name":"mesh-paste","cmd":"exec cat"}' "http://127.0.0.1:$PORT/agents/new" > /dev/null
api -X POST -d '{"text":"alpha-AAA\nbeta-BBB","paste":true}' "http://127.0.0.1:$PORT/agents/mesh-paste/send" > /dev/null
sleep 1
api "http://127.0.0.1:$PORT/agents/mesh-paste/output?lines=30" > "$TMP/pasted.json"
/usr/bin/python3 - "$TMP/pasted.json" <<'PY'
import json, sys
out = json.load(open(sys.argv[1]))
flat = "\n".join(out["lines"])
missing = [t for t in ("alpha-AAA", "beta-BBB") if t not in flat]
if missing:
    print(f"FAIL: paste:true dropped {missing}; pane shows: {out['lines'][-10:]}")
    sys.exit(1)
PY
echo "check-daemon-050: paste:true multiline OK"

# ---- region capture: params accepted + announced; slivers rejected ----
# The first region request may build mesh-input with swiftc, hence the long timeout;
# if display geometry is unavailable here the daemon falls back to a pixel-space
# crop — either way the served crop must be announced in x-mesh-rect.
CODE="$(curl -s -m 150 -o "$TMP/region.jpg" -D "$TMP/region.hdr" -w '%{http_code}' -H @"$TMP/hdr" \
  "http://127.0.0.1:$PORT/screen.jpg?x=0.25&y=0.25&w=0.5&h=0.5&q=60")"
[ "$CODE" = "200" ] || { echo "FAIL: region capture returned HTTP $CODE"; cat "$TMP/region.hdr" 2>/dev/null || true; exit 1; }
grep -qi '^content-type: image/jpeg' "$TMP/region.hdr" || { echo "FAIL: region capture is not a JPEG"; exit 1; }
grep -qi '^x-mesh-rect: 0.25,0.25,0.5,0.5' "$TMP/region.hdr" || { echo "FAIL: served crop not announced in x-mesh-rect"; cat "$TMP/region.hdr"; exit 1; }
[ -s "$TMP/region.jpg" ] || { echo "FAIL: region capture returned an empty body"; exit 1; }
TINY="$(curl -s -m 20 -o "$TMP/tiny.json" -w '%{http_code}' -H @"$TMP/hdr" \
  "http://127.0.0.1:$PORT/screen.jpg?x=0.2&y=0.2&w=0.005&h=0.4")"
[ "$TINY" = "400" ] || { echo "FAIL: sliver rect returned HTTP $TINY, want 400"; cat "$TMP/tiny.json"; exit 1; }
echo "check-daemon-050: region capture OK (200 + x-mesh-rect, sliver=400)"

# ---- /system: truthful shape, with no side effect on the machine running this ----
# An unknown action takes the same code path to the same response builder, so the
# shape under test is identical — without locking, sleeping, or restarting the Mac
# of whoever runs the suite. "lock" is deliberately NOT exercised here.
curl -s -m 20 -o "$TMP/system.json" -H @"$TMP/hdr" \
  -X POST -d '{"action":"frobnicate"}' "http://127.0.0.1:$PORT/system"
/usr/bin/python3 - "$TMP/system.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
fail = []
if r.get("ok") is not False: fail.append("an unknown action must answer ok:false, never a fake ok")
if not r.get("error"): fail.append("a refusal must say why")
for key, kind in (("exitCode", int), ("stderr", str)):
    if key in r and not isinstance(r[key], kind):
        fail.append(f"{key} is {type(r[key]).__name__}, not {kind.__name__}")
if isinstance(r.get("ok"), bool) and isinstance(r.get("exitCode"), int) and r["ok"] != (r["exitCode"] == 0):
    fail.append(f"ok={r['ok']} contradicts exitCode={r['exitCode']} — the route is lying again")
for f in fail: print("FAIL:", f)
sys.exit(1 if fail else 0)
PY
# The unsupported-on-this-OS branch, exercised for real with zero side effects:
# on macOS, the Linux "shutdown" mapping (systemctl) cannot exist — the truthful
# answer is ok:false with exit 127, never a fake ok.
(cd "$ROOT/install/payload/meshd" && bun -e '
import { linuxSystemAction } from "./input-linux.ts";
const r = await linuxSystemAction("shutdown");
if (r.ok !== false) throw new Error("a missing systemctl must not report ok:true");
if (r.exitCode !== 127) throw new Error(`want exitCode 127 for a missing binary, got ${r.exitCode}`);
if (typeof r.stderr !== "string" || !r.stderr) throw new Error("the failure must carry stderr");
const unknown = await linuxSystemAction("frobnicate");
if (unknown.ok !== false || !unknown.error) throw new Error("unknown actions must refuse");
')
# shutdown/restart wiring exists on both platforms — by inspection, never executed.
grep -q 'tell app "System Events" to shut down' "$ROOT/install/payload/meshd/input.ts" \
  || { echo "FAIL: macOS shutdown action missing from input.ts"; exit 1; }
grep -q 'tell app "System Events" to restart' "$ROOT/install/payload/meshd/input.ts" \
  || { echo "FAIL: macOS restart action missing from input.ts"; exit 1; }
grep -q '"systemctl", "poweroff"' "$ROOT/install/payload/meshd/input-linux.ts" \
  || { echo "FAIL: Linux shutdown action missing from input-linux.ts"; exit 1; }
grep -q '"systemctl", "reboot"' "$ROOT/install/payload/meshd/input-linux.ts" \
  || { echo "FAIL: Linux restart action missing from input-linux.ts"; exit 1; }
echo "check-daemon-050: /system truthful shape OK (no side-effecting action executed)"

# ---- /open rejects everything that is not http/https ----
for URL in "file:///etc/passwd" "javascript:alert(1)" "ssh://root@host" "not a url"; do
  CODE="$(curl -s -m 20 -o "$TMP/open.json" -w '%{http_code}' -H @"$TMP/hdr" \
    -X POST -d "{\"url\":$(printf '%s' "$URL" | /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" \
    "http://127.0.0.1:$PORT/open")"
  [ "$CODE" = "400" ] || { echo "FAIL: /open accepted $URL (HTTP $CODE)"; cat "$TMP/open.json"; exit 1; }
done
echo "check-daemon-050: /open rejects non-http OK"

# ---- /la/token stores (memory + file) ----
START_TOKEN="$(printf 'ab%.0s' $(seq 1 40))"    # 80 hex chars
UPDATE_TOKEN="$(printf 'cd%.0s' $(seq 1 40))"
api -X POST -d "{\"kind\":\"start\",\"token\":\"$START_TOKEN\"}" "http://127.0.0.1:$PORT/la/token" > "$TMP/la1.json"
api -X POST -d "{\"kind\":\"update\",\"token\":\"$UPDATE_TOKEN\",\"session\":\"mesh-boot\"}" "http://127.0.0.1:$PORT/la/token" > "$TMP/la2.json"
BAD="$(curl -s -m 20 -o /dev/null -w '%{http_code}' -H @"$TMP/hdr" \
  -X POST -d '{"kind":"start","token":"zz-not-hex"}' "http://127.0.0.1:$PORT/la/token")"
[ "$BAD" = "400" ] || { echo "FAIL: /la/token accepted a non-hex token (HTTP $BAD)"; exit 1; }
api "http://127.0.0.1:$PORT/push" > "$TMP/push-la.json"
/usr/bin/python3 - "$TMP/la1.json" "$TMP/la2.json" "$TMP/push-la.json" "$TMP/.mesh/la-tokens.json" <<'PY'
import json, sys
la1, la2, push = (json.load(open(p)) for p in sys.argv[1:4])
fail = []
if not (la1.get("ok") and la1.get("start") == 1 and la1.get("update") == 0):
    fail.append(f"start register answered {la1}")
if not (la2.get("ok") and la2.get("start") == 1 and la2.get("update") == 1):
    fail.append(f"update register answered {la2}")
if push.get("laStartTokens") != 1 or push.get("laUpdateTokens") != 1:
    fail.append(f"/push does not report the stored LA tokens: {push}")
try:
    stored = json.load(open(sys.argv[4]))
    kinds = sorted(t.get("kind") for t in stored)
    if kinds != ["start", "update"]:
        fail.append(f"la-tokens.json holds {kinds}, want ['start','update']")
    if not all(t.get("env") in ("dev", "prod") for t in stored):
        fail.append("stored LA tokens lack an APNs environment")
except FileNotFoundError:
    fail.append("la-tokens.json was never written beside the daemon state")
for f in fail: print("FAIL:", f)
sys.exit(1 if fail else 0)
PY
echo "check-daemon-050: /la/token stores OK (memory counts + la-tokens.json)"

# ---- mesh-agent-run reports failure at level error ----
( cd "$TMP" && \
  MESH_HOME="$TMP/.mesh" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" MESHD_SESSION=mesh-fail \
  "$ROOT/install/payload/bin/mesh-agent-run" checksrc sh -c "exit 3" ) && \
  { echo "FAIL: mesh-agent-run swallowed the exit status"; exit 1; } || true
api "http://127.0.0.1:$PORT/events" > "$TMP/events-2.json"
/usr/bin/python3 - "$TMP/events-2.json" <<'PY'
import json, sys
events = json.load(open(sys.argv[1]))
failed = [e for e in events if e.get("title") == "Failed" and e.get("session") == "mesh-fail"]
if len(failed) != 1:
    print(f"FAIL: want exactly one Failed event for mesh-fail, got {len(failed)}")
    sys.exit(1)
if failed[0].get("level") != "error":
    print(f"FAIL: mesh-agent-run Failed event is level {failed[0].get('level')!r}, want error")
    sys.exit(1)
PY
echo "check-daemon-050: mesh-agent-run Failed lands at level error OK"

# ---- the example hook file matches what `mesh hooks install` writes ----
grep -q '"SubagentStop"' "$ROOT/install/hooks/claude-settings.meshwatch.example.json" && {
  echo "FAIL: the example hook file still registers SubagentStop (the installer does not)"
  exit 1
} || true

echo "check-daemon-050: OK"

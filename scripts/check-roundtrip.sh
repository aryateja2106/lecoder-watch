#!/bin/sh
# The notification round-trip: an event an agent hook posts must carry a session
# name the reply route can actually address — or say that it cannot be addressed.
#
# The defect this pins down, observed live 2026-08-24: outside tmux, mesh-hook
# reported the cwd path as the session, the watch showed "Claude needs attention",
# and every answer POSTed to /agents/<a-filesystem-path>/send — which the mux cannot
# resolve, and which the send route then answered ok:true about anyway.
#
# Everything here is throwaway: meshd on :8898 with HOME and the events file in a
# temp dir, tmux on a private socket with no user config. The real daemon on :8899,
# the real tmux server and ~/.mesh are never touched. No token value is ever printed.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-roundtrip: SKIP (no bun)"; exit 0; }
command -v tmux >/dev/null 2>&1 || { echo "check-roundtrip: SKIP (no tmux)"; exit 0; }

PORT=8898
if curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/health" 2>/dev/null; then
  echo "check-roundtrip: SKIP (something already listens on :$PORT — not killing it)"
  exit 0
fi

TMP="$(mktemp -d)"
SOCK="mesh-check-$$"
SESSION="mesh-check-roundtrip"
DAEMON_PID=""
cleanup() {
  if [ -n "$DAEMON_PID" ]; then
    kill "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true   # absorb the job-control notice
  fi
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

# Token lives in a file, exactly where mesh-hook looks for it under MESH_HOME, and
# reaches curl via a header file — never on a command line, never on stdout.
mkdir -p "$TMP/.mesh"
head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TMP/.mesh/token"
chmod 600 "$TMP/.mesh/token"
printf 'authorization: Bearer %s\n' "$(cat "$TMP/.mesh/token")" > "$TMP/hdr"
chmod 600 "$TMP/hdr"

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

# (a) From inside a tmux pane the hook must report the mux session — the name
# `mesh ls` shows and the reply route resolves — plus the exact pane, additively.
cat > "$TMP/inside.sh" <<EOF
#!/bin/sh
unset MESHD_SESSION MESHD_LEVEL MESHD_TOKEN MESH_HOOK_SOURCE
printf '%s' '{"hook_event_name":"Notification","message":"needs input","cwd":"$TMP"}' |
  MESH_HOME="$TMP/.mesh" MESHD_HOST=127.0.0.1 MESHD_PORT=$PORT \
  python3 "$ROOT/install/payload/bin/mesh-hook" --source claude
touch "$TMP/inside.done"
EOF
tmux -L "$SOCK" -f /dev/null new-session -d -s "$SESSION" "sh $TMP/inside.sh; exec cat"

i=0
until [ -e "$TMP/inside.done" ]; do
  i=$((i + 1))
  [ "$i" -lt 50 ] || { echo "FAIL: hook inside tmux never posted"; tmux -L "$SOCK" capture-pane -p -t "$SESSION" || true; exit 1; }
  sleep 0.2
done

# (b) From a bare terminal — no mux, no MESHD_SESSION — the event must admit it is
# not answerable, and carry the folder name instead of a filesystem path.
printf '%s' '{"hook_event_name":"Notification","message":"needs input","cwd":"/Users/nobody/Projects/worktrees/agent-x"}' |
  env -u TMUX -u TMUX_PANE -u RMUX -u RMUX_PANE -u MESHD_SESSION -u MESHD_LEVEL -u MESHD_TOKEN -u MESH_HOOK_SOURCE \
  MESH_HOME="$TMP/.mesh" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" \
  python3 "$ROOT/install/payload/bin/mesh-hook" --source claude

# What the daemon serves back, not merely what the hook sent.
curl -sf -H @"$TMP/hdr" "http://127.0.0.1:$PORT/events" > "$TMP/events.json"

SESSION="$SESSION" /usr/bin/python3 - "$TMP/events.json" <<'PY'
import json, os, sys
events = json.load(open(sys.argv[1]))
session = os.environ["SESSION"]
fail = []
inside = [e for e in events if e.get("replyable") is True]
outside = [e for e in events if e.get("replyable") is False]
if len(inside) != 1: fail.append(f"want exactly 1 replyable event, got {len(inside)}")
if len(outside) != 1: fail.append(f"want exactly 1 unreplyable event, got {len(outside)}")
if inside:
    e = inside[0]
    if e.get("session") != session: fail.append(f"inside-tmux session is {e.get('session')!r}, want {session!r}")
    if not str(e.get("pane", "")).startswith(session + ":"): fail.append(f"pane {e.get('pane')!r} does not name a pane of {session!r}")
if outside:
    e = outside[0]
    if e.get("session") != "agent-x": fail.append(f"unreplyable session is {e.get('session')!r}, want the folder name 'agent-x'")
    if "/" in str(e.get("session", "")): fail.append("unreplyable session leaked a filesystem path")
for f in fail: print("FAIL:", f)
sys.exit(1 if fail else 0)
PY

# The session the event names must be answerable, and the answer must land in it.
CODE="$(curl -s -o "$TMP/send.json" -w '%{http_code}' -H @"$TMP/hdr" \
  -X POST -d '{"text":"hello-roundtrip"}' "http://127.0.0.1:$PORT/agents/$SESSION/send")"
[ "$CODE" = "200" ] || { echo "FAIL: send to the reported session returned HTTP $CODE"; cat "$TMP/send.json"; exit 1; }
grep -q '"ok":true' "$TMP/send.json" || { echo "FAIL: send to the reported session not ok"; cat "$TMP/send.json"; exit 1; }
sleep 1
tmux -L "$SOCK" capture-pane -p -t "$SESSION" | grep -q "hello-roundtrip" \
  || { echo "FAIL: the reply never arrived in the pane"; tmux -L "$SOCK" capture-pane -p -t "$SESSION"; exit 1; }

# (c) A name the mux cannot resolve is a clean 404 that says so — not ok:true about
# keys typed into the void.
CODE="$(curl -s -o "$TMP/miss.json" -w '%{http_code}' -H @"$TMP/hdr" \
  -X POST -d '{"text":"x"}' "http://127.0.0.1:$PORT/agents/no-such-session/send")"
[ "$CODE" = "404" ] || { echo "FAIL: unknown session send returned HTTP $CODE, want 404"; cat "$TMP/miss.json"; exit 1; }
grep -q '"ok":false' "$TMP/miss.json" && grep -q '"error":"session not addressable"' "$TMP/miss.json" \
  || { echo "FAIL: unknown session send body is not the clean refusal"; cat "$TMP/miss.json"; exit 1; }

# And the push payload honors the event's word: replyable:false means no buttons.
(cd "$ROOT/install/payload/meshd" && HOME="$TMP" bun -e '
import { buildPayload } from "./push.ts";
const dead = buildPayload("Claude needs attention", "?", { level: "warning", session: "agent-x", replyable: false });
if ("category" in dead.aps) throw new Error("replyable:false must not offer reply buttons");
if (dead.replyable !== false) throw new Error("payload must carry replyable:false to the clients");
const live = buildPayload("Claude needs attention", "?", { level: "warning", session: "api", replyable: true });
if (live.aps.category !== "AGENT_ATTENTION") throw new Error("replyable:true must keep the buttons");
const unsaid = buildPayload("Claude needs attention", "?", { level: "warning", session: "api" });
if (unsaid.aps.category !== "AGENT_ATTENTION") throw new Error("an event that never said must behave as before");
if ("replyable" in unsaid) throw new Error("an event that never said must not grow the field");
')

echo "check-roundtrip: OK"

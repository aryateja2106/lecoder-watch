#!/bin/sh
# check-approve-path.sh — the phone's Approve reaches the agent: /agents rows carry the agent's
# own sessionId (the id-first match in Shared/Models.swift matchingAgent needs it), a key aimed at
# a pane the mux cannot resolve is retried on the session instead of answering ok:true about
# nothing, shift-tab / shift-enter are sendable, and claude-mem's observer Stop events are dropped.
#
# Observed 2026-09-22: Claude Code on the Pi stopped at its permission prompt, the Monitor tab
# listed "Claude needs attention" with no Approve at all (no row owned the event: the daemon never
# emitted sessionId on /agents), and a pane-targeted Enter could vanish into discarded stderr.
#
# Throwaway meshd on :8896 with a private tmux socket, like check-roundtrip.sh; nothing live touched.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$ROOT/install/payload/meshd/server.ts"
grep -q '"shift-tab": "BTab"' "$SRV" || { echo "FAIL: shift-tab missing from KEY_SEND_KEYS"; exit 1; }
grep -q '"shift-enter": "M-Enter"' "$SRV" || { echo "FAIL: shift-enter missing from KEY_SEND_KEYS"; exit 1; }
grep -q 'sessionId: last.sessionId' "$SRV" || { echo "FAIL: /agents rows do not stamp sessionId"; exit 1; }
grep -q 'includes("/.claude-mem/")' "$SRV" || { echo "FAIL: observer events not filtered"; exit 1; }
command -v bun >/dev/null 2>&1 || { echo "check-approve-path: ok (structural; no bun)"; exit 0; }
command -v tmux >/dev/null 2>&1 || { echo "check-approve-path: ok (structural; no tmux)"; exit 0; }

PORT=8896
if curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/health" 2>/dev/null; then
  echo "check-approve-path: SKIP (something already listens on :$PORT — not killing it)"; exit 0
fi
TMP="$(mktemp -d)"; SOCK="mesh-approve-$$"; S="mesh-check-approve"; DAEMON_PID=""
cleanup() {
  [ -n "$DAEMON_PID" ] && { kill "$DAEMON_PID" 2>/dev/null || true; wait "$DAEMON_PID" 2>/dev/null || true; }
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/.mesh"
head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TMP/.mesh/token"
printf 'authorization: Bearer %s\n' "$(cat "$TMP/.mesh/token")" > "$TMP/hdr"
MESHD_TOKEN="$(cat "$TMP/.mesh/token")" HOME="$TMP" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" \
MESHD_EVENTS_PATH="$TMP/events.jsonl" MESH_MUX="tmux -L $SOCK" MESHD_TELEMETRY=off \
  bun "$SRV" >"$TMP/meshd.log" 2>&1 &
DAEMON_PID=$!
i=0; until curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null; do
  i=$((i+1)); [ "$i" -lt 50 ] || { echo "FAIL: throwaway meshd never came up"; cat "$TMP/meshd.log"; exit 1; }; sleep 0.2
done
tmux -L "$SOCK" -f /dev/null new-session -d -s "$S" -x 80 -y 24 "sh -c 'while read x; do echo got-line-\$x; done'"
sleep 0.5
api() { curl -s -H @"$TMP/hdr" "$@"; }

# (a) an event with the agent's id makes the /agents row carry that id
api -X POST "http://127.0.0.1:$PORT/events" -H 'content-type: application/json' \
  -d "{\"source\":\"claude\",\"title\":\"Claude needs attention\",\"level\":\"warning\",\"session\":\"$S\",\"replyable\":true,\"sessionId\":\"conv-42\"}" >/dev/null
api "http://127.0.0.1:$PORT/agents" | grep -q '"sessionId":"conv-42"' || { echo "FAIL: /agents row lacks the event's sessionId"; api "http://127.0.0.1:$PORT/agents"; exit 1; }

# (b) observer noise is dropped, not stored
code=$(api -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/events" -H 'content-type: application/json' \
  -d '{"source":"claude","title":"Claude stopped","level":"info","session":"observer-sessions","cwd":"/x/.claude-mem/observer-sessions"}')
[ "$code" = "202" ] || { echo "FAIL: observer event answered $code, expected 202"; exit 1; }
api "http://127.0.0.1:$PORT/events" | grep -q observer-sessions && { echo "FAIL: observer event was stored"; exit 1; }

# (c) unsupported key still refused; the two new keys accepted
api "http://127.0.0.1:$PORT/agents/$S/send" -H 'content-type: application/json' -d '{"key":"ctrl-z"}' | grep -q unsupported || { echo "FAIL: ctrl-z should be unsupported"; exit 1; }
for k in shift-tab shift-enter; do
  api "http://127.0.0.1:$PORT/agents/$S/send" -H 'content-type: application/json' -d "{\"key\":\"$k\"}" | grep -q '"ok":true' || { echo "FAIL: $k rejected"; exit 1; }
done

# (d) text + Enter aimed at a pane the mux cannot resolve still lands on the session
api "http://127.0.0.1:$PORT/agents/$S/send" -H 'content-type: application/json' -d '{"text":"hello"}' >/dev/null
out=$(api "http://127.0.0.1:$PORT/agents/$S/send" -H 'content-type: application/json' -d "{\"key\":\"enter\",\"pane\":\"$S:9.9\"}")
echo "$out" | grep -q '"ok":true' || { echo "FAIL: enter with a bad pane: $out"; exit 1; }
sleep 0.5
tmux -L "$SOCK" capture-pane -p -t "$S" | grep -q 'got-line-hello' || { echo "FAIL: Enter never reached the session"; tmux -L "$SOCK" capture-pane -p -t "$S"; exit 1; }
echo "check-approve-path: ok — sessionId on /agents, observer dropped, shift-tab/shift-enter, bad-pane Enter retried on the session"

#!/bin/sh
# check-remote-agent-loop.sh — start a session on ANOTHER machine, see its events, type into it, kill it.
#
# check-roundtrip.sh proves hook → /events → /agents/:s/send on a throwaway daemon on this Mac.
# Nothing ever proved the same loop against a remote Linux daemon (the Jetson, the Pi) — which
# is the product: "assign an agent on that box a task from my wrist". This check does, over the
# wire, with the real `mesh` CLI and no LLM tokens: the "agent" is `mesh-agent-run` wrapping a
# shell command, so the Started/Completed events are the ones a hook would post.
#
# Structural half (always runs): the CLI still has `new … -H`, `events`, `send`, `kill`.
# Live half (opt-in, MESH_FLEET_LIVE=1): needs ~/.mesh/hosts.json with the target host.
#   MESH_REMOTE_HOST=jetson   which host (default jetson)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MESH_CLI="$ROOT/install/payload/bin/mesh"
for verb in '"new"' '"events"' '"send"' '"kill"' '"peek"'; do
  grep -q "case $verb" "$MESH_CLI" || { echo "check-remote-agent-loop: FAIL — mesh CLI lost the $verb verb"; exit 1; }
done
if [ "${MESH_FLEET_LIVE:-}" != "1" ]; then
  echo "check-remote-agent-loop: OK (structural; set MESH_FLEET_LIVE=1 MESH_REMOTE_HOST=jetson to run the loop on a remote host)"
  exit 0
fi

HOST="${MESH_REMOTE_HOST:-jetson}"
MESH="${MESH_BIN:-$HOME/.mesh/bin/mesh}"
[ -x "$MESH" ] || { echo "check-remote-agent-loop: SKIP live (no $MESH)"; exit 0; }
"$MESH" health -H "$HOST" >/dev/null 2>&1 || { echo "check-remote-agent-loop: FAIL — $HOST does not answer /health"; exit 1; }

NAME="loop-check-$$"
MARK="loop-mark-$$"
cleanup() { "$MESH" kill "$NAME" -H "$HOST" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# 1. A session on the remote box whose command posts Started/Completed like an agent hook would.
"$MESH" new "$NAME" -H "$HOST" --cmd "sh" >/dev/null || { echo "check-remote-agent-loop: FAIL — mesh new on $HOST failed"; exit 1; }
"$MESH" ls -H "$HOST" --json | grep -q "\"$NAME\"" || { echo "check-remote-agent-loop: FAIL — $NAME missing from mesh ls -H $HOST"; exit 1; }
# Wait for a drawn prompt: a shell that is still starting can discard typeahead, and the
# daemon's own readiness poll gives up after 1.2 s — on a Jetson bash takes longer than that.
i=0
until "$MESH" peek "$NAME" -H "$HOST" -n 5 2>/dev/null | grep -q '[$#] *$'; do
  i=$((i+1)); [ $i -ge 15 ] && { echo "check-remote-agent-loop: FAIL — no shell prompt in $NAME on $HOST after 15s"; exit 1; }
  sleep 1
done
# The first keystrokes after a shell draws its prompt can still be dropped (readline is not
# reading yet — seen on the Jetson: prompt at 1 s, first send lost, second lands). Settle,
# send, and re-send once if the command text has not echoed within 5 s.
sleep 1.5
CMD="MESHD_SESSION=$NAME ~/.mesh/bin/mesh-agent-run loopcheck sh -c 'echo $MARK'"
tries=0
until "$MESH" peek "$NAME" -H "$HOST" -n 20 2>/dev/null | grep -q "loopcheck"; do
  [ $tries -ge 2 ] && { echo "check-remote-agent-loop: FAIL — typed command never echoed in $NAME on $HOST after 2 sends"; exit 1; }
  "$MESH" send "$NAME" -H "$HOST" "$CMD" >/dev/null || { echo "check-remote-agent-loop: FAIL — mesh send to $HOST failed"; exit 1; }
  tries=$((tries+1)); sleep 5
done

# 2. The events land on THAT host's daemon, naming the session.
i=0; got=0
while [ $i -lt 45 ]; do
  if "$MESH" events -H "$HOST" --since "$SINCE" --json 2>/dev/null | grep -q '"Completed"'; then got=1; break; fi
  i=$((i+1)); sleep 1
done
[ "$got" = 1 ] || { echo "check-remote-agent-loop: FAIL — no Completed event on $HOST within 45s"; "$MESH" events -H "$HOST" --since "$SINCE" 2>&1 | tail -5; exit 1; }
EV=$("$MESH" events -H "$HOST" --since "$SINCE" --json)
echo "$EV" | grep -q "\"$NAME\"" || { echo "check-remote-agent-loop: FAIL — events on $HOST do not name session $NAME"; echo "$EV" | head -c 600; exit 1; }

# 3. Typed text reached the pane (the reply path a watch uses).
"$MESH" peek "$NAME" -H "$HOST" -n 40 | grep -q "$MARK" || { echo "check-remote-agent-loop: FAIL — $MARK not in the pane on $HOST"; exit 1; }

# 4. Kill and confirm gone.
"$MESH" kill "$NAME" -H "$HOST" >/dev/null
trap - EXIT
if "$MESH" ls -H "$HOST" --json | grep -q "\"$NAME\""; then echo "check-remote-agent-loop: FAIL — $NAME survived kill on $HOST"; exit 1; fi
echo "check-remote-agent-loop: OK — session created on $HOST, Started/Completed events seen, send landed, killed"

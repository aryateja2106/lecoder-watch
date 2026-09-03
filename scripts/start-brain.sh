#!/bin/sh
# Start the local model server with a chosen memory profile, and wait until it answers.
#
# Slots are a speed dial, not a quality dial: fewer wired slots use less memory and read
# more from SSD. On a 24 GiB host the built-in rule gives Qwen 3.6 96 slots (~6.8 GB),
# which is often not the trade you want on a laptop you are also working on.
#
#   scripts/start-brain.sh --model ~/models/qwen36.gturbo            # 32 slots (~2.2 GB)
#   scripts/start-brain.sh --model ... --slots 16                    # the floor, ~1.45 GB
#   scripts/start-brain.sh --model ... --slots auto --port 8091      # the built-in rule
#
# 32 is the default here rather than 16 on purpose. 16 is the exact floor chunked prefill
# can schedule -- (maxPendingDepth + 1) * tileExperts -- so it has zero headroom, and it
# is also the slowest rung. 16 stays reachable for measuring the smallest footprint.
#
# Requires the --expert-cache-slots patch in references/patches/. Without it the server
# has no way to accept a profile; this script says so rather than starting a server that
# silently ignores the request.
set -eu

MODEL=""; SLOTS="32"; PORT="8080"; CONTEXT="16384"; BIN="${MFERENCE_SERVER:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --slots) SLOTS="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --max-context) CONTEXT="$2"; shift 2 ;;
    --bin) BIN="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$MODEL" ] || { echo "error: --model <dir> is required" >&2; exit 2; }
[ -d "$MODEL" ] || { echo "error: no such model directory: $MODEL" >&2; exit 2; }

if [ -z "$BIN" ]; then
  BIN="$(command -v MferenceServer 2>/dev/null || echo ".build/release/MferenceServer")"
fi
[ -x "$BIN" ] || { echo "error: MferenceServer not found at $BIN (build it, or pass --bin)" >&2; exit 2; }

# Refuse to start a second server on a port something already answers on -- that is
# almost always LM Studio or an earlier run, and killing either is not this script's job.
if curl -sf --max-time 2 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
  echo "error: something already answers on 127.0.0.1:$PORT. Use --port, or stop it yourself." >&2
  exit 2
fi

ARGS="--model $MODEL --port $PORT --max-context $CONTEXT"
if [ "$SLOTS" != "auto" ]; then
  if "$BIN" --help 2>&1 | grep -q -- "--expert-cache-slots"; then
    ARGS="$ARGS --expert-cache-slots $SLOTS"
  else
    echo "error: this MferenceServer does not support --expert-cache-slots." >&2
    echo "       Apply references/patches/0001-mference-server-expert-cache-slots.patch" >&2
    echo "       in the fork and rebuild, or pass --slots auto." >&2
    exit 2
  fi
fi

echo "starting: $BIN $ARGS"
# The PID comes from $!, never from pgrep: pgrep matches the newest MferenceServer
# anywhere on the machine, which may be the user's own.
# shellcheck disable=SC2086
"$BIN" $ARGS &
PID=$!

i=0
while [ "$i" -lt 120 ]; do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "error: server exited during startup" >&2
    wait "$PID" || true
    exit 1
  fi
  if curl -sf --max-time 2 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
    echo "ready on http://127.0.0.1:$PORT/v1  (pid $PID, slots $SLOTS)"
    echo "grade it:  bun run scripts/brain-eval/eval.ts --endpoint http://127.0.0.1:$PORT/v1"
    echo "stop it:   kill $PID"
    exit 0
  fi
  i=$((i + 1))
  sleep 1
done

echo "error: server did not answer within 120s (pid $PID still running; kill it yourself)" >&2
exit 1

#!/bin/sh
# check-paste-epipe.sh — a big paste must not take the machine off the mesh.
#
# `POST /agents/<s>/send` with paste:true streamed the text into `<mux> load-buffer -`.
# rmux 0.3.1 — the default multiplexer on macOS — does not treat `-` as stdin, so it exits
# without ever draining that pipe. Under ~400 KB the payload fits the kernel pipe buffer
# and nothing shows; from ~1 MB the write fails with EPIPE, and on a bun FileSink that
# error arrives OUT OF BAND. It is not the returned promise, so the `.catch()` wrapped
# around the call never fires and a try/catch cannot see it either: the function returned
# {code:1} normally, the request completed, and only then did the daemon exit.
#
# One tap of the phone's paste button after copying a long log did it, because
# iOS pasteIntoPane() sends the whole UIPasteboard with no length cap.
#
# The mux here is a stub that behaves exactly like rmux: it resolves the session, and
# fails `load-buffer` without reading a byte. The assertion is simply that the daemon is
# still answering afterwards.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-paste-epipe: SKIP (no bun)"; exit 0; }

TMP="$(mktemp -d)"
PORT=8894
PID=""
cleanup() { [ -n "$PID" ] && { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }; rm -rf "$TMP"; }
trap cleanup EXIT

# A multiplexer that resolves sessions and refuses load-buffer without reading stdin.
cat > "$TMP/stubmux" <<'MUXEOF'
#!/bin/sh
case "$1" in
  has-session) echo 0; exit 0 ;;
  load-buffer) exit 1 ;;        # <- exits WITHOUT draining stdin, exactly like rmux
  *) exit 0 ;;
esac
MUXEOF
chmod +x "$TMP/stubmux"

mkdir -p "$TMP/.mesh"
TOKEN="check-paste-epipe-$$"
printf '%s\n' "$TOKEN" > "$TMP/.mesh/token"

HOME="$TMP" MESHD_TOKEN="$TOKEN" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" \
MESH_MUX="$TMP/stubmux" MESHD_EVENTS_PATH="$TMP/events.jsonl" MESHD_TELEMETRY=off \
  bun "$ROOT/install/payload/meshd/server.ts" >"$TMP/meshd.log" 2>&1 &
PID=$!

up=0
i=0
while [ "$i" -lt 40 ]; do
  curl -sf -m 2 -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 \
    && { up=1; break; }
  i=$((i + 1))
done
[ "$up" = "1" ] || { echo "FAIL: check-paste-epipe: daemon never came up"; sed -n '1,15p' "$TMP/meshd.log"; exit 1; }

# ~1.5 MB with a newline in it, because only multiline text takes the paste path.
/usr/bin/python3 -c "
import json,sys
json.dump({'text': 'first line\n' + 'x'*1500000, 'paste': True}, open('$TMP/body.json','w'))
"

curl -s -m 30 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -X POST --data-binary @"$TMP/body.json" \
  "http://127.0.0.1:$PORT/agents/pastesess/send" > "$TMP/send.out" 2>&1 || true

# The one assertion that matters. A daemon that died here is a machine that dropped off
# the mesh mid-session, with every in-flight request and stream lost — supervision may
# respawn it, but the user's session is gone either way.
if ! curl -sf -m 5 -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "FAIL: check-paste-epipe: the daemon died on a 1.5 MB paste"
  echo "  send response: $(head -c 200 "$TMP/send.out")"
  echo "  daemon log tail:"; tail -8 "$TMP/meshd.log" | sed 's/^/    /'
  exit 1
fi

# And the paste still had to be delivered by the fallback, not silently dropped.
grep -q '"ok":true' "$TMP/send.out" \
  || { echo "FAIL: check-paste-epipe: daemon survived but the send did not report ok: $(head -c 200 "$TMP/send.out")"; exit 1; }

echo "check-paste-epipe: OK (1.5 MB paste against a non-draining mux; daemon alive, send delivered)"

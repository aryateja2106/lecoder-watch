#!/bin/sh
# Speak one saved note on a spare daemon at 127.0.0.1:8898. State and HOME
# stay under /tmp. Telemetry stays off. No model stub.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$ROOT/scripts/$(basename "$0")"
cd "$ROOT/install/payload/meshd"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

python3 - "$SELF" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
proc = "/" + "proc"
bad_port = "88" + "99"
if text.count(proc) != 0 or text.count(bad_port) != 0:
    raise SystemExit("FAIL: script uses forbidden host paths or ports")
PY

TH="$(mktemp -d /tmp/speak-saved-note.XXXXXX)"
STATE="$TH/state"
HOME_DIR="$TH/home"
LOG="$TH/meshd.log"
PORT=8898
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
NOTE_TITLE="Saved for speech"
NOTE_BODY="The pairing code K7QM-2N4P is already on disk."
SRV=
NOTE_ID=
NOTE_FILE=

stop_srv() {
  [ -n "${SRV:-}" ] || return 0
  kill "$SRV" 2>/dev/null || true
  n=0
  while kill -0 "$SRV" 2>/dev/null && [ "$n" -lt 20 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -KILL "$SRV" 2>/dev/null || true
  wait "$SRV" 2>/dev/null || true
  SRV=
}

cleanup() {
  ec=$?
  stop_srv
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn | grep -q ":${PORT} "; then
      echo "FAIL: port ${PORT} is still listening"
      ec=1
    fi
  fi
  rm -rf "$TH"
  exit "$ec"
}
trap cleanup EXIT

mkdir -p "$STATE" "$HOME_DIR"
: > "$TH/tts-in"

cat > "$TH/tts" <<EOF
#!/bin/sh
cat >> "$TH/tts-in"
exit 0
EOF
chmod 700 "$TH/tts"

if command -v ss >/dev/null 2>&1; then
  if ss -ltn | grep -q ":${PORT} "; then
    echo "FAIL: port ${PORT} is already in use"
    exit 1
  fi
fi

start_daemon() {
  tts="$1"
  stop_srv
  MESHD_PORT=$PORT \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$STATE" \
  MESHD_TELEMETRY=off \
  MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
  MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
  MESHD_KB_PATH="$TH/kb.sqlite" \
  HOME="$HOME_DIR" \
  MESH_TTS="$tts" \
  bun server.ts >"$LOG" 2>&1 &
  SRV=$!
  up=0
  i=0
  while [ "$i" -lt 50 ]; do
    if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      up=1
      break
    fi
    kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited before listening"; cat "$LOG"; exit 1; }
    sleep 0.1
    i=$((i + 1))
  done
  [ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on ${PORT}"; cat "$LOG"; exit 1; }
}

start_daemon "$TH/tts"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/create.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "{\"title\":\"${NOTE_TITLE}\",\"body\":\"${NOTE_BODY}\"}" \
  "http://127.0.0.1:${PORT}/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/create.json"; echo; cat "$LOG"; exit 1; }

NOTE_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/create.json")"
NOTE_FILE="$STATE/knowledge/${NOTE_ID}.json"
[ -f "$NOTE_FILE" ] || { echo "FAIL: note file missing"; exit 1; }
cp "$NOTE_FILE" "$TH/note-before.json"

code="$(curl --connect-timeout 1 --max-time 10 -sS -o "$TH/speak.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data '{"speak":true}' \
  "http://127.0.0.1:${PORT}/knowledge/${NOTE_ID}" || true)"
[ "$code" = "200" ] || { echo "FAIL: speak -> ${code}"; cat "$TH/speak.json"; echo; cat "$LOG"; exit 1; }

python3 - "$TH/speak.json" "$NOTE_BODY" "$NOTE_TITLE" "$NOTE_ID" "$TH/tts-in" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
body, title, note_id, heard_path = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
if body in raw:
    raise SystemExit("FAIL: response text contains the body")
data = json.loads(raw)
if set(data) != {"id", "title", "spoken"}:
    raise SystemExit("FAIL: response keys are %r" % (sorted(data),))
if data.get("id") != note_id or data.get("title") != title or data.get("spoken") is not True:
    raise SystemExit("FAIL: response is %r" % (data,))
heard = open(heard_path, encoding="utf-8").read()
if body not in heard:
    raise SystemExit("FAIL: speaker stdin did not include the stored body")
PY

cmp -s "$TH/note-before.json" "$NOTE_FILE" || { echo "FAIL: speak changed the note file"; exit 1; }
fmode="$(stat -c '%a' "$NOTE_FILE" 2>/dev/null || stat -f '%OLp' "$NOTE_FILE")"
fmode="${fmode#0}"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
echo "check-speak-saved-note: local TTS receives the body and the file stays mode 600"

stop_srv
start_daemon "http://127.0.0.1:9999/speaker"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/remote.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data '{"speak":true}' \
  "http://127.0.0.1:${PORT}/knowledge/${NOTE_ID}" || true)"
[ "$code" = "400" ] || { echo "FAIL: remote MESH_TTS -> ${code}"; cat "$TH/remote.json"; exit 1; }
python3 - "$TH/remote.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("error") != "tts must be a local binary":
    raise SystemExit("FAIL: error is %r" % (data.get("error"),))
PY
cmp -s "$TH/note-before.json" "$NOTE_FILE" || { echo "FAIL: remote TTS wrote the note"; exit 1; }
echo "check-speak-saved-note: remote MESH_TTS is 400 and wrote nothing"

echo "check-speak-saved-note: OK"

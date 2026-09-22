#!/bin/sh
# Spare daemon on 127.0.0.1:8898: POST /knowledge/:id with a local audio file
# and MESH_STT replaces that note's body from stdout. A missing id creates
# nothing and does not run the binary. A remote URL does not write or run.
# An empty transcript leaves the old body. This script does not use port 8899,
# does not read a real home directory, and does not prove a microphone.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH
command -v bun >/dev/null 2>&1 || { echo "check-spoken-note-replace: SKIP (bun not installed)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

grep -q 'handleKnowledge' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route knowledge"
  exit 1
}
if grep -E -n 'supabase|fetch\(|ai-gateway' "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: knowledge.ts reaches the network"
  exit 1
fi
grep -q 'MESH_STT' "$ROOT/install/payload/meshd/knowledge.ts" || {
  echo "FAIL: knowledge.ts does not name MESH_STT"
  exit 1
}

TH="$(mktemp -d)"
STATE="$TH/state"
PDF="$TH/paper.pdf"
AUDIO="$TH/clip.wav"
LOG="$TH/meshd.log"
PORT=8898
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
SRV=
NOTE_FILE=

[ "$PORT" = "8898" ] || { echo "FAIL: spare daemon must listen on 8898"; exit 1; }

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
  rm -rf "$TH"
  exit "$ec"
}
trap cleanup EXIT

printf 'RIFF' > "$AUDIO"

cat > "$TH/stt" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >> "$TH/stt-args"
printf '%s\n' "Replaced from speech"
printf '%s\n' "Second line of transcript"
exit 0
EOF
cat > "$TH/stt-empty" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >> "$TH/stt-empty-args"
exit 0
EOF
chmod 700 "$TH/stt" "$TH/stt-empty"
: > "$TH/stt-args"
: > "$TH/stt-empty-args"

python3 - "$PDF" <<'PY'
import sys
path = sys.argv[1]
stream = b"BT /F1 12 Tf 72 720 Td (Original body on disk) Tj ET\n"
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"endstream",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    b"<< /Title (Spare note) >>",
]
out = bytearray(b"%PDF-1.4\n")
for i, obj in enumerate(objects, start=1):
    out += f"{i} 0 obj\n".encode() + obj + b"\nendobj\n"
out += b"trailer\n<< /Root 1 0 R /Info 6 0 R >>\n%%EOF\n"
open(path, "wb").write(out)
PY

if command -v ss >/dev/null 2>&1; then
  if ss -ltn | grep -q ':8898 '; then
    echo "FAIL: port 8898 is already in use"
    exit 1
  fi
fi

start_daemon() {
  stop_srv
  MESHD_PORT=$PORT \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$STATE" \
  MESHD_TELEMETRY=off \
  MESH_STT="$TH/stt" \
  MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
  MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
  MESHD_KB_PATH="$TH/kb.sqlite" \
  HOME="$TH" \
  bun server.ts >"$LOG" 2>&1 &
  SRV=$!
  up=0
  i=0
  while [ "$i" -lt 50 ]; do
    if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      up=1
      break
    fi
    kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited before listening"; cat "$LOG"; exit 1; }
    sleep 0.1
    i=$((i + 1))
  done
  [ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on $PORT"; cat "$LOG"; exit 1; }
}

note_count() {
  found=0
  for f in "$STATE/knowledge"/*.json; do
    [ -f "$f" ] || continue
    found=$((found + 1))
  done
  echo "$found"
}

mode_of() {
  m="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1")"
  echo "${m#0}"
}

stt_lines() {
  wc -l < "$TH/stt-args" | tr -d ' '
}

start_daemon

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/post.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "{\"path\":\"${PDF}\"}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; echo; cat "$LOG"; exit 1; }
ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/post.json")"
NOTE_FILE="$STATE/knowledge/${ID}.json"
[ -f "$NOTE_FILE" ] || { echo "FAIL: created note file is missing"; exit 1; }
python3 - "$NOTE_FILE" <<'PY'
import json, sys
note = json.load(open(sys.argv[1]))
if "Original body on disk" not in note.get("body", ""):
    raise SystemExit("FAIL: initial body is %r" % (note.get("body"),))
PY

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/mint.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "{\"path\":\"${PDF}\"}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: second POST /knowledge -> ${code}"; exit 1; }
MINTED="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/mint.json")"
[ "$MINTED" != "$ID" ] || { echo "FAIL: POST /knowledge did not mint a new id"; exit 1; }
rm -f "$STATE/knowledge/${MINTED}.json"
[ "$(note_count)" = "1" ] || { echo "FAIL: note count after mint check is $(note_count)"; exit 1; }

AUDIO_JSON="$(python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1]}))' "$AUDIO")"
before="$(stt_lines)"
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/replaced.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "$AUDIO_JSON" \
  "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
[ "$code" = "200" ] || { echo "FAIL: POST /knowledge/:id audio -> ${code}"; cat "$TH/replaced.json"; echo; cat "$LOG"; exit 1; }
[ "$(stt_lines)" -eq 1 ] || { echo "FAIL: transcriber was not run once"; exit 1; }
[ "$(stt_lines)" -gt "$before" ] || { echo "FAIL: transcriber did not run"; exit 1; }
python3 - "$TH/replaced.json" "$NOTE_FILE" "$AUDIO" "$TH/stt-args" <<'PY'
import json, sys
resp = json.load(open(sys.argv[1]))
note = json.load(open(sys.argv[2]))
audio = sys.argv[3]
args = open(sys.argv[4]).read().splitlines()
if args != [audio]:
    raise SystemExit("FAIL: transcriber args are %r" % (args,))
want = "Replaced from speech\nSecond line of transcript"
if resp.get("body") != want:
    raise SystemExit("FAIL: response body is %r" % (resp.get("body"),))
if note.get("body") != want:
    raise SystemExit("FAIL: stored body is %r" % (note.get("body"),))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: title changed to %r" % (note.get("title"),))
PY
echo "check-spoken-note-replace: transcript is the note body"

fmode="$(mode_of "$NOTE_FILE")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-spoken-note-replace: file mode 600"
echo "check-spoken-note-replace: directory mode 700"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; exit 1; }
python3 - "$TH/list.json" "$ID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
notes = data.get("notes")
if not isinstance(notes, list) or len(notes) != 1:
    raise SystemExit("FAIL: list is %r" % (notes,))
note = notes[0]
if set(note.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
if note.get("id") != sys.argv[2] or note.get("title") != "Spare note":
    raise SystemExit("FAIL: list note is %r" % (note,))
if "Replaced from speech" in json.dumps(data):
    raise SystemExit("FAIL: list leaked the body")
PY
echo "check-spoken-note-replace: list is id and title"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/one.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge/:id -> ${code}"; exit 1; }
python3 - "$TH/one.json" <<'PY'
import json, sys
note = json.load(open(sys.argv[1]))
want = "Replaced from speech\nSecond line of transcript"
if note.get("body") != want:
    raise SystemExit("FAIL: read body is %r" % (note.get("body"),))
PY
echo "check-spoken-note-replace: read returns the new body"

cp "$NOTE_FILE" "$TH/frozen.json"
refuse_audio() {
  label="$1"
  target="$2"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1]}))' "$target")"
  before="$(stt_lines)"
  code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/rej.json" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data "$payload" \
    "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
  cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: $label wrote the note"; exit 1; }
  after="$(stt_lines)"
  [ "$before" = "$after" ] || { echo "FAIL: $label spawned the transcriber"; exit 1; }
  case "$code" in
    200|201) echo "FAIL: $label was stored ($code)"; exit 1 ;;
  esac
  echo "check-spoken-note-replace: $label"
}

refuse_audio "remote audio did not run" "http://127.0.0.1:9/clip.wav"
refuse_audio "https audio did not run" "https://example.com/clip.wav"
refuse_audio "scheme audio did not run" "file://${AUDIO}"
refuse_audio "protocol-relative audio did not run" "//127.0.0.1/clip.wav"
refuse_audio "scheme in path did not run" "${TH}/bin://clip.wav"

MISS="$(python3 -c 'import uuid; print(uuid.uuid4())')"
before="$(stt_lines)"
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/miss-id.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "$AUDIO_JSON" \
  "http://127.0.0.1:$PORT/knowledge/${MISS}" || true)"
[ "$code" = "404" ] || { echo "FAIL: missing id -> ${code}"; cat "$TH/miss-id.json"; exit 1; }
[ ! -e "$STATE/knowledge/${MISS}.json" ] || { echo "FAIL: missing id created a note"; exit 1; }
after="$(stt_lines)"
[ "$before" = "$after" ] || { echo "FAIL: missing id spawned the transcriber"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: missing id rewrote the note"; exit 1; }
echo "check-spoken-note-replace: missing id created nothing"

stop_srv
MESHD_PORT=$PORT \
MESHD_HOST=127.0.0.1 \
MESHD_TOKEN="$TOKEN" \
MESHD_STATE="$STATE" \
MESHD_TELEMETRY=off \
MESH_STT="$TH/stt-empty" \
MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
MESHD_KB_PATH="$TH/kb.sqlite" \
HOME="$TH" \
bun server.ts >"$LOG" 2>&1 &
SRV=$!
up=0
i=0
while [ "$i" -lt 50 ]; do
  if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    up=1
    break
  fi
  kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited for empty transcript test"; cat "$LOG"; exit 1; }
  sleep 0.1
  i=$((i + 1))
done
[ "$up" -eq 1 ] || { echo "FAIL: meshd did not restart"; exit 1; }

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/empty.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "$AUDIO_JSON" \
  "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
[ "$code" != "200" ] || { echo "FAIL: empty transcript returned 200"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: empty transcript wiped the body"; exit 1; }
[ -s "$TH/stt-empty-args" ] || { echo "FAIL: empty transcript case did not run the binary"; exit 1; }
echo "check-spoken-note-replace: empty transcript kept the old body"

echo "check-spoken-note-replace: OK"

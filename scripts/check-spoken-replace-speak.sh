#!/bin/sh
# Spare daemon on 127.0.0.1:8898: POST /knowledge/:id {audio, speak:true}
# replaces that note from MESH_STT, then runs MESH_TTS only when speak is true
# and the binary is local and exits 0. spoken is true only then. speak false
# or a missing TTS binary stores the transcript with spoken false. A remote
# URL, a scheme, or a protocol-relative path for the audio or the TTS binary
# does not write and does not spawn. An empty transcript keeps the old body
# and does not speak. A missing id creates nothing. This script does not use
# port 8899, does not read a real home directory, and does not prove a
# microphone or a speaker.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH
command -v bun >/dev/null 2>&1 || { echo "check-spoken-replace-speak: SKIP (bun not installed)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

calls="$(grep -c 'await handleKnowledge(' "$ROOT/install/payload/meshd/server.ts" || true)"
[ "$calls" = "1" ] || { echo "FAIL: server.ts must call handleKnowledge once"; exit 1; }
if grep -E -n 'supabase|fetch\(|ai-gateway' "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: knowledge.ts reaches the network"
  exit 1
fi
grep -q 'MESH_STT' "$ROOT/install/payload/meshd/knowledge.ts" || {
  echo "FAIL: knowledge.ts does not name MESH_STT"
  exit 1
}
grep -q 'MESH_TTS' "$ROOT/install/payload/meshd/knowledge.ts" || {
  echo "FAIL: knowledge.ts does not name MESH_TTS"
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
[ "$PORT" != "8899" ] || { echo "FAIL: port 8899 is not a spare daemon"; exit 1; }

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
: > "$TH/stt-args"
: > "$TH/stt-say"
: > "$TH/tts-out"
: > "$TH/tts-runs"
: > "$TH/tts-fail-out"
: > "$TH/tts-fail-runs"

cat > "$TH/stt" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >> "$TH/stt-args"
cat "$TH/stt-say"
exit 0
EOF
cat > "$TH/tts" <<EOF
#!/bin/sh
cat >> "$TH/tts-out"
printf '.\n' >> "$TH/tts-runs"
exit 0
EOF
cat > "$TH/tts-fail" <<EOF
#!/bin/sh
cat >> "$TH/tts-fail-out"
printf '.\n' >> "$TH/tts-fail-runs"
exit 1
EOF
chmod 700 "$TH/stt" "$TH/tts" "$TH/tts-fail"

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
  stt_bin="$1"
  tts_bin="$2"
  stop_srv
  MESHD_PORT=$PORT \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$STATE" \
  MESHD_TELEMETRY=off \
  MESH_STT="$stt_bin" \
  MESH_TTS="$tts_bin" \
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

lines_of() {
  wc -l < "$1" | tr -d ' '
}

mode_of() {
  m="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1")"
  echo "${m#0}"
}

post_audio() {
  out="$1"
  speak="$2"
  python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1], "speak": sys.argv[2] == "true"}))' "$AUDIO" "$speak" > "$TH/payload.json"
  curl --connect-timeout 1 --max-time 10 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/payload.json" \
    "http://127.0.0.1:$PORT/knowledge/${ID}" || true
}

start_daemon "$TH/stt" "$TH/tts"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/post.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "{\"path\":\"${PDF}\"}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; echo; cat "$LOG"; exit 1; }
[ "$(lines_of "$TH/tts-runs")" = "0" ] || { echo "FAIL: creating a note spawned TTS"; exit 1; }
ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/post.json")"
NOTE_FILE="$STATE/knowledge/${ID}.json"
[ -f "$NOTE_FILE" ] || { echo "FAIL: created note file is missing"; exit 1; }
python3 - "$NOTE_FILE" <<'PY'
import json, sys
note = json.load(open(sys.argv[1]))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: title is %r" % (note.get("title"),))
if "Original body on disk" not in note.get("body", ""):
    raise SystemExit("FAIL: initial body is %r" % (note.get("body"),))
PY

printf '%s\n' "Replaced from speech" "Second line of transcript" > "$TH/stt-say"
code="$(post_audio "$TH/spoken.json" true)"
[ "$code" = "200" ] || { echo "FAIL: POST /knowledge/:id speak -> ${code}"; cat "$TH/spoken.json"; echo; cat "$LOG"; exit 1; }
[ "$(lines_of "$TH/stt-args")" = "1" ] || { echo "FAIL: transcriber was not run once"; exit 1; }
[ "$(lines_of "$TH/tts-runs")" = "1" ] || { echo "FAIL: speaker was not run once"; exit 1; }
python3 - "$TH/spoken.json" "$NOTE_FILE" "$AUDIO" "$TH/stt-args" "$TH/tts-out" <<'PY'
import json, sys
resp = json.load(open(sys.argv[1]))
note = json.load(open(sys.argv[2]))
audio = sys.argv[3]
args = open(sys.argv[4]).read().splitlines()
heard = open(sys.argv[5]).read()
want = "Replaced from speech\nSecond line of transcript"
if args != [audio]:
    raise SystemExit("FAIL: transcriber args are %r" % (args,))
if resp.get("spoken") is not True:
    raise SystemExit("FAIL: spoken is %r" % (resp.get("spoken"),))
if resp.get("body") != want:
    raise SystemExit("FAIL: response body is %r" % (resp.get("body"),))
if note.get("body") != want:
    raise SystemExit("FAIL: stored body is %r" % (note.get("body"),))
if resp.get("title") != "Spare note" or note.get("title") != "Spare note":
    raise SystemExit("FAIL: title changed")
if "Spare note" not in heard or want not in heard:
    raise SystemExit("FAIL: speaker heard %r" % (heard,))
if "Original body on disk" in heard:
    raise SystemExit("FAIL: speaker heard the old body")
PY
echo "check-spoken-replace-speak: local TTS that exits 0 returns spoken true"

fmode="$(mode_of "$NOTE_FILE")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-spoken-replace-speak: file mode 600"
echo "check-spoken-replace-speak: directory mode 700"

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
blob = json.dumps(data)
if "Replaced from speech" in blob or "spoken" in blob:
    raise SystemExit("FAIL: list leaked the body")
PY
echo "check-spoken-replace-speak: list is id and title"
echo "check-spoken-replace-speak: title stayed"

printf '%s\n' "Stored without speaking" > "$TH/stt-say"
before_tts="$(lines_of "$TH/tts-runs")"
code="$(post_audio "$TH/quiet.json" false)"
[ "$code" = "200" ] || { echo "FAIL: speak false -> ${code}"; cat "$TH/quiet.json"; echo; exit 1; }
[ "$(lines_of "$TH/tts-runs")" = "$before_tts" ] || { echo "FAIL: speak false spawned TTS"; exit 1; }
python3 - "$TH/quiet.json" "$NOTE_FILE" <<'PY'
import json, sys
resp = json.load(open(sys.argv[1]))
note = json.load(open(sys.argv[2]))
want = "Stored without speaking"
if resp.get("spoken") is not False:
    raise SystemExit("FAIL: speak false returned spoken %r" % (resp.get("spoken"),))
if resp.get("body") != want or note.get("body") != want:
    raise SystemExit("FAIL: speak false body is %r" % (note.get("body"),))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: speak false changed the title")
PY
echo "check-spoken-replace-speak: speak false stores the transcript"

cp "$NOTE_FILE" "$TH/frozen.json"
: > "$TH/stt-say"
before_stt="$(lines_of "$TH/stt-args")"
before_tts="$(lines_of "$TH/tts-runs")"
code="$(post_audio "$TH/empty.json" true)"
[ "$code" != "200" ] && [ "$code" != "201" ] || { echo "FAIL: empty transcript returned ${code}"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: empty transcript wiped the body"; exit 1; }
[ "$(lines_of "$TH/stt-args")" -gt "$before_stt" ] || { echo "FAIL: empty transcript did not run STT"; exit 1; }
[ "$(lines_of "$TH/tts-runs")" = "$before_tts" ] || { echo "FAIL: empty transcript spawned TTS"; exit 1; }
echo "check-spoken-replace-speak: empty transcript kept the old body"

refuse_audio() {
  label="$1"
  target="$2"
  cp "$NOTE_FILE" "$TH/frozen.json"
  before_stt="$(lines_of "$TH/stt-args")"
  before_tts="$(lines_of "$TH/tts-runs")"
  python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1], "speak": True}))' "$target" > "$TH/payload.json"
  code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/rej.json" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/payload.json" \
    "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
  cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: $label wrote the note"; exit 1; }
  [ "$(lines_of "$TH/stt-args")" = "$before_stt" ] || { echo "FAIL: $label spawned STT"; exit 1; }
  [ "$(lines_of "$TH/tts-runs")" = "$before_tts" ] || { echo "FAIL: $label spawned TTS"; exit 1; }
  case "$code" in
    200|201) echo "FAIL: $label was stored ($code)"; exit 1 ;;
  esac
  echo "check-spoken-replace-speak: $label"
}

refuse_audio "remote audio did not run" "http://127.0.0.1:9/clip.wav"
refuse_audio "scheme audio did not run" "file://${AUDIO}"
refuse_audio "protocol-relative audio did not run" "//127.0.0.1/clip.wav"

MISS="$(python3 -c 'import uuid; print(uuid.uuid4())')"
cp "$NOTE_FILE" "$TH/frozen.json"
before_stt="$(lines_of "$TH/stt-args")"
before_tts="$(lines_of "$TH/tts-runs")"
python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1], "speak": True}))' "$AUDIO" > "$TH/payload.json"
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/miss-id.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/payload.json" \
  "http://127.0.0.1:$PORT/knowledge/${MISS}" || true)"
[ "$code" = "404" ] || { echo "FAIL: missing id -> ${code}"; cat "$TH/miss-id.json"; exit 1; }
[ ! -e "$STATE/knowledge/${MISS}.json" ] || { echo "FAIL: missing id created a note"; exit 1; }
[ "$(lines_of "$TH/stt-args")" = "$before_stt" ] || { echo "FAIL: missing id spawned STT"; exit 1; }
[ "$(lines_of "$TH/tts-runs")" = "$before_tts" ] || { echo "FAIL: missing id spawned TTS"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: missing id rewrote the note"; exit 1; }
echo "check-spoken-replace-speak: missing id created nothing"

printf '%s\n' "Stored without a speaker" > "$TH/stt-say"
before_tts="$(lines_of "$TH/tts-runs")"
start_daemon "$TH/stt" "$TH/missing-tts"
code="$(post_audio "$TH/missing-tts.json" true)"
[ "$code" = "200" ] || { echo "FAIL: missing TTS -> ${code}"; cat "$TH/missing-tts.json"; echo; cat "$LOG"; exit 1; }
[ "$(lines_of "$TH/tts-runs")" = "$before_tts" ] || { echo "FAIL: missing TTS spawned the local speaker"; exit 1; }
python3 - "$TH/missing-tts.json" "$NOTE_FILE" <<'PY'
import json, sys
resp = json.load(open(sys.argv[1]))
note = json.load(open(sys.argv[2]))
want = "Stored without a speaker"
if resp.get("spoken") is not False:
    raise SystemExit("FAIL: missing TTS returned spoken %r" % (resp.get("spoken"),))
if resp.get("body") != want or note.get("body") != want:
    raise SystemExit("FAIL: missing TTS body is %r" % (note.get("body"),))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: missing TTS changed the title")
PY
echo "check-spoken-replace-speak: missing TTS stores the transcript"

printf '%s\n' "Stored after a failed speaker" > "$TH/stt-say"
start_daemon "$TH/stt" "$TH/tts-fail"
code="$(post_audio "$TH/fail-tts.json" true)"
[ "$code" = "200" ] || { echo "FAIL: nonzero TTS -> ${code}"; cat "$TH/fail-tts.json"; echo; cat "$LOG"; exit 1; }
[ "$(lines_of "$TH/tts-fail-runs")" = "1" ] || { echo "FAIL: nonzero TTS did not run"; exit 1; }
python3 - "$TH/fail-tts.json" "$NOTE_FILE" "$TH/tts-fail-out" <<'PY'
import json, sys
resp = json.load(open(sys.argv[1]))
note = json.load(open(sys.argv[2]))
heard = open(sys.argv[3]).read()
want = "Stored after a failed speaker"
if resp.get("spoken") is not False:
    raise SystemExit("FAIL: nonzero TTS returned spoken %r" % (resp.get("spoken"),))
if resp.get("body") != want or note.get("body") != want:
    raise SystemExit("FAIL: nonzero TTS body is %r" % (note.get("body"),))
if want not in heard:
    raise SystemExit("FAIL: nonzero TTS did not receive the transcript")
PY
echo "check-spoken-replace-speak: nonzero TTS leaves spoken false"

refuse_tts() {
  label="$1"
  tts_value="$2"
  cp "$NOTE_FILE" "$TH/frozen.json"
  before_stt="$(lines_of "$TH/stt-args")"
  before_tts="$(lines_of "$TH/tts-runs")"
  before_fail="$(lines_of "$TH/tts-fail-runs")"
  printf '%s\n' "This transcript must not be stored" > "$TH/stt-say"
  start_daemon "$TH/stt" "$tts_value"
  code="$(post_audio "$TH/rej-tts.json" true)"
  cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: $label wrote the note"; exit 1; }
  [ "$(lines_of "$TH/stt-args")" = "$before_stt" ] || { echo "FAIL: $label spawned STT"; exit 1; }
  [ "$(lines_of "$TH/tts-runs")" = "$before_tts" ] || { echo "FAIL: $label spawned TTS"; exit 1; }
  [ "$(lines_of "$TH/tts-fail-runs")" = "$before_fail" ] || { echo "FAIL: $label spawned the failing TTS"; exit 1; }
  case "$code" in
    200|201) echo "FAIL: $label was stored ($code)"; exit 1 ;;
  esac
  echo "check-spoken-replace-speak: $label"
}

refuse_tts "remote TTS did not run" "http://127.0.0.1:9/say"
refuse_tts "scheme TTS did not run" "file://${TH}/tts"
refuse_tts "protocol-relative TTS did not run" "//${TH}/tts"

echo "check-spoken-replace-speak: OK"

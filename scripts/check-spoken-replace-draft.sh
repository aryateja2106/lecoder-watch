#!/bin/sh
# Spare daemon on 127.0.0.1:8898: POST /knowledge/:id {audio, speak:true}
# replaces one note from a local MESH_STT binary, then a local MESH_TTS
# binary that exits 0 makes spoken true. The agent drafts that new
# transcript into one held file, mode 600, and does not execute it. A
# pairing-code transcript and a hosts.json transcript stay on hold, and
# the loopback model is not called. A second note replaced with a clean
# paper summary still drafts that new body. A missing id does not call
# the model and creates no file. A remote URL, a file:// path, or a
# protocol-relative path for the audio or the TTS binary does not write
# and does not call the model. A command without confirm does not run.
# This script does not use port 8899, does not read a real home directory,
# and does not prove a microphone or a speaker.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
unset AI_GATEWAY_API_KEY
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

calls="$(grep -c 'await handleKnowledge(' "$ROOT/install/payload/meshd/server.ts" || true)"
[ "$calls" = "1" ] || { echo "FAIL: server.ts must call handleKnowledge once"; exit 1; }
if grep -E -n 'supabase|fetch\(|ai-gateway' "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: knowledge.ts reaches the network"
  exit 1
fi
if grep -E -n 'supabase|ai-gateway' \
  "$ROOT/install/payload/meshd/agent-note.ts" \
  "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: note path names supabase or the AI gateway"
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
grep -q 'handleAgentNote' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route agent-note"
  exit 1
}
grep -q '../jev-routing/route.ts' "$ROOT/experiments/note-route-draft/draft.ts" || {
  echo "FAIL: draft does not use the existing route"
  exit 1
}
if grep -E -q 'child_process|Bun\.spawn|execFile\(' "$ROOT/experiments/note-route-draft/draft.ts"; then
  echo "FAIL: draft module can run a file"
  exit 1
fi
if grep -q 'ai-gateway.vercel.sh' "$ROOT/experiments/note-route-draft/draft.ts"; then
  echo "FAIL: draft module names the gateway"
  exit 1
fi
call_name="$(printf '%s%s' 'liveGateway' 'Call')"
if grep -q "$call_name" \
  "$ROOT/install/payload/meshd/knowledge.ts" \
  "$ROOT/install/payload/meshd/agent-note.ts" \
  "$ROOT/experiments/note-route-draft/draft.ts" \
  "$0"; then
  echo "FAIL: gateway call is named"
  exit 1
fi

env -u AI_GATEWAY_API_KEY bun -e '
import { modelClassOf as agentClass, completionsEndpoint } from "./install/payload/meshd/agent-note.ts";
import { modelClassOf as draftClass } from "./experiments/note-route-draft/draft.ts";
const allowed = new Set(["local", "user-subscription"]);
const samples = [
  ["http://127.0.0.1:9/v1", "local"],
  ["https://models.example/v1", "user-subscription"],
  ["local", "local"],
  ["user-subscription", "user-subscription"],
  ["ftp://files.example/v1", "user-subscription"],
];
for (const [sample, want] of samples) {
  for (const got of [agentClass(sample), draftClass(sample)]) {
    if (!allowed.has(got)) {
      console.error("FAIL: model class is " + got);
      process.exit(1);
    }
    if (got !== want) {
      console.error("FAIL: " + sample + " class is " + got);
      process.exit(1);
    }
  }
}
if (completionsEndpoint("https://models.example/v1") === null) {
  console.error("FAIL: subscription class has no endpoint shape");
  process.exit(1);
}
if (completionsEndpoint("ftp://files.example/v1") !== null) {
  console.error("FAIL: remote scheme has an endpoint");
  process.exit(1);
}
if (completionsEndpoint("local") !== null || completionsEndpoint("user-subscription") !== null) {
  console.error("FAIL: class label has an endpoint");
  process.exit(1);
}
' || { echo "FAIL: model classification"; exit 1; }
echo "check-spoken-replace-draft: model class is local or user-subscription"

fixture_text() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["text"], end="")' \
    "$ROOT/experiments/jev-routing/fixtures.json" "$1"
}
PAIRING="$(fixture_text sendPairingCode)"
HOSTS="$(fixture_text copyHosts)"
PAPER="$(fixture_text summarizePaper)"
SPOKEN="Draft the spoken replacement"
[ -n "$PAIRING" ] && [ -n "$HOSTS" ] && [ -n "$PAPER" ] && [ -n "$SPOKEN" ] || {
  echo "FAIL: route fixtures are empty"
  exit 1
}
[ "$SPOKEN" != "$PAPER" ] || { echo "FAIL: spoken transcript matches the paper"; exit 1; }

TH="$(mktemp -d)"
ORIG_HOME="$HOME"
HOME_DIR="$TH/home"
STATE="$TH/state"
WORK="$TH/session"
PDF="$TH/spare.pdf"
PDF2="$TH/paper.pdf"
AUDIO="$TH/clip.wav"
LOG="$TH/meshd.log"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
PORT=8898
OLD1="Original body on disk"
OLD2="Earlier paper text stays out"
SRV=
STUB=
MESH_MARK="$ORIG_HOME/.mesh"
had_mesh=0
[ -e "$MESH_MARK" ] && had_mesh=1

case "$PORT" in
  8899) echo "FAIL: refusing port 8899"; exit 1 ;;
esac
[ "$PORT" = "8898" ] || { echo "FAIL: spare daemon must listen on 8898"; exit 1; }

stop_stub() {
  [ -n "${STUB:-}" ] || return 0
  kill "$STUB" 2>/dev/null || true
  n=0
  while kill -0 "$STUB" 2>/dev/null && [ "$n" -lt 20 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -KILL "$STUB" 2>/dev/null || true
  wait "$STUB" 2>/dev/null || true
  STUB=
}

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
  stop_stub
  rm -rf "$TH"
  exit "$ec"
}
trap cleanup EXIT

python3 - "$PORT" <<'PY'
import socket, sys
port = int(sys.argv[1])
sock = socket.socket()
try:
    sock.bind(("127.0.0.1", port))
except OSError:
    sys.exit("FAIL: port %s is already in use" % port)
finally:
    sock.close()
PY

mkdir -p "$HOME_DIR" "$STATE" "$WORK" "$TH/stub-bodies"
chmod 700 "$HOME_DIR" "$STATE" "$WORK" "$TH/stub-bodies"
printf 'RIFF' > "$AUDIO"
: > "$TH/stt-args"
: > "$TH/stt-say"
: > "$TH/tts-out"
: > "$TH/tts-runs"

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
chmod 700 "$TH/stt" "$TH/tts"
printf 'touch %s\n' "$WORK/draft-executed" > "$TH/stub.reply"

make_pdf() {
  title="$1"
  body="$2"
  dest="$3"
  TITLE="$title" BODY="$body" python3 - "$dest" <<'PY'
import os, sys
path = sys.argv[1]
title = os.environ["TITLE"]
body = os.environ["BODY"]
stream = ("BT /F1 12 Tf 72 720 Td (%s) Tj ET\n" % body).encode()
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"endstream",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ("<< /Title (%s) >>" % title).encode(),
]
out = bytearray(b"%PDF-1.4\n")
for i, obj in enumerate(objects, start=1):
    out += f"{i} 0 obj\n".encode() + obj + b"\nendobj\n"
out += b"trailer\n<< /Root 1 0 R /Info 6 0 R >>\n%%EOF\n"
open(path, "wb").write(out)
PY
}
make_pdf "Spare note" "$OLD1" "$PDF"
make_pdf "Paper note" "$OLD2" "$PDF2"

python3 - "$TH/stub.port" "$TH/stub-bodies" "$TH/stub.headers" "$TH/stub.reply" 2>"$TH/stub.err" <<'PY' &
import json, os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file, body_dir, header_file, reply_file = sys.argv[1:5]
reply = open(reply_file, "r", encoding="utf-8").read()

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(n) if n else b""
        names = [name for name in os.listdir(body_dir) if name.endswith(".json")]
        dest = os.path.join(body_dir, "%d.json" % (len(names) + 1))
        with open(dest, "wb") as fh:
            fh.write(raw)
        with open(header_file, "a", encoding="utf-8") as fh:
            fh.write(self.path + "\n")
            fh.write(str(self.headers))
            fh.write("\n")
        host = self.headers.get("Host", "")
        if "supabase.co" in host.lower() or "supabase.co" in self.path.lower():
            raise SystemExit("stub saw supabase.co")
        if self.headers.get("Authorization"):
            raise SystemExit("stub saw an authorization header")
        payload = json.dumps({
            "choices": [{"message": {"role": "assistant", "content": reply}}],
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        return

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
if server.server_address[0] != "127.0.0.1":
    raise SystemExit("stub did not bind 127.0.0.1")
tmp_port = port_file + ".tmp"
with open(tmp_port, "w") as fh:
    fh.write(str(server.server_address[1]))
    fh.write("\n")
os.rename(tmp_port, port_file)
server.serve_forever()
PY
STUB=$!
i=0
while [ ! -s "$TH/stub.port" ] && [ "$i" -lt 300 ]; do
  kill -0 "$STUB" 2>/dev/null || {
    echo "FAIL: model stub exited"
    tail -n 40 "$TH/stub.err" || true
    exit 1
  }
  sleep 0.1
  i=$((i + 1))
done
if [ ! -s "$TH/stub.port" ]; then
  echo "FAIL: model stub port file never appeared"
  tail -n 40 "$TH/stub.err" || true
  exit 1
fi
STUB_PORT="$(tr -d '[:space:]' < "$TH/stub.port")"
if [ -z "$STUB_PORT" ] || [ "$STUB_PORT" = "8899" ] || [ "$STUB_PORT" = "8898" ]; then
  echo "FAIL: model stub port is not a spare localhost port"
  exit 1
fi

lines_of() {
  wc -l < "$1" | tr -d ' '
}

mode_of() {
  m="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1")"
  echo "${m#0}"
}

note_count() {
  found=0
  for f in "$STATE/knowledge"/*.json; do
    [ -f "$f" ] || continue
    found=$((found + 1))
  done
  echo "$found"
}

stub_hits() {
  found=0
  for f in "$TH/stub-bodies"/*.json; do
    [ -f "$f" ] || continue
    found=$((found + 1))
  done
  echo "$found"
}

start_daemon() {
  tts_bin="$1"
  stop_srv
  env -u AI_GATEWAY_API_KEY \
    MESHD_PORT="$PORT" \
    MESHD_HOST=127.0.0.1 \
    MESHD_TOKEN="$TOKEN" \
    MESHD_STATE="$STATE" \
    MESHD_TELEMETRY=off \
    MESH_STT="$TH/stt" \
    MESH_TTS="$tts_bin" \
    MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
    MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
    MESHD_KB_PATH="$TH/kb.sqlite" \
    HOME="$HOME_DIR" \
    bun "$ROOT/install/payload/meshd/server.ts" >"$LOG" 2>&1 &
  SRV=$!
  up=0
  i=0
  while [ "$i" -lt 50 ]; do
    if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      up=1
      break
    fi
    kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited before listening"; sed "s/${TOKEN}/[redacted]/g" "$LOG"; exit 1; }
    sleep 0.1
    i=$((i + 1))
  done
  [ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on $PORT"; sed "s/${TOKEN}/[redacted]/g" "$LOG"; exit 1; }
}

set_transcript() {
  printf '%s\n' "$1" > "$TH/stt-say"
}

post_audio() {
  id="$1"
  out="$2"
  speak="$3"
  audio_path="$4"
  python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1], "speak": sys.argv[2] == "true"}))' \
    "$audio_path" "$speak" > "$TH/payload.json"
  curl --connect-timeout 1 --max-time 10 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/payload.json" \
    "http://127.0.0.1:$PORT/knowledge/${id}" || true
}

post_note() {
  name="$1"
  out="$2"
  curl --connect-timeout 1 --max-time 12 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$name" \
    "http://127.0.0.1:$PORT/agent-note" || true
}

start_daemon "$TH/tts"
echo "check-spoken-replace-draft: spare daemon is on 127.0.0.1:${PORT}"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/post.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "{\"path\":\"${PDF}\"}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; echo; exit 1; }
[ "$(lines_of "$TH/tts-runs")" = "0" ] || { echo "FAIL: creating a note spawned TTS"; exit 1; }
[ "$(stub_hits)" = "0" ] || { echo "FAIL: creating a note called the model"; exit 1; }
ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/post.json")"
NOTE_FILE="$STATE/knowledge/${ID}.json"
[ -f "$NOTE_FILE" ] || { echo "FAIL: created note file is missing"; exit 1; }
OLD1="$OLD1" python3 - "$NOTE_FILE" "$ID" <<'PY'
import json, os, sys
note = json.load(open(sys.argv[1]))
if note.get("id") != sys.argv[2] or note.get("title") != "Spare note":
    raise SystemExit("FAIL: created note is %r" % (note,))
if note.get("body") != os.environ["OLD1"]:
    raise SystemExit("FAIL: created body is %r" % (note.get("body"),))
PY

MISS="$(python3 -c 'import uuid; print(uuid.uuid4())')"
[ "$MISS" != "$ID" ] || { echo "FAIL: missing id collided with the note"; exit 1; }
cp "$NOTE_FILE" "$TH/frozen.json"
before_stt="$(lines_of "$TH/stt-args")"
before_tts="$(lines_of "$TH/tts-runs")"
set_transcript "do not store this transcript"
code="$(post_audio "$MISS" "$TH/miss-id.json" true "$AUDIO")"
[ "$code" = "404" ] || { echo "FAIL: missing id -> ${code}"; cat "$TH/miss-id.json"; echo; exit 1; }
[ ! -e "$STATE/knowledge/${MISS}.json" ] || { echo "FAIL: missing id created a note"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: missing id changed the note count"; exit 1; }
[ "$(lines_of "$TH/stt-args")" = "$before_stt" ] || { echo "FAIL: missing id spawned STT"; exit 1; }
[ "$(lines_of "$TH/tts-runs")" = "$before_tts" ] || { echo "FAIL: missing id spawned TTS"; exit 1; }
[ "$(stub_hits)" = "0" ] || { echo "FAIL: missing id called the model"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: missing id rewrote the note"; exit 1; }

WORK="$WORK" STUB_PORT="$STUB_PORT" python3 - "$TH/missing-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": "00000000-0000-4000-8000-000000000099",
    "cwd": os.environ["WORK"],
    "model": "http://127.0.0.1:%s/v1" % os.environ["STUB_PORT"],
    "file": "held-spoken.txt",
    "command": "touch " + os.environ["WORK"] + "/missing-ran",
    "confirm": True,
}))
PY
code="$(post_note "$TH/missing-req.json" "$TH/missing-agent.json")"
[ "$code" = "404" ] || { echo "FAIL: missing agent id -> ${code}"; cat "$TH/missing-agent.json"; echo; exit 1; }
[ "$(stub_hits)" = "0" ] || { echo "FAIL: missing agent id called the model"; exit 1; }
[ ! -e "$WORK/held-spoken.txt" ] || { echo "FAIL: missing id wrote a file"; exit 1; }
[ ! -e "$WORK/missing-ran" ] || { echo "FAIL: missing id ran a command"; exit 1; }
[ ! -e "$STATE/knowledge/00000000-0000-4000-8000-000000000099.json" ] || {
  echo "FAIL: missing agent id created a note"
  exit 1
}
echo "check-spoken-replace-draft: missing id created nothing and did not call the model"

refuse_audio() {
  label="$1"
  target="$2"
  cp "$NOTE_FILE" "$TH/frozen.json"
  before_stt="$(lines_of "$TH/stt-args")"
  before_tts="$(lines_of "$TH/tts-runs")"
  before_hits="$(stub_hits)"
  code="$(post_audio "$ID" "$TH/rej.json" true "$target")"
  cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: $label wrote the note"; exit 1; }
  [ "$(lines_of "$TH/stt-args")" = "$before_stt" ] || { echo "FAIL: $label spawned STT"; exit 1; }
  [ "$(lines_of "$TH/tts-runs")" = "$before_tts" ] || { echo "FAIL: $label spawned TTS"; exit 1; }
  [ "$(stub_hits)" = "$before_hits" ] || { echo "FAIL: $label called the model"; exit 1; }
  case "$code" in
    200|201) echo "FAIL: $label was stored ($code)"; exit 1 ;;
  esac
  echo "check-spoken-replace-draft: $label"
}
refuse_audio "remote audio did not write" "http://127.0.0.1:9/clip.wav"
refuse_audio "scheme audio did not write" "file://${AUDIO}"
refuse_audio "protocol-relative audio did not write" "//127.0.0.1/clip.wav"

refuse_tts() {
  label="$1"
  tts_value="$2"
  cp "$NOTE_FILE" "$TH/frozen.json"
  before_stt="$(lines_of "$TH/stt-args")"
  before_tts="$(lines_of "$TH/tts-runs")"
  before_hits="$(stub_hits)"
  set_transcript "This transcript must not be stored"
  start_daemon "$tts_value"
  code="$(post_audio "$ID" "$TH/rej-tts.json" true "$AUDIO")"
  cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: $label wrote the note"; exit 1; }
  [ "$(lines_of "$TH/stt-args")" = "$before_stt" ] || { echo "FAIL: $label spawned STT"; exit 1; }
  [ "$(lines_of "$TH/tts-runs")" = "$before_tts" ] || { echo "FAIL: $label spawned TTS"; exit 1; }
  [ "$(stub_hits)" = "$before_hits" ] || { echo "FAIL: $label called the model"; exit 1; }
  case "$code" in
    200|201) echo "FAIL: $label was stored ($code)"; exit 1 ;;
  esac
  echo "check-spoken-replace-draft: $label"
}
refuse_tts "remote TTS did not write" "http://127.0.0.1:9/say"
refuse_tts "scheme TTS did not write" "file://${TH}/tts"
refuse_tts "protocol-relative TTS did not write" "//${TH}/tts"

start_daemon "$TH/tts"
set_transcript "$SPOKEN"
before_stt="$(lines_of "$TH/stt-args")"
before_tts="$(lines_of "$TH/tts-runs")"
code="$(post_audio "$ID" "$TH/spoken.json" true "$AUDIO")"
[ "$code" = "200" ] || { echo "FAIL: POST /knowledge/:id speak -> ${code}"; cat "$TH/spoken.json"; echo; exit 1; }
[ "$(lines_of "$TH/stt-args")" -gt "$before_stt" ] || { echo "FAIL: transcriber was not run"; exit 1; }
[ "$(lines_of "$TH/tts-runs")" -gt "$before_tts" ] || { echo "FAIL: speaker was not run"; exit 1; }
[ "$(stub_hits)" = "0" ] || { echo "FAIL: spoken replace called the model"; exit 1; }
SPOKEN="$SPOKEN" OLD1="$OLD1" python3 - "$TH/spoken.json" "$NOTE_FILE" "$AUDIO" "$TH/stt-args" "$TH/tts-out" <<'PY'
import json, os, sys
resp = json.load(open(sys.argv[1]))
note = json.load(open(sys.argv[2]))
audio = sys.argv[3]
args = open(sys.argv[4]).read().splitlines()
heard = open(sys.argv[5]).read()
want = os.environ["SPOKEN"]
old = os.environ["OLD1"]
if args[-1] != audio:
    raise SystemExit("FAIL: transcriber args are %r" % (args,))
if resp.get("spoken") is not True:
    raise SystemExit("FAIL: spoken is %r" % (resp.get("spoken"),))
if resp.get("body") != want or note.get("body") != want:
    raise SystemExit("FAIL: stored transcript is %r" % (note.get("body"),))
if resp.get("title") != "Spare note" or note.get("title") != "Spare note":
    raise SystemExit("FAIL: title changed")
if old in note.get("body", "") or old in heard:
    raise SystemExit("FAIL: old body survived the spoken replace")
if "Spare note" not in heard or want not in heard:
    raise SystemExit("FAIL: speaker heard %r" % (heard,))
PY
fmode="$(mode_of "$NOTE_FILE")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-spoken-replace-draft: local TTS that exits 0 returns spoken true"
echo "check-spoken-replace-draft: title stayed"
echo "check-spoken-replace-draft: file mode 600"
echo "check-spoken-replace-draft: directory mode 700"

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
if "spoken" in blob or "body" in blob:
    raise SystemExit("FAIL: list leaked more than id and title")
PY
echo "check-spoken-replace-draft: list is id and title"

cp "$NOTE_FILE" "$TH/frozen.json"
NOTE_ID="$ID" WORK="$WORK" STUB_PORT="$STUB_PORT" python3 - "$TH/job-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": os.environ["NOTE_ID"],
    "cwd": os.environ["WORK"],
    "model": "http://127.0.0.1:%s/v1" % os.environ["STUB_PORT"],
    "file": "held-spoken.txt",
    "command": "sh " + os.environ["WORK"] + "/held-spoken.txt",
    "confirm": False,
}))
PY
code="$(post_note "$TH/job-req.json" "$TH/job.json")"
[ "$code" = "200" ] || { echo "FAIL: POST /agent-note -> ${code}"; cat "$TH/job.json"; echo; exit 1; }
SPOKEN="$SPOKEN" OLD1="$OLD1" python3 - "$TH/job.json" "$WORK/held-spoken.txt" "$TH/stub.reply" "$TH/stub-bodies" "$TH/stub.headers" "$WORK" <<'PY'
import json, os, stat, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
allowed = {"local", "user-subscription"}
if data.get("modelClass") not in allowed:
    raise SystemExit("FAIL: modelClass is %r" % (data.get("modelClass"),))
if data.get("modelClass") != "local":
    raise SystemExit("FAIL: localhost model was not class local")
if data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: command was not held")
draft = data.get("draft")
if draft != "held-spoken.txt" or os.path.isabs(draft) or "://" in str(draft) or ".." in str(draft):
    raise SystemExit("FAIL: draft name is %r" % (draft,))
for needle in ("127.0.0.1", "http", "supabase", "chat/completions"):
    if needle in raw:
        raise SystemExit("FAIL: transcript contains %s" % needle)
reply = open(sys.argv[3], "rb").read()
got = open(sys.argv[2], "rb").read()
if got != reply:
    raise SystemExit("FAIL: held file is not the stub reply")
mode = stat.S_IMODE(os.stat(sys.argv[2]).st_mode)
if mode != 0o600:
    raise SystemExit("FAIL: held file mode is %o" % mode)
if mode & 0o111:
    raise SystemExit("FAIL: held file is executable")
bodies = sorted(name for name in os.listdir(sys.argv[4]) if name.endswith(".json"))
if bodies != ["1.json"]:
    raise SystemExit("FAIL: stub files are %r" % (bodies,))
payload = json.load(open(os.path.join(sys.argv[4], "1.json")))
if payload.get("model") not in allowed or payload.get("model") != "local":
    raise SystemExit("FAIL: stub model class is %r" % (payload.get("model"),))
messages = json.dumps(payload.get("messages"))
spoken = os.environ["SPOKEN"]
old = os.environ["OLD1"]
if spoken not in messages:
    raise SystemExit("FAIL: stub did not receive the spoken transcript")
if old in messages:
    raise SystemExit("FAIL: stub received the old body")
headers = open(sys.argv[5]).read().lower()
if "supabase.co" in headers or "authorization" in headers or "bearer" in headers:
    raise SystemExit("FAIL: stub saw supabase.co or an authorization header")
if "/v1/chat/completions" not in headers:
    raise SystemExit("FAIL: stub path is not the completions endpoint")
names = sorted(os.listdir(sys.argv[6]))
if names != ["held-spoken.txt"]:
    raise SystemExit("FAIL: session files are %r" % (names,))
if os.path.exists(os.path.join(sys.argv[6], "draft-executed")):
    raise SystemExit("FAIL: held file was executed")
PY
[ ! -e "$WORK/draft-executed" ] || { echo "FAIL: unconfirmed command ran"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: draft rewrote the note"; exit 1; }
echo "check-spoken-replace-draft: agent drafted the spoken transcript"
echo "check-spoken-replace-draft: held file is one relative path mode 600"
echo "check-spoken-replace-draft: held file was not executed"
echo "check-spoken-replace-draft: command without confirm did not run"

hold_replace() {
  label="$1"
  text="$2"
  copy="$3"
  before_hits="$(stub_hits)"
  set_transcript "$text"
  code="$(post_audio "$ID" "$TH/hold-res.json" true "$AUDIO")"
  [ "$code" = "200" ] || { echo "FAIL: $label replace -> ${code}"; cat "$TH/hold-res.json"; echo; exit 1; }
  [ "$(stub_hits)" = "$before_hits" ] || { echo "FAIL: $label replace called the model"; exit 1; }
  [ "$(note_count)" = "1" ] || { echo "FAIL: $label replace created a note"; exit 1; }
  TEXT="$text" python3 - "$NOTE_FILE" "$ID" "$TH/hold-res.json" <<'PY'
import json, os, sys
note = json.load(open(sys.argv[1]))
resp = json.load(open(sys.argv[3]))
want = os.environ["TEXT"]
if note.get("id") != sys.argv[2] or note.get("title") != "Spare note":
    raise SystemExit("FAIL: held replace changed the note identity")
if note.get("body") != want or resp.get("body") != want:
    raise SystemExit("FAIL: held transcript was not stored")
if resp.get("spoken") is not True:
    raise SystemExit("FAIL: held replace spoken is %r" % (resp.get("spoken"),))
PY
  cp "$NOTE_FILE" "$copy"
  echo "check-spoken-replace-draft: $label transcript replaced the same note"
}
hold_replace "pairing code" "$PAIRING" "$TH/pairing.json"
hold_replace "hosts.json" "$HOSTS" "$TH/hosts.json"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/paper-post.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "{\"path\":\"${PDF2}\"}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: second POST /knowledge -> ${code}"; cat "$TH/paper-post.json"; echo; exit 1; }
ID2="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/paper-post.json")"
[ "$ID2" != "$ID" ] || { echo "FAIL: second note reused the first id"; exit 1; }
NOTE2="$STATE/knowledge/${ID2}.json"
[ -f "$NOTE2" ] || { echo "FAIL: second note file is missing"; exit 1; }
before_hits="$(stub_hits)"
set_transcript "$PAPER"
code="$(post_audio "$ID2" "$TH/paper-res.json" true "$AUDIO")"
[ "$code" = "200" ] || { echo "FAIL: paper replace -> ${code}"; cat "$TH/paper-res.json"; echo; exit 1; }
[ "$(stub_hits)" = "$before_hits" ] || { echo "FAIL: paper replace called the model before the draft"; exit 1; }
[ "$(note_count)" = "2" ] || { echo "FAIL: paper replace changed the note count"; exit 1; }
PAPER="$PAPER" OLD2="$OLD2" python3 - "$NOTE2" "$ID2" "$TH/paper-res.json" <<'PY'
import json, os, sys
note = json.load(open(sys.argv[1]))
resp = json.load(open(sys.argv[3]))
if note.get("id") != sys.argv[2] or note.get("title") != "Paper note":
    raise SystemExit("FAIL: paper replace changed the title")
if note.get("body") != os.environ["PAPER"] or resp.get("body") != os.environ["PAPER"]:
    raise SystemExit("FAIL: paper body was not stored")
if os.environ["OLD2"] in note.get("body", ""):
    raise SystemExit("FAIL: paper body still contains the old text")
if resp.get("spoken") is not True:
    raise SystemExit("FAIL: paper spoken is %r" % (resp.get("spoken"),))
PY
cp "$NOTE2" "$TH/paper.json"
echo "check-spoken-replace-draft: second note replaced with the paper summary"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list2.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge after paper -> ${code}"; exit 1; }
python3 - "$TH/list2.json" "$ID" "$ID2" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
notes = data.get("notes")
if not isinstance(notes, list) or len(notes) != 2:
    raise SystemExit("FAIL: list after paper is %r" % (notes,))
want = {sys.argv[2]: "Spare note", sys.argv[3]: "Paper note"}
got = {}
for note in notes:
    if set(note.keys()) != {"id", "title"}:
        raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
    got[note.get("id")] = note.get("title")
if got != want:
    raise SystemExit("FAIL: list notes are %r" % (got,))
PY
if grep -q "$PAPER" "$TH/list2.json" || grep -q "$HOSTS" "$TH/list2.json" || grep -q "$PAIRING" "$TH/list2.json"; then
  echo "FAIL: GET /knowledge returned a replaced body"
  exit 1
fi

cat > "$TH/prove.ts" <<'TS'
import { existsSync, readFileSync, statSync } from "node:fs";
import { readdir } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const root = process.argv[2];
const pairingPath = process.argv[3];
const hostsPath = process.argv[4];
const paperPath = process.argv[5];
const work = process.argv[6];
const old1 = process.argv[7];
const old2 = process.argv[8];
const endpoint = process.argv[9];
const bodyDir = process.argv[10];
const replyPath = process.argv[11];

function fail(message: string): never {
  console.error("FAIL: " + message);
  process.exit(1);
}

if (process.env.AI_GATEWAY_API_KEY) fail("gateway key is set");

const draftMod = await import(pathToFileURL(join(root, "experiments/note-route-draft/draft.ts")).href);
const routeMod = await import(pathToFileURL(join(root, "experiments/jev-routing/route.ts")).href);
const filterMod = await import(pathToFileURL(join(root, "experiments/jev-routing/filter.ts")).href);
const { draftNote, modelClassOf } = draftMod;
const { route } = routeMod;
const { filter } = filterMod;

const allow = {
  surface: "terminal-text",
  choice: "allow-local-tool",
  score: 0.2,
  boolean: true,
  confidence: 0.6,
};

function noteOf(path: string): Record<string, unknown> {
  const note = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
  if (typeof note.body !== "string" || typeof note.id !== "string") fail("stored note has no body");
  return note;
}

const allowedClass = new Set(["local", "user-subscription"]);
function assertClass(value: string, label: string): void {
  if (!allowedClass.has(value)) fail(label + " model class is " + value);
}

const gotClass = modelClassOf(endpoint);
assertClass(gotClass, "loopback");
if (gotClass !== "local") fail("loopback model was not class local");

const realFetch = globalThis.fetch;
let fetches = 0;
globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = input instanceof Request ? input.url : String(input);
  let host = "";
  try {
    host = new URL(url).hostname;
  } catch {
    host = "";
  }
  if (host !== "127.0.0.1") fail("fetch left 127.0.0.1");
  fetches += 1;
  return realFetch(input, init);
};

async function hits(): Promise<number> {
  const names = (await readdir(bodyDir)).filter((name) => name.endsWith(".json"));
  return names.length;
}

const marker = join(work, "draft-executed");
const reply = readFileSync(replyPath, "utf8");
const secretFile = "held-secret.txt";
const paperFile = "held-paper.txt";

function runIfConfirmed(command: string, confirm: boolean): void {
  if (confirm === true) fail("unconfirmed path tried to run: " + command);
}

const before = await hits();
try {
  async function held(label: string, state: Record<string, unknown>): Promise<void> {
    const beforeHits = await hits();
    const beforeFetch = fetches;
    const decision = route(filter(state), allow);
    if (decision !== "hold-for-review") fail(label + " route allowed");
    const result = await draftNote({
      state,
      evaluation: allow,
      endpoint,
      model: endpoint,
      cwd: work,
      file: secretFile,
    });
    if (result.decision !== "hold-for-review") fail(label + " was drafted");
    assertClass(result.modelClass, label);
    if (result.modelClass !== "local") fail(label + " was not class local");
    if (result.drafted || result.file !== null) fail(label + " wrote a draft");
    if ((await hits()) !== beforeHits || fetches !== beforeFetch) fail(label + " called the model");
    if (existsSync(join(work, secretFile)) || existsSync(marker)) fail(label + " created a file");
    runIfConfirmed(reply, false);
    if (existsSync(marker)) fail(label + " ran a command");
    console.log("check-spoken-replace-draft: " + label + " stayed on hold and the model was not called");
  }

  const pairing = noteOf(pairingPath);
  if (String(pairing.body).includes(old1)) fail("stored pairing body still has the old text");
  await held("pairing code", pairing);

  const hosts = noteOf(hostsPath);
  if (String(hosts.body).includes(old1)) fail("stored hosts body still has the old text");
  await held("hosts.json", hosts);

  const paper = noteOf(paperPath);
  if (paper.body !== "summarize this paper") fail("stored paper body is not the new summary");
  if (String(paper.body).includes(old1) || String(paper.body).includes(old2)) {
    fail("stored paper body still has an old text");
  }
  if (route(filter(paper), allow) !== "allow-local-tool") fail("replaced paper was held");
  const drafted = await draftNote({
    state: paper,
    evaluation: allow,
    endpoint,
    model: endpoint,
    cwd: work,
    file: paperFile,
  });
  if (drafted.decision !== "allow-local-tool" || !drafted.drafted || drafted.file !== paperFile) {
    fail("clean paper was not drafted");
  }
  assertClass(drafted.modelClass, "paper");
  if (drafted.modelClass !== "local") fail("paper model was not class local");
  if ((await hits()) !== before + 1 || fetches !== 1) fail("clean paper did not call the model once");
  const names = (await readdir(bodyDir)).filter((name) => name.endsWith(".json")).sort();
  const last = JSON.parse(readFileSync(join(bodyDir, names[names.length - 1]), "utf8")) as {
    model?: string;
    messages?: { content?: string }[];
  };
  if (!allowedClass.has(String(last.model)) || last.model !== "local") {
    fail("stub model class is " + String(last.model));
  }
  const messages = JSON.stringify(last.messages ?? []);
  if (!messages.includes("summarize this paper")) fail("stub did not receive the new paper body");
  if (messages.includes(old1) || messages.includes(old2)) fail("stub received an old body");
  const draftPath = join(work, paperFile);
  const info = statSync(draftPath);
  if (!info.isFile() || (info.mode & 0o777) !== 0o600) fail("draft mode is " + (info.mode & 0o777).toString(8));
  if (info.mode & 0o111) fail("draft file is executable");
  if (readFileSync(draftPath, "utf8") !== reply) fail("draft file is not the assistant text");
  runIfConfirmed(reply, false);
  if (existsSync(marker)) fail("unconfirmed command ran");
  const dumped = JSON.stringify(drafted);
  if (dumped.includes(endpoint) || dumped.includes("ai-gateway")) fail("draft result recorded an endpoint");
  console.log("check-spoken-replace-draft: second note drafted the new paper body");
} finally {
  globalThis.fetch = realFetch;
}
TS

env -u AI_GATEWAY_API_KEY \
  node --experimental-strip-types "$TH/prove.ts" \
  "$ROOT" "$TH/pairing.json" "$TH/hosts.json" "$TH/paper.json" "$WORK" \
  "$OLD1" "$OLD2" "http://127.0.0.1:${STUB_PORT}/v1/chat/completions" \
  "$TH/stub-bodies" "$TH/stub.reply"

[ ! -e "$WORK/draft-executed" ] || { echo "FAIL: unconfirmed command ran"; exit 1; }
[ ! -e "$WORK/held-secret.txt" ] || { echo "FAIL: a held transcript wrote a file"; exit 1; }
[ -f "$WORK/held-spoken.txt" ] || { echo "FAIL: spoken draft file is missing"; exit 1; }
[ -f "$WORK/held-paper.txt" ] || { echo "FAIL: paper draft file is missing"; exit 1; }
spoken_mode="$(mode_of "$WORK/held-spoken.txt")"
paper_mode="$(mode_of "$WORK/held-paper.txt")"
[ "$spoken_mode" = "600" ] || { echo "FAIL: spoken held file mode is $spoken_mode, want 600"; exit 1; }
[ "$paper_mode" = "600" ] || { echo "FAIL: paper held file mode is $paper_mode, want 600"; exit 1; }
[ "$(note_count)" = "2" ] || { echo "FAIL: draft changed the note count"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/hosts.json" || { echo "FAIL: draft rewrote the hosts note"; exit 1; }
cmp -s "$NOTE2" "$TH/paper.json" || { echo "FAIL: draft rewrote the paper note"; exit 1; }
fmode="$(mode_of "$NOTE_FILE")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
fmode="$(mode_of "$NOTE2")"
[ "$fmode" = "600" ] || { echo "FAIL: paper note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
[ ! -d "$HOME_DIR/.mesh" ] || { echo "FAIL: daemon wrote under its home directory"; exit 1; }
if [ "$had_mesh" -eq 0 ] && [ -e "$MESH_MARK" ]; then
  echo "FAIL: wrote ~/.mesh"
  exit 1
fi
[ "$(stub_hits)" = "2" ] || { echo "FAIL: model was called ${stub_hits} times"; exit 1; }

if grep -E -q 'supabase\.co|ai-gateway' "$LOG"; then
  echo "FAIL: daemon log records supabase.co or the AI gateway"
  exit 1
fi

if [ "$(uname -s)" = "Darwin" ]; then
  command -v lsof >/dev/null 2>&1 || { echo "FAIL: lsof is required on Darwin"; exit 1; }
  SRV_PID="$SRV" HOME_DIR="$HOME_DIR" STATE="$STATE" python3 - <<'PY'
import os, re, subprocess, sys
root = int(os.environ["SRV_PID"])

def run(args):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)

listed = run(["ps", "-ax", "-o", "pid=,ppid="])
if listed.returncode != 0 or not listed.stdout.strip():
    sys.exit("FAIL: could not list processes to check sockets")
by_ppid = {}
for line in listed.stdout.splitlines():
    parts = line.split()
    if len(parts) != 2:
        continue
    pid, ppid = int(parts[0]), int(parts[1])
    by_ppid.setdefault(ppid, []).append(pid)
pids, seen, stack = [], set(), [root]
while stack:
    cur = stack.pop()
    if cur in seen:
        continue
    seen.add(cur)
    pids.append(cur)
    stack.extend(by_ppid.get(cur, []))

env_text = run(["ps", "-wwE", "-p", str(root), "-o", "command="]).stdout
need = [
    "MESHD_TELEMETRY=off",
    "MESHD_HOST=127.0.0.1",
    "MESHD_PORT=8898",
    "HOME=" + os.environ["HOME_DIR"],
    "MESHD_STATE=" + os.environ["STATE"],
]
for item in need:
    if item not in env_text.split():
        sys.exit("FAIL: daemon env is missing " + item.split("=", 1)[0])

lsof = run(["lsof", "-nP", "-a", "-p", ",".join(str(p) for p in pids), "-iTCP"])
rows = []
for line in lsof.stdout.splitlines():
    match = re.search(r"\bTCP\s+(\S+)(?:\s+\(([^)]+)\))?\s*$", line)
    if match:
        rows.append(match.group(1))
if not rows:
    sys.exit("FAIL: could not see the daemon's TCP sockets")

def loopback(host):
    h = host.strip("[]").lower()
    if h.startswith("::ffff:"):
        h = h.split("::ffff:", 1)[1]
    return h in ("127.0.0.1", "::1", "localhost")

def remote_host(name):
    if "->" not in name:
        return None
    remote = name.split("->", 1)[1]
    if remote.startswith("["):
        end = remote.find("]")
        return remote[1:end] if end >= 0 else remote
    return remote.rsplit(":", 1)[0]

bad = []
for name in rows:
    host = remote_host(name)
    if host is None or loopback(host):
        continue
    bad.append(name)
if bad:
    sys.exit("FAIL: daemon has a non-loopback socket: %s" % ", ".join(bad))
PY
else
  SRV_PID="$SRV" HOME_DIR="$HOME_DIR" STATE="$STATE" python3 - <<'PY'
import os, sys
root = int(os.environ["SRV_PID"])

def descendants(pid):
    by_ppid = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            data = open(f"/proc/{name}/stat", "rb").read().decode(errors="replace")
        except OSError:
            continue
        r = data.rfind(")")
        parts = data[r + 2:].split()
        if len(parts) < 2:
            continue
        by_ppid.setdefault(int(parts[1]), []).append(int(name))
    out, stack = [], [pid]
    while stack:
        cur = stack.pop()
        out.append(cur)
        stack.extend(by_ppid.get(cur, []))
    return out

def inodes(pid):
    found = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fd_dir)
    except OSError:
        return found
    for name in names:
        try:
            target = os.readlink(f"{fd_dir}/{name}")
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            found.add(target[len("socket:["):-1])
    return found

def loopback(ip):
    if ip in ("00000000", "0100007F", "00000000000000000000000001000000"):
        return True
    if ip.endswith("0100007F") and "FFFF" in ip:
        return True
    return False

socks = set()
for pid in descendants(root):
    socks |= inodes(pid)

bad = []
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        parts = line.split()
        if len(parts) < 10 or parts[9] not in socks:
            continue
        remote_ip = parts[2].split(":")[0]
        if loopback(remote_ip):
            continue
        bad.append(parts[2])

env = {}
try:
    raw = open(f"/proc/{root}/environ", "rb").read().split(b"\0")
except OSError:
    raw = []
for item in raw:
    if b"=" not in item:
        continue
    key, value = item.split(b"=", 1)
    env[key.decode()] = value.decode()
need = {
    "MESHD_TELEMETRY": "off",
    "MESHD_HOST": "127.0.0.1",
    "MESHD_PORT": "8898",
    "HOME": os.environ["HOME_DIR"],
    "MESHD_STATE": os.environ["STATE"],
}
for key, value in need.items():
    if env.get(key) != value:
        sys.exit("FAIL: daemon env %s is not the spare value" % key)
if bad:
    sys.exit("FAIL: daemon has a non-loopback socket: %s" % ", ".join(bad))
PY
fi

echo "check-spoken-replace-draft: OK"

#!/bin/sh
# A local MESH_STT transcript replaces one knowledge note, and that new body
# is what the agent drafts. A replaced transcript that asks to send a pairing
# code, or to copy hosts.json, stays on hold and the loopback model is not
# called. "summarize this paper" still drafts. A missing id, a remote URL, a
# scheme, and a protocol-relative audio path do not write and do not call the
# model. An unconfirmed command does not run. The model class is only local
# or user-subscription.
#
# Spare daemon: 127.0.0.1:8898. This script does not use port 8899, does not
# read a real home directory, does not call a live gateway, and does not
# prove a microphone.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
unset AI_GATEWAY_API_KEY
if [ -n "${AI_GATEWAY_API_KEY:-}" ]; then
  echo "FAIL: AI_GATEWAY_API_KEY is set"
  exit 1
fi
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

# The forbidden name is assembled so this file can refuse itself. A copy of
# that name anywhere in this check, or in the note path, fails the run.
gateway_name() {
  printf '%s%s' 'liveGateway' 'Call'
}
if grep -q "$(gateway_name)" \
  "$0" \
  "$ROOT/install/payload/meshd/knowledge.ts" \
  "$ROOT/install/payload/meshd/agent-note.ts" \
  "$ROOT/experiments/note-route-draft/draft.ts"; then
  echo "FAIL: spoken-note draft path names a live gateway call"
  exit 1
fi
if grep -E -n 'supabase|ai-gateway' \
  "$ROOT/install/payload/meshd/agent-note.ts" \
  "$ROOT/install/payload/meshd/knowledge.ts" \
  "$ROOT/experiments/note-route-draft/draft.ts"; then
  echo "FAIL: note path names supabase or the AI gateway"
  exit 1
fi
grep -q 'MESH_STT' "$ROOT/install/payload/meshd/knowledge.ts" || {
  echo "FAIL: knowledge.ts does not name MESH_STT"
  exit 1
}
grep -q 'handleKnowledge' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route knowledge"
  exit 1
}
calls="$(grep -c 'handleKnowledge(' "$ROOT/install/payload/meshd/server.ts" || true)"
[ "$calls" = "1" ] || { echo "FAIL: expected one knowledge route, found $calls"; exit 1; }
grep -q 'handleAgentNote' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route agent-note"
  exit 1
}
grep -q 'readNote' "$ROOT/install/payload/meshd/agent-note.ts" || {
  echo "FAIL: agent-note does not read the note"
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

# Classify in process. This does not open a socket.
env -u AI_GATEWAY_API_KEY bun -e '
import { modelClassOf, completionsEndpoint } from "./install/payload/meshd/agent-note.ts";
const allowed = new Set(["local", "user-subscription"]);
const samples = [
  ["http://127.0.0.1:9/v1", "local"],
  ["https://models.example/v1", "user-subscription"],
  ["local", "local"],
  ["user-subscription", "user-subscription"],
  ["ftp://files.example/v1", "user-subscription"],
];
for (const [sample, want] of samples) {
  const got = modelClassOf(sample);
  if (!allowed.has(got)) {
    console.error("FAIL: model class is " + got);
    process.exit(1);
  }
  if (got !== want) {
    console.error("FAIL: " + sample + " class is " + got);
    process.exit(1);
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
echo "check-spoken-note-draft: model class is local or user-subscription"

PAPER="$(python3 -c 'import json; print(json.load(open("experiments/jev-routing/fixtures.json"))["summarizePaper"]["text"], end="")')"
PAIRING="$(python3 -c 'import json; print(json.load(open("experiments/jev-routing/fixtures.json"))["sendPairingCode"]["text"], end="")')"
HOSTS="$(python3 -c 'import json; print(json.load(open("experiments/jev-routing/fixtures.json"))["copyHosts"]["text"], end="")')"
[ "$PAPER" = "summarize this paper" ] || { echo "FAIL: paper fixture is not the spoken summary"; exit 1; }
[ "$PAIRING" = "send the pairing code" ] || { echo "FAIL: pairing fixture changed"; exit 1; }
[ -n "$HOSTS" ] || { echo "FAIL: hosts fixture is empty"; exit 1; }

TH="$(mktemp -d)"
HOME_DIR="$TH/home"
STATE="$TH/state"
WORK="$TH/session"
PAPER_WORK="$TH/paper-session"
AUDIO="$TH/clip.wav"
PDF="$TH/spare.pdf"
LOG="$TH/meshd.log"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
PORT=8898
OLD='Original body on disk'
SRV=
STUB=
MESH_MARK="$HOME/.mesh"
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

mkdir -p "$HOME_DIR" "$STATE" "$WORK" "$PAPER_WORK" "$TH/fakebin"
chmod 700 "$HOME_DIR" "$STATE" "$WORK" "$PAPER_WORK"
printf 'RIFF' > "$AUDIO"
: > "$TH/stt-args"
: > "$TH/stt-queue"

cat > "$TH/stt" <<EOF
#!/bin/sh
set -eu
printf '%s\n' "\$1" >> "$TH/stt-args"
line=\$(head -n 1 "$TH/stt-queue")
tail -n +2 "$TH/stt-queue" > "$TH/stt-queue.next"
mv "$TH/stt-queue.next" "$TH/stt-queue"
printf '%s\n' "\$line"
exit 0
EOF
cat > "$TH/fakebin/curl" <<EOF
#!/bin/sh
printf '%s\n' curl >> "$TH/curl-ran"
exit 0
EOF
cat > "$TH/fakebin/wget" <<EOF
#!/bin/sh
printf '%s\n' wget >> "$TH/wget-ran"
exit 0
EOF
chmod 700 "$TH/stt" "$TH/fakebin/curl" "$TH/fakebin/wget"

OLD="$OLD" python3 - "$PDF" <<'PY'
import os, sys
path = sys.argv[1]
old = os.environ["OLD"]
stream = ("BT /F1 12 Tf 72 720 Td (%s) Tj ET\n" % old).encode()
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

python3 - "$TH/stub.port" "$TH/stub.body" "$TH/stub.path" "$TH/stub.headers" "$TH/stub.reply" "$WORK" 2>"$TH/stub.err" <<'PY' &
import json, os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file, body_file, path_file, header_file, reply_file, work = sys.argv[1:7]
reply = "touch " + work + "/draft-executed\n"
with open(reply_file, "w") as fh:
    fh.write(reply)

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(n) if n else b""
        with open(body_file, "ab") as fh:
            fh.write(raw + b"\n")
        with open(path_file, "a") as fh:
            fh.write(self.path + "\n")
        host = self.headers.get("Host", "")
        with open(header_file, "a") as fh:
            fh.write(str(self.headers))
            fh.write("\n")
        if "supabase.co" in host.lower() or "supabase.co" in self.path.lower():
            raise SystemExit("stub saw supabase.co")
        if "ai-gateway" in host.lower() or "ai-gateway" in self.path.lower():
            raise SystemExit("stub saw the AI gateway")
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
echo "check-spoken-note-draft: model stub is on 127.0.0.1:${STUB_PORT}"

env -u AI_GATEWAY_API_KEY \
  PATH="$TH/fakebin:$PATH" \
  MESHD_PORT="$PORT" \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$STATE" \
  MESHD_TELEMETRY=off \
  MESH_STT="$TH/stt" \
  MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
  MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
  MESHD_KB_PATH="$TH/kb.sqlite" \
  HOME="$HOME_DIR" \
  bun install/payload/meshd/server.ts >"$LOG" 2>&1 &
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
echo "check-spoken-note-draft: spare daemon is on 127.0.0.1:${PORT}"

note_count() {
  found=0
  for f in "$STATE/knowledge"/*.json; do
    [ -f "$f" ] || continue
    found=$((found + 1))
  done
  echo "$found"
}

mode_of() {
  python3 -c 'import os, stat, sys; print(format(stat.S_IMODE(os.stat(sys.argv[1]).st_mode), "o"))' "$1"
}

stt_lines() {
  wc -l < "$TH/stt-args" | tr -d ' '
}

stub_posts() {
  if [ ! -f "$TH/stub.body" ]; then
    echo 0
    return
  fi
  python3 -c 'import sys
raw = open(sys.argv[1], "rb").read().splitlines()
print(sum(1 for line in raw if line))' "$TH/stub.body"
}

queue_transcript() {
  python3 -c 'import sys; open(sys.argv[1], "a").write(sys.argv[2] + "\n")' "$TH/stt-queue" "$1"
}

post_audio() {
  out="$1"
  curl --connect-timeout 1 --max-time 8 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data "$AUDIO_JSON" \
    "http://127.0.0.1:$PORT/knowledge/${2}" || true
}

AUDIO_JSON="$(python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1]}))' "$AUDIO")"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/post.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "{\"path\":\"${PDF}\"}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; echo; cat "$LOG"; exit 1; }
ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/post.json")"
NOTE_FILE="$STATE/knowledge/${ID}.json"
[ -f "$NOTE_FILE" ] || { echo "FAIL: created note file is missing"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: expected one note after create, found $(note_count)"; exit 1; }
[ "$(stt_lines)" = "0" ] || { echo "FAIL: creating a pdf note ran the transcriber"; exit 1; }
[ "$(stub_posts)" = "0" ] || { echo "FAIL: creating a note called the model"; exit 1; }
OLD="$OLD" python3 - "$NOTE_FILE" "$ID" <<'PY'
import json, os, sys
note = json.load(open(sys.argv[1]))
old = os.environ["OLD"]
if note.get("id") != sys.argv[2]:
    raise SystemExit("FAIL: created id is %r" % (note.get("id"),))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: created title is %r" % (note.get("title"),))
if note.get("body") != old:
    raise SystemExit("FAIL: created body is %r" % (note.get("body"),))
PY

queue_transcript "$PAPER"
before="$(stt_lines)"
code="$(post_audio "$TH/replaced.json" "$ID")"
[ "$code" = "200" ] || { echo "FAIL: POST /knowledge/:id audio -> ${code}"; cat "$TH/replaced.json"; echo; cat "$LOG"; exit 1; }
[ "$(stt_lines)" -eq $((before + 1)) ] || { echo "FAIL: transcriber did not run once"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: speech replace created a note, found $(note_count)"; exit 1; }
[ "$(stub_posts)" = "0" ] || { echo "FAIL: speech replace called the model"; exit 1; }
PAPER="$PAPER" OLD="$OLD" python3 - "$TH/replaced.json" "$NOTE_FILE" "$ID" "$AUDIO" "$TH/stt-args" <<'PY'
import json, os, sys
resp = json.load(open(sys.argv[1]))
note = json.load(open(sys.argv[2]))
want = os.environ["PAPER"]
old = os.environ["OLD"]
if resp.get("id") != sys.argv[3] or note.get("id") != sys.argv[3]:
    raise SystemExit("FAIL: speech replace changed the id")
if resp.get("title") != "Spare note" or note.get("title") != "Spare note":
    raise SystemExit("FAIL: speech replace changed the title to %r" % (note.get("title"),))
if resp.get("body") != want or note.get("body") != want:
    raise SystemExit("FAIL: stored transcript is %r" % (note.get("body"),))
if old in note.get("body", "") or old in resp.get("body", ""):
    raise SystemExit("FAIL: transcript still contains the old body")
args = open(sys.argv[5]).read().splitlines()
if args != [sys.argv[4]]:
    raise SystemExit("FAIL: transcriber args are %r" % (args,))
PY
fmode="$(mode_of "$NOTE_FILE")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-spoken-note-draft: local transcript replaced one note"
echo "check-spoken-note-draft: title stayed"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; cat "$TH/list.json"; echo; exit 1; }
PAPER="$PAPER" OLD="$OLD" python3 - "$TH/list.json" "$ID" <<'PY'
import json, os, sys
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
if os.environ["PAPER"] in blob or os.environ["OLD"] in blob:
    raise SystemExit("FAIL: list returned a note body")
PY
echo "check-spoken-note-draft: list is id and title"
cp "$NOTE_FILE" "$TH/speech.json"

quiet_side() {
  label="$1"
  if [ "$(stub_posts)" != "0" ]; then
    echo "FAIL: $label called the model"
    exit 1
  fi
  if [ -e "$TH/curl-ran" ] || [ -e "$TH/wget-ran" ]; then
    echo "FAIL: $label spawned a downloader"
    exit 1
  fi
  [ ! -e "$WORK/held-note.txt" ] || { echo "FAIL: $label wrote a file"; exit 1; }
  [ ! -e "$WORK/draft-executed" ] || { echo "FAIL: $label executed a draft"; exit 1; }
}

MISS="$(python3 -c 'import uuid; print(uuid.uuid4())')"
[ "$MISS" != "$ID" ] || { echo "FAIL: missing id collided with the note"; exit 1; }
before="$(stt_lines)"
code="$(post_audio "$TH/miss-id.json" "$MISS")"
[ "$code" = "404" ] || { echo "FAIL: missing id -> ${code}"; cat "$TH/miss-id.json"; echo; exit 1; }
[ ! -e "$STATE/knowledge/${MISS}.json" ] || { echo "FAIL: missing id created a note"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: missing id changed the note count to $(note_count)"; exit 1; }
[ "$(stt_lines)" = "$before" ] || { echo "FAIL: missing id spawned the transcriber"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/speech.json" || { echo "FAIL: missing id rewrote the note"; exit 1; }
quiet_side "missing id"
echo "check-spoken-note-draft: missing id created nothing"

WORK="$WORK" STUB_PORT="$STUB_PORT" python3 - "$TH/missing-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": "00000000-0000-4000-8000-000000000099",
    "cwd": os.environ["WORK"],
    "model": "http://127.0.0.1:%s/v1" % os.environ["STUB_PORT"],
    "file": "held-note.txt",
    "command": "touch " + os.environ["WORK"] + "/missing-ran",
    "confirm": True,
}))
PY
code="$(curl --connect-timeout 1 --max-time 12 -sS -o "$TH/missing.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/missing-req.json" \
  "http://127.0.0.1:$PORT/agent-note" || true)"
[ "$code" = "404" ] || { echo "FAIL: missing note -> ${code}"; cat "$TH/missing.json"; echo; exit 1; }
python3 - "$TH/missing.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("error") != "note not found":
    raise SystemExit("FAIL: missing note error is %r" % (data.get("error"),))
PY
[ ! -e "$WORK/missing-ran" ] || { echo "FAIL: missing id ran a command"; exit 1; }
[ ! -e "$WORK/held-note.txt" ] || { echo "FAIL: missing id wrote a file"; exit 1; }
quiet_side "missing agent note"
cmp -s "$NOTE_FILE" "$TH/speech.json" || { echo "FAIL: missing agent note rewrote the note"; exit 1; }
echo "check-spoken-note-draft: missing id did not call the model"

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
  cmp -s "$NOTE_FILE" "$TH/speech.json" || { echo "FAIL: $label wrote the note"; exit 1; }
  [ "$(stt_lines)" = "$before" ] || { echo "FAIL: $label spawned the transcriber"; exit 1; }
  [ "$(note_count)" = "1" ] || { echo "FAIL: $label created another note"; exit 1; }
  case "$code" in
    200|201) echo "FAIL: $label was stored ($code)"; exit 1 ;;
  esac
  [ "$code" = "400" ] || { echo "FAIL: $label -> ${code}"; cat "$TH/rej.json"; echo; exit 1; }
  quiet_side "$label"
  echo "check-spoken-note-draft: $label"
}
refuse_audio "remote audio did not write" "http://127.0.0.1:9/clip.wav"
refuse_audio "scheme audio did not write" "file://${AUDIO}"
refuse_audio "protocol-relative audio did not write" "//127.0.0.1/clip.wav"

post_note() {
  curl --connect-timeout 1 --max-time 12 -sS -o "$2" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$1" \
    "http://127.0.0.1:$PORT/agent-note" || true
}

NOTE_ID="$ID" WORK="$WORK" STUB_PORT="$STUB_PORT" python3 - "$TH/job-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": os.environ["NOTE_ID"],
    "cwd": os.environ["WORK"],
    "model": "http://127.0.0.1:%s/v1" % os.environ["STUB_PORT"],
    "file": "held-note.txt",
    "command": "sh " + os.environ["WORK"] + "/held-note.txt",
    "confirm": False,
}))
PY
code="$(post_note "$TH/job-req.json" "$TH/job.json")"
[ "$code" = "200" ] || { echo "FAIL: POST /agent-note -> ${code}"; cat "$TH/job.json"; echo; cat "$LOG"; exit 1; }
PAPER="$PAPER" OLD="$OLD" python3 - "$TH/job.json" "$WORK/held-note.txt" "$TH/stub.reply" "$TH/stub.body" "$TH/stub.path" "$TH/stub.headers" "$WORK" <<'PY'
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
if draft != "held-note.txt" or os.path.isabs(draft) or "://" in str(draft) or ".." in str(draft):
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
bodies = [ln for ln in open(sys.argv[4], "rb").read().splitlines() if ln]
if len(bodies) != 1:
    raise SystemExit("FAIL: stub request count is %d" % len(bodies))
payload = json.loads(bodies[0])
if payload.get("model") not in allowed:
    raise SystemExit("FAIL: stub saw a model name that is not a class")
if payload.get("model") != "local":
    raise SystemExit("FAIL: stub model class is %r" % (payload.get("model"),))
messages = json.dumps(payload.get("messages"))
paper = os.environ["PAPER"]
old = os.environ["OLD"]
if paper not in messages:
    raise SystemExit("FAIL: stub did not receive the new transcript")
if old in messages:
    raise SystemExit("FAIL: stub received the old body")
for needle in ("supabase", "http", "127.0.0.1"):
    if needle in messages:
        raise SystemExit("FAIL: stub body contains %s" % needle)
paths = [ln.strip() for ln in open(sys.argv[5]).read().splitlines() if ln.strip()]
if paths != ["/v1/chat/completions"]:
    raise SystemExit("FAIL: stub path is not the completions endpoint")
headers = open(sys.argv[6]).read().lower()
if "supabase.co" in headers or "authorization" in headers or "bearer" in headers or "ai-gateway" in headers:
    raise SystemExit("FAIL: stub saw supabase.co, a gateway, or an authorization header")
names = sorted(os.listdir(sys.argv[7]))
if names != ["held-note.txt"]:
    raise SystemExit("FAIL: session files are %r" % (names,))
PY
[ ! -e "$WORK/draft-executed" ] || { echo "FAIL: held file was executed"; exit 1; }
[ ! -e "$WORK/missing-ran" ] || { echo "FAIL: missing-id command ran later"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: draft wrote another note"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/speech.json" || { echo "FAIL: agent draft rewrote the note"; exit 1; }
[ "$(stt_lines)" = "1" ] || { echo "FAIL: agent draft spawned the transcriber"; exit 1; }
echo "check-spoken-note-draft: stub received the new transcript"
echo "check-spoken-note-draft: held file is one relative path mode 600"
echo "check-spoken-note-draft: held file was not executed"
echo "check-spoken-note-draft: command without confirm did not run"
cp "$TH/stub.body" "$TH/stub-agent.body"

replace_speech() {
  label="$1"
  text="$2"
  snap="$3"
  queue_transcript "$text"
  before="$(stt_lines)"
  code="$(post_audio "$TH/swap.json" "$ID")"
  [ "$code" = "200" ] || { echo "FAIL: $label -> ${code}"; cat "$TH/swap.json"; echo; cat "$LOG"; exit 1; }
  [ "$(stt_lines)" -eq $((before + 1)) ] || { echo "FAIL: $label did not run the transcriber once"; exit 1; }
  [ "$(note_count)" = "1" ] || { echo "FAIL: $label created a note, found $(note_count)"; exit 1; }
  [ "$(stub_posts)" = "1" ] || { echo "FAIL: $label called the model"; exit 1; }
  cp "$NOTE_FILE" "$snap"
  echo "check-spoken-note-draft: $label"
}
replace_speech "pairing transcript replaced the same note" "$PAIRING" "$TH/pairing.json"
replace_speech "hosts transcript replaced the same note" "$HOSTS" "$TH/hosts.json"
replace_speech "paper transcript replaced the same note" "$PAPER" "$TH/paper.json"
[ "$(stt_lines)" = "4" ] || { echo "FAIL: transcriber ran $(stt_lines) times"; exit 1; }
PAIRING="$PAIRING" HOSTS="$HOSTS" PAPER="$PAPER" OLD="$OLD" python3 - "$TH/pairing.json" "$TH/hosts.json" "$TH/paper.json" "$ID" <<'PY'
import json, os, sys
pairing, hosts, paper = [json.load(open(p)) for p in sys.argv[1:4]]
want_id = sys.argv[4]
for note, body in (
    (pairing, os.environ["PAIRING"]),
    (hosts, os.environ["HOSTS"]),
    (paper, os.environ["PAPER"]),
):
    if note.get("id") != want_id:
        raise SystemExit("FAIL: replaced id is %r" % (note.get("id"),))
    if note.get("title") != "Spare note":
        raise SystemExit("FAIL: replaced title is %r" % (note.get("title"),))
    if note.get("body") != body:
        raise SystemExit("FAIL: replaced body is %r" % (note.get("body"),))
    if os.environ["OLD"] in note.get("body", ""):
        raise SystemExit("FAIL: replaced body still has the old text")
PY
cmp -s "$NOTE_FILE" "$TH/paper.json" || { echo "FAIL: live note is not the paper transcript"; exit 1; }

cat > "$TH/prove.ts" <<'TS'
import { spawn } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const root = process.argv[2];
const pairingPath = process.argv[3];
const hostsPath = process.argv[4];
const paperPath = process.argv[5];
const paperWork = process.argv[6];
const stubPort = process.argv[7];
const old = process.argv[8];
const marker = process.argv[9];

function fail(message: string): never {
  console.error("FAIL: " + message);
  process.exit(1);
}

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

const fixtures = JSON.parse(readFileSync(join(root, "experiments/jev-routing/fixtures.json"), "utf8")) as {
  sendPairingCode: { text: string };
  copyHosts: { text: string };
  summarizePaper: { text: string };
};

function noteOf(path: string): Record<string, unknown> {
  const note = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
  if (typeof note.body !== "string" || typeof note.id !== "string" || typeof note.title !== "string") {
    fail("stored note has no body");
  }
  return note;
}

const allowedClass = new Set(["local", "user-subscription"]);
function assertClass(value: string, label: string): void {
  if (!allowedClass.has(value)) fail(label + " model class is " + value);
}

const samples: [string, string][] = [
  ["local", "local"],
  ["user-subscription", "user-subscription"],
  ["http://127.0.0.1:9/v1/chat/completions", "local"],
  ["https://models.example/v1", "user-subscription"],
];
for (const [sample, want] of samples) {
  const got = modelClassOf(sample);
  assertClass(got, sample);
  if (got !== want) fail(sample + " class is " + got);
}

const realFetch = globalThis.fetch;
let fetches = 0;
const sent: string[] = [];
globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = input instanceof Request ? input.url : String(input);
  if (url.includes("ai-gateway") || url.includes("supabase")) fail("fetch left the loopback stub");
  let host = "";
  try {
    host = new URL(url).hostname;
  } catch {
    host = "";
  }
  if (host !== "127.0.0.1") fail("fetch left 127.0.0.1");
  fetches += 1;
  sent.push(typeof init?.body === "string" ? init.body : "");
  return realFetch(input, init);
};

if (stubPort === "8898" || stubPort === "8899") fail("model stub used a daemon port");
const endpoint = `http://127.0.0.1:${stubPort}/v1/chat/completions`;
const scratch = await mkdtemp(join(tmpdir(), "spoken-note-draft-"));
const fileName = "held-note.txt";

function runIfConfirmed(command: string, confirm: boolean): void {
  if (confirm !== true) return;
  const child = spawn("/bin/sh", ["-c", command], { cwd: paperWork, stdio: "ignore" });
  child.unref();
}

try {
  async function held(label: string, state: Record<string, unknown>): Promise<void> {
    const before = fetches;
    const decision = route(filter(state), allow);
    if (decision !== "hold-for-review") fail(label + " route allowed");
    const result = await draftNote({
      state,
      evaluation: allow,
      endpoint,
      model: endpoint,
      cwd: scratch,
      file: fileName,
    });
    if (result.decision !== "hold-for-review") fail(label + " was drafted");
    assertClass(result.modelClass, label);
    if (result.drafted || result.file !== null) fail(label + " wrote a draft");
    if (fetches !== before) fail(label + " called the model");
    if (existsSync(join(scratch, fileName)) || existsSync(marker)) fail(label + " created a file");
    runIfConfirmed("touch " + marker, false);
    if (existsSync(marker)) fail(label + " ran a command");
    console.log("check-spoken-note-draft: " + label + " held and the model was not called");
  }

  const pairing = noteOf(pairingPath);
  if (pairing.title !== "Spare note") fail("pairing title changed");
  if (pairing.body !== fixtures.sendPairingCode.text) fail("stored pairing body is not the fixture ask");
  if (String(pairing.body).includes(old)) fail("stored pairing body still has the old text");
  await held("pairing code", pairing);

  const hosts = noteOf(hostsPath);
  if (hosts.title !== "Spare note") fail("hosts title changed");
  if (hosts.body !== fixtures.copyHosts.text) fail("stored hosts body is not the fixture ask");
  if (String(hosts.body).includes(old)) fail("stored hosts body still has the old text");
  await held("hosts.json", hosts);

  const paper = noteOf(paperPath);
  if (paper.title !== "Spare note") fail("paper title changed");
  if (paper.body !== fixtures.summarizePaper.text) fail("stored paper body is not the fixture ask");
  if (paper.body !== "summarize this paper") fail("paper transcript is not the summary ask");
  if (String(paper.body).includes(old)) fail("stored paper body still has the old text");
  if (route(filter(paper), allow) !== "allow-local-tool") fail("replaced paper was held");
  const drafted = await draftNote({
    state: paper,
    evaluation: allow,
    endpoint,
    model: "http://127.0.0.1:" + stubPort + "/v1",
    cwd: paperWork,
    file: fileName,
  });
  if (drafted.decision !== "allow-local-tool" || !drafted.drafted || drafted.file !== fileName) {
    fail("clean paper was not drafted");
  }
  assertClass(drafted.modelClass, "paper");
  if (drafted.modelClass !== "local") fail("loopback model was not class local");
  if (fetches !== 1 || sent.length !== 1) fail("clean paper did not call the model once");
  const posted = JSON.parse(sent[0]) as { model?: string; messages?: { content?: string }[] };
  if (!allowedClass.has(String(posted.model))) fail("stub saw model " + String(posted.model));
  if (posted.model !== "local") fail("stub model class is " + String(posted.model));
  const messages = JSON.stringify(posted.messages ?? []);
  if (!messages.includes("summarize this paper")) fail("stub did not receive the new body");
  if (messages.includes(old)) fail("stub received an old body");
  if (messages.includes(fixtures.sendPairingCode.text) || messages.includes(fixtures.copyHosts.text)) {
    fail("stub received a held transcript");
  }
  const draftPath = join(paperWork, fileName);
  const info = statSync(draftPath);
  if (!info.isFile() || (info.mode & 0o777) !== 0o600) fail("draft mode is " + (info.mode & 0o777).toString(8));
  if (info.mode & 0o111) fail("draft file is executable");
  const names = (await readdir(paperWork)).sort();
  if (names.length !== 1 || names[0] !== fileName) fail("paper session files are " + names.join(","));
  runIfConfirmed(readFileSync(draftPath, "utf8"), false);
  if (existsSync(marker)) fail("unconfirmed command ran");
  const dumped = JSON.stringify(drafted);
  if (dumped.includes(endpoint) || dumped.includes("ai-gateway") || dumped.includes("supabase")) {
    fail("draft result recorded an endpoint");
  }
  console.log("check-spoken-note-draft: summarize this paper drafted the new body");
} finally {
  globalThis.fetch = realFetch;
  await rm(scratch, { recursive: true, force: true });
}
TS

if grep -q "$(gateway_name)" "$TH/prove.ts"; then
  echo "FAIL: prove step names a live gateway call"
  exit 1
fi

posts_before="$(stub_posts)"
[ "$posts_before" = "1" ] || { echo "FAIL: expected one agent draft call before the hold, found $posts_before"; exit 1; }
env -u AI_GATEWAY_API_KEY \
  node --experimental-strip-types "$TH/prove.ts" \
  "$ROOT" "$TH/pairing.json" "$TH/hosts.json" "$TH/paper.json" "$PAPER_WORK" "$STUB_PORT" "$OLD" "$WORK/draft-executed"

[ "$(stub_posts)" = "2" ] || { echo "FAIL: hold or paper draft called the model the wrong number of times"; exit 1; }
PAPER="$PAPER" OLD="$OLD" PAIRING="$PAIRING" HOSTS="$HOSTS" python3 - "$TH/stub.body" "$TH/stub-agent.body" <<'PY'
import json, os, sys
def lines(path):
    return [ln for ln in open(path, "rb").read().splitlines() if ln]
agent = lines(sys.argv[2])
both = lines(sys.argv[1])
if len(agent) != 1 or len(both) != 2:
    raise SystemExit("FAIL: stub history is %d then %d" % (len(agent), len(both)))
if both[0] != agent[0]:
    raise SystemExit("FAIL: agent draft request was rewritten")
paper = json.loads(both[1])
messages = json.dumps(paper.get("messages"))
if os.environ["PAPER"] not in messages:
    raise SystemExit("FAIL: second stub call missed the paper transcript")
for banned in (os.environ["OLD"], os.environ["PAIRING"], os.environ["HOSTS"]):
    if banned in messages:
        raise SystemExit("FAIL: second stub call included a held or old body")
if paper.get("model") != "local":
    raise SystemExit("FAIL: second stub model class is %r" % (paper.get("model"),))
PY

[ ! -e "$WORK/draft-executed" ] || { echo "FAIL: unconfirmed command ran"; exit 1; }
[ ! -e "$WORK/missing-ran" ] || { echo "FAIL: missing id command ran"; exit 1; }
[ -f "$WORK/held-note.txt" ] || { echo "FAIL: agent draft file is missing"; exit 1; }
held_mode="$(mode_of "$WORK/held-note.txt")"
[ "$held_mode" = "600" ] || { echo "FAIL: held file mode is $held_mode, want 600"; exit 1; }
[ -f "$PAPER_WORK/held-note.txt" ] || { echo "FAIL: paper draft file is missing"; exit 1; }
paper_mode="$(mode_of "$PAPER_WORK/held-note.txt")"
[ "$paper_mode" = "600" ] || { echo "FAIL: paper draft mode is $paper_mode, want 600"; exit 1; }
cmp -s "$WORK/held-note.txt" "$TH/stub.reply" || { echo "FAIL: held file is not the stub reply"; exit 1; }
cmp -s "$PAPER_WORK/held-note.txt" "$TH/stub.reply" || { echo "FAIL: paper draft is not the stub reply"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: draft changed the note count"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/paper.json" || { echo "FAIL: draft rewrote the paper note"; exit 1; }
[ ! -d "$HOME_DIR/.mesh" ] || { echo "FAIL: daemon wrote under its home directory"; exit 1; }
if [ "$had_mesh" -eq 0 ] && [ -e "$MESH_MARK" ]; then
  echo "FAIL: wrote ~/.mesh"
  exit 1
fi

if grep -E -q 'supabase\.co|ai-gateway' "$LOG"; then
  echo "FAIL: daemon log records supabase.co or the AI gateway"
  exit 1
fi

if [ "$(uname -s)" = "Darwin" ]; then
  command -v lsof >/dev/null 2>&1 || { echo "FAIL: lsof is required on Darwin"; exit 1; }
  SRV_PID="$SRV" HOME_DIR="$HOME_DIR" STATE="$STATE" STT="$TH/stt" python3 - <<'PY'
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
    "MESH_STT=" + os.environ["STT"],
]
for item in need:
    if item not in env_text.split():
        sys.exit("FAIL: daemon env is missing " + item.split("=", 1)[0])
if "AI_GATEWAY_API_KEY=" in env_text:
    sys.exit("FAIL: AI_GATEWAY_API_KEY is set in the daemon")

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
  SRV_PID="$SRV" HOME_DIR="$HOME_DIR" STATE="$STATE" STT="$TH/stt" python3 - <<'PY'
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
    "MESH_STT": os.environ["STT"],
}
for key, value in need.items():
    if env.get(key) != value:
        sys.exit("FAIL: daemon env %s is not the spare value" % key)
if env.get("AI_GATEWAY_API_KEY"):
    sys.exit("FAIL: AI_GATEWAY_API_KEY is set in the daemon")
if bad:
    sys.exit("FAIL: daemon has a non-loopback socket: %s" % ", ".join(bad))
PY
fi
echo "check-spoken-note-draft: no live gateway call"
echo "check-spoken-note-draft: OK"

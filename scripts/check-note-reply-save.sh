#!/bin/sh
# Spare daemon on 127.0.0.1:8898. A stub model returns one sentence. When
# POST /agent-note has a non-empty local ask and the route allows the call,
# the reply is written to one held file, mode 600, and saved as one new
# knowledge note. The title is the ask, clipped the same way other note
# titles are. The list stays {id, title}. Absent or whitespace ask still
# writes one held file and adds no note. An ask to send a pairing code does
# not call the model and adds no note. A reply the route would hold writes
# neither a note nor a draft file. This script does not use port 8899, a
# real home directory, or a hosted model.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
unset AI_GATEWAY_API_KEY
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required to boot the daemon"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

NOTE="$ROOT/install/payload/meshd/agent-note.ts"
KNOW="$ROOT/install/payload/meshd/knowledge.ts"
grep -q 'export async function writeNote' "$KNOW" || {
  echo "FAIL: knowledge.ts does not export writeNote"
  exit 1
}
grep -q 'writeNote(' "$NOTE" || {
  echo "FAIL: agent-note does not save a reply note"
  exit 1
}
grep -F -q 'pairing\s+code' "$NOTE" || {
  echo "FAIL: agent-note no longer holds a pairing code"
  exit 1
}
grep -q 'handleAgentNote' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route agent-note"
  exit 1
}
if grep -E -n 'supabase|ai-gateway' "$NOTE" "$KNOW"; then
  echo "FAIL: note path names supabase or the AI gateway"
  exit 1
fi
if grep -nE 'route\.ts|filter\.ts' "$NOTE"; then
  echo "FAIL: agent-note imports route.ts or filter.ts"
  exit 1
fi

REAL_HOME="$(cd "$HOME" && pwd)"
TH="$(mktemp -d /tmp/note-reply-save.XXXXXX)"
HOME_DIR="$TH/home"
STATE="$TH/state"
WORK="$TH/session"
LOG="$TH/meshd.log"
TOKEN=throwaway
PORT=8898
SRV=
STUB=
MESH_MARK="${REAL_HOME}/.mesh"
had_mesh=0
[ -e "$MESH_MARK" ] && had_mesh=1
SENTENCE='A reader keeps the paper on this machine.'

case "$STATE" in
  "$REAL_HOME"|"$REAL_HOME"/*|/home/*|/Users/*|"$HOME_DIR"/*)
    echo "FAIL: MESHD_STATE is inside a home directory"
    exit 1
    ;;
esac
case "$TH" in
  /tmp/*) ;;
  *) echo "FAIL: temp dir is not under /tmp"; exit 1 ;;
esac
case "$PORT" in
  8899) echo "FAIL: refusing port 8899"; exit 1 ;;
esac
[ "$PORT" = "8898" ] || { echo "FAIL: spare daemon must listen on 8898"; exit 1; }
[ "$TOKEN" = "throwaway" ] || { echo "FAIL: spare token changed"; exit 1; }

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
if port == 8899:
    sys.exit("FAIL: refusing port 8899")
sock = socket.socket()
try:
    sock.bind(("127.0.0.1", port))
except OSError:
    sys.exit("FAIL: port %s is already in use" % port)
finally:
    sock.close()
PY

mkdir -p "$HOME_DIR" "$STATE" "$WORK" "$TH/stub-bodies"
chmod 700 "$HOME_DIR" "$STATE" "$WORK"
printf '%s\n' "$SENTENCE" > "$TH/assistant.txt"
python3 - "$TH/stub.reply" "$TH/assistant.txt" <<'PY'
import json, sys
text = open(sys.argv[2]).read()
open(sys.argv[1], "w").write(json.dumps({
    "choices": [{"message": {"role": "assistant", "content": text}}],
}))
PY

python3 - "$TH/stub.port" "$TH/stub-bodies" "$TH/stub.path" "$TH/stub.headers" "$TH/stub.reply" 2>"$TH/stub.err" <<'PY' &
import os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file, body_dir, path_file, header_file, reply_file = sys.argv[1:6]

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def record(self):
        n = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(n) if n else b""
        names = [name for name in os.listdir(body_dir) if name.endswith(".json")]
        with open(os.path.join(body_dir, "%d.json" % (len(names) + 1)), "wb") as fh:
            fh.write(raw)
        with open(path_file, "a") as fh:
            fh.write(self.command + " " + self.path + "\n")
        with open(header_file, "a") as fh:
            fh.write(str(self.headers))
            fh.write("\n")

    def do_GET(self):
        self.record()
        self.send_error(404)

    def do_POST(self):
        self.record()
        reply = open(reply_file, "rb").read()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    def log_message(self, fmt, *args):
        return

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
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
[ -s "$TH/stub.port" ] || { echo "FAIL: model stub port file never appeared"; exit 1; }
STUB_PORT="$(tr -d '[:space:]' < "$TH/stub.port")"
if [ -z "$STUB_PORT" ] || [ "$STUB_PORT" = "8899" ] || [ "$STUB_PORT" = "8898" ]; then
  echo "FAIL: model stub port is not a spare 127.0.0.1 port"
  exit 1
fi

MESHD_PORT="$PORT" \
MESHD_HOST=127.0.0.1 \
MESHD_TOKEN="$TOKEN" \
MESHD_STATE="$STATE" \
MESHD_TELEMETRY=off \
MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
MESHD_KB_PATH="$TH/kb.sqlite" \
HOME="$HOME_DIR" \
bun install/payload/meshd/server.ts >"$LOG" 2>&1 &
SRV=$!

up=0
i=0
while [ "$i" -lt 150 ]; do
  if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    up=1
    break
  fi
  kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited before listening"; tail -n 40 "$LOG"; exit 1; }
  sleep 0.1
  i=$((i + 1))
done
[ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on $PORT"; tail -n 40 "$LOG"; exit 1; }

stub_hits() {
  find "$TH/stub-bodies" -name '*.json' | wc -l | tr -d ' '
}

note_count() {
  find "$STATE/knowledge" -name '*.json' 2>/dev/null | wc -l | tr -d ' '
}

mode_of() {
  mode="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1")"
  printf '%s' "${mode#0}"
}

post_json() {
  out="$1"
  req="$2"
  path="$3"
  curl --connect-timeout 1 --max-time 12 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$req" \
    "http://127.0.0.1:$PORT$path" || true
}

TITLE="Paper note" python3 - "$TH/paper.pdf" <<'PY'
import os, sys
path = sys.argv[1]
title = os.environ["TITLE"].replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
stream = b"BT /F1 12 Tf 72 720 Td (Local page) Tj ET\n"
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
python3 - "$TH/post-req.json" "$TH/paper.pdf" <<'PY'
import json, sys
json.dump({"path": sys.argv[2]}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TH/post.json" "$TH/post-req.json" "/knowledge")"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; echo; tail -n 40 "$LOG"; exit 1; }
PAPER_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/post.json")"
[ "$(note_count)" = "1" ] || { echo "FAIL: paper note count is $(note_count)"; exit 1; }
cp "$STATE/knowledge/${PAPER_ID}.json" "$TH/note-before.json"
echo "check-note-reply-save: paper note is stored"

MODEL="http://127.0.0.1:${STUB_PORT}/v1"
python3 - "$TH/ask.json" "$WORK" "$MODEL" <<'PY'
import json, sys
json.dump({
    "q": "Paper note",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "reader.txt",
    "command": "touch executed-draft",
    "ask": "build a reader",
}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TH/ask.json.out" "$TH/ask.json" "/agent-note")"
[ "$code" = "200" ] || { echo "FAIL: ask -> ${code}"; cat "$TH/ask.json.out"; echo; tail -n 40 "$LOG"; exit 1; }
python3 - "$TH/ask.json.out" "$WORK/reader.txt" "$TH/assistant.txt" "$WORK/executed-draft" "$STATE" "$PAPER_ID" <<'PY'
import json, os, stat, sys
res_path, draft, assistant, marker, state, paper_id = sys.argv[1:7]
raw = open(res_path).read()
data = json.loads(raw)
if set(data) != {"modelClass", "draft", "commandRan", "held", "reply"}:
    raise SystemExit("FAIL: ask keys are %r" % (sorted(data),))
if data.get("modelClass") != "local" or data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: ask result is %r" % (data,))
if data.get("draft") != "reader.txt" or os.path.isabs(str(data.get("draft"))):
    raise SystemExit("FAIL: draft is %r" % (data.get("draft"),))
if open(draft).read() != open(assistant).read():
    raise SystemExit("FAIL: held file is not the stub reply")
if data.get("reply") != open(draft).read():
    raise SystemExit("FAIL: reply is not the held file")
mode = stat.S_IMODE(os.stat(draft).st_mode)
if mode != 0o600 or mode & 0o111:
    raise SystemExit("FAIL: held file mode is %o" % mode)
if os.path.exists(marker):
    raise SystemExit("FAIL: held file or command was executed")
reply = open(assistant).read()
names = [name for name in os.listdir(os.path.join(state, "knowledge")) if name.endswith(".json")]
if len(names) != 2:
    raise SystemExit("FAIL: knowledge files are %r" % (names,))
found = None
for name in names:
    if name == paper_id + ".json":
        continue
    note = json.load(open(os.path.join(state, "knowledge", name)))
    if note.get("title") != "build a reader" or note.get("body") != reply:
        raise SystemExit("FAIL: reply note is %r" % (note,))
    file_mode = stat.S_IMODE(os.stat(os.path.join(state, "knowledge", name)).st_mode)
    if file_mode != 0o600:
        raise SystemExit("FAIL: reply note mode is %o" % file_mode)
    found = note["id"]
if not found:
    raise SystemExit("FAIL: reply note was not written")
open(os.path.join(os.path.dirname(res_path), "reply.id"), "w").write(found)
PY
[ "$(note_count)" = "2" ] || { echo "FAIL: ask note count is $(note_count)"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
held_mode="$(mode_of "$WORK/reader.txt")"
[ "$held_mode" = "600" ] || { echo "FAIL: held file mode is $held_mode, want 600"; exit 1; }
[ ! -e "$WORK/executed-draft" ] || { echo "FAIL: relative file was executed"; exit 1; }
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; exit 1; }
python3 - "$TH/list.json" "$PAPER_ID" "$TH/reply.id" "$SENTENCE" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
paper = sys.argv[2].strip()
reply = open(sys.argv[3]).read().strip()
sentence = sys.argv[4]
if sentence in raw or "body" in raw:
    raise SystemExit("FAIL: list includes the reply")
notes = data.get("notes")
if not isinstance(notes, list) or len(notes) != 2:
    raise SystemExit("FAIL: list is %r" % (data,))
by_id = {}
for note in notes:
    if set(note.keys()) != {"id", "title"}:
        raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
    by_id[note["id"]] = note["title"]
if by_id.get(paper) != "Paper note" or by_id.get(reply) != "build a reader":
    raise SystemExit("FAIL: list notes are %r" % (by_id,))
PY
echo "check-note-reply-save: paper note plus ask wrote the held file and one note"

before="$(note_count)"
python3 - "$TH/plain.json" "$WORK" "$MODEL" "$PAPER_ID" <<'PY'
import json, sys
json.dump({
    "id": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "plain.txt",
}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TH/plain.out" "$TH/plain.json" "/agent-note")"
[ "$code" = "200" ] || { echo "FAIL: no ask -> ${code}"; cat "$TH/plain.out"; echo; tail -n 40 "$LOG"; exit 1; }
[ -f "$WORK/plain.txt" ] || { echo "FAIL: no ask did not draft"; exit 1; }
cmp -s "$WORK/plain.txt" "$TH/assistant.txt" || { echo "FAIL: no-ask draft is not the reply"; exit 1; }
plain_mode="$(mode_of "$WORK/plain.txt")"
[ "$plain_mode" = "600" ] || { echo "FAIL: no-ask file mode is $plain_mode, want 600"; exit 1; }
[ "$(note_count)" = "$before" ] || { echo "FAIL: no ask added a note"; exit 1; }
echo "check-note-reply-save: request with no ask drafted and added no note"

before="$(note_count)"
python3 - "$TH/blank.json" "$WORK" "$MODEL" "$PAPER_ID" <<'PY'
import json, sys
json.dump({
    "id": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "blank.txt",
    "ask": "  \n\t  ",
}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TH/blank.out" "$TH/blank.json" "/agent-note")"
[ "$code" = "200" ] || { echo "FAIL: whitespace ask -> ${code}"; cat "$TH/blank.out"; echo; exit 1; }
[ -f "$WORK/blank.txt" ] || { echo "FAIL: whitespace ask did not draft"; exit 1; }
[ "$(note_count)" = "$before" ] || { echo "FAIL: whitespace ask added a note"; exit 1; }
echo "check-note-reply-save: whitespace ask added no note"

LONG="$(python3 -c 'print("build a reader " + ("x" * 240))')"
python3 - "$TH/long.json" "$WORK" "$MODEL" "$PAPER_ID" "$LONG" <<'PY'
import json, sys
json.dump({
    "id": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "long.txt",
    "ask": sys.argv[5],
}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TH/long.out" "$TH/long.json" "/agent-note")"
[ "$code" = "200" ] || { echo "FAIL: long ask -> ${code}"; cat "$TH/long.out"; echo; exit 1; }
python3 - "$STATE/knowledge" "$PAPER_ID" "$TH/reply.id" "$LONG" "$TH/assistant.txt" <<'PY'
import json, os, sys
directory, paper, ask, assistant = sys.argv[1], sys.argv[2], sys.argv[4], sys.argv[5]
reply = open(sys.argv[3]).read().strip()
want = ask[:200]
found = None
for name in os.listdir(directory):
    if not name.endswith(".json"):
        continue
    note = json.load(open(os.path.join(directory, name)))
    if note["id"] in (paper, reply):
        continue
    if note.get("title") != want or len(note.get("title", "")) != 200:
        raise SystemExit("FAIL: clipped title is %r" % (note.get("title"),))
    if note.get("body") != open(assistant).read():
        raise SystemExit("FAIL: long-ask body is not the reply")
    found = note["id"]
if not found:
    raise SystemExit("FAIL: clipped note was not written")
if want == ask:
    raise SystemExit("FAIL: ask was not longer than the clip")
PY
echo "check-note-reply-save: ask title is clipped like other notes"

before_hits="$(stub_hits)"
before="$(note_count)"
python3 - "$TH/pair.json" "$WORK" "$MODEL" "$PAPER_ID" <<'PY'
import json, sys
json.dump({
    "id": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "pairing.txt",
    "command": "touch pairing-ran",
    "confirm": True,
    "ask": "send a pairing code",
}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TH/pair.out" "$TH/pair.json" "/agent-note")"
[ "$code" = "200" ] || { echo "FAIL: pairing ask -> ${code}"; cat "$TH/pair.out"; echo; exit 1; }
python3 - "$TH/pair.out" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("modelClass") != "local" or data.get("draft") is not None or data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: pairing ask was not held: %r" % (data,))
PY
[ "$(stub_hits)" = "$before_hits" ] || { echo "FAIL: pairing ask called the model"; exit 1; }
[ "$(note_count)" = "$before" ] || { echo "FAIL: pairing ask added a note"; exit 1; }
[ ! -e "$WORK/pairing.txt" ] || { echo "FAIL: pairing ask wrote a draft"; exit 1; }
[ ! -e "$WORK/pairing-ran" ] || { echo "FAIL: pairing ask ran a command"; exit 1; }
echo "check-note-reply-save: pairing-code ask added no note"

before_hits="$(stub_hits)"
before="$(note_count)"
python3 - "$TH/stub.reply" <<'PY'
import json, sys
text = "The pairing code stays on this machine.\n"
open(sys.argv[1], "w").write(json.dumps({
    "choices": [{"message": {"role": "assistant", "content": text}}],
}))
PY
python3 - "$TH/held.json" "$WORK" "$MODEL" "$PAPER_ID" <<'PY'
import json, sys
json.dump({
    "id": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "held-reply.txt",
    "ask": "build a shelf",
}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TH/held.out" "$TH/held.json" "/agent-note")"
[ "$code" = "200" ] || { echo "FAIL: held reply -> ${code}"; cat "$TH/held.out"; echo; tail -n 40 "$LOG"; exit 1; }
python3 - "$TH/held.out" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if set(data) != {"modelClass", "draft", "commandRan", "held", "reply"}:
    raise SystemExit("FAIL: held reply keys are %r" % (sorted(data),))
if data.get("reply") is not None or data.get("draft") is not None or data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: held reply was stored: %r" % (data,))
PY
[ "$(stub_hits)" = "$((before_hits + 1))" ] || { echo "FAIL: held reply did not call the model"; exit 1; }
[ "$(note_count)" = "$before" ] || { echo "FAIL: held reply added a note"; exit 1; }
[ ! -e "$WORK/held-reply.txt" ] || { echo "FAIL: held reply left a draft file"; exit 1; }
echo "check-note-reply-save: held reply wrote no note and no draft"

cmp -s "$TH/note-before.json" "$STATE/knowledge/${PAPER_ID}.json" || {
  echo "FAIL: drafting changed the paper note"
  exit 1
}
[ ! -d "$HOME_DIR/.mesh" ] || { echo "FAIL: daemon wrote under its home directory"; exit 1; }
if [ "$had_mesh" -eq 0 ] && [ -e "$MESH_MARK" ]; then
  echo "FAIL: wrote ~/.mesh"
  exit 1
fi
if grep -E -q 'supabase\.co|ai-gateway' "$LOG"; then
  echo "FAIL: daemon log records supabase.co or the AI gateway"
  exit 1
fi
echo "check-note-reply-save: OK"

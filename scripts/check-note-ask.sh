#!/bin/sh
# Spare daemon on 127.0.0.1:8898. POST /agent-note takes an optional local
# ask. Absent or blank, the model receives the note text only. A paper note
# plus "build a reader" reaches the stub and is stored as one relative file,
# mode 600, not executed. An ask that says to send a pairing code is held
# before the model. An ask containing :// or a protocol-relative ask is 400
# and writes nothing. A command runs only when confirm is true. The model
# class is only local or user-subscription. This script does not use port
# 8899, a real home directory, or the AI gateway.
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

calls="$(grep -c 'await handleKnowledge(' "$ROOT/install/payload/meshd/server.ts" || true)"
[ "$calls" = "1" ] || { echo "FAIL: server.ts must call handleKnowledge once"; exit 1; }
grep -q 'handleAgentNote' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route agent-note"
  exit 1
}
if grep -nE 'route\.ts|filter\.ts' "$ROOT/install/payload/meshd/agent-note.ts"; then
  echo "FAIL: agent-note imports route.ts or filter.ts"
  exit 1
fi
if grep -E -n 'supabase|ai-gateway' "$ROOT/install/payload/meshd/agent-note.ts"; then
  echo "FAIL: note path names supabase or the AI gateway"
  exit 1
fi
grep -F -q 'ask must be local text' "$ROOT/install/payload/meshd/agent-note.ts" || {
  echo "FAIL: agent-note does not refuse a remote ask"
  exit 1
}
grep -F -q 'pairing\s+code' "$ROOT/install/payload/meshd/agent-note.ts" || {
  echo "FAIL: agent-note no longer holds a pairing code"
  exit 1
}

bun -e '
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
  if (!allowed.has(got) || got !== want) {
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
echo "check-note-ask: model class is local or user-subscription"

PAPER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["summarizePaper"]["text"], end="")' \
  "$ROOT/experiments/jev-routing/fixtures.json")"
[ -n "$PAPER" ] || { echo "FAIL: paper fixture is missing"; exit 1; }

TH="$(mktemp -d /tmp/note-ask.XXXXXX)"
HOME_DIR="$TH/home"
STATE="$TH/state"
WORK="$TH/session"
LOG="$TH/meshd.log"
TOKEN=throwaway
PORT=8898
SRV=
STUB=
MESH_MARK="${HOME}/.mesh"
had_mesh=0
[ -e "$MESH_MARK" ] && had_mesh=1

case "$STATE" in
  /home/*|/Users/*|"$HOME"/*|"$HOME_DIR"/*)
    echo "FAIL: MESHD_STATE is inside a home directory"
    exit 1
    ;;
esac
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
printf '%s\n' 'Draft of the reader.' > "$TH/assistant.txt"
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
reply = open(reply_file, "rb").read()

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
echo "check-note-ask: model stub is on 127.0.0.1:${STUB_PORT}"

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

mode_of() {
  mode="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1")"
  printf '%s' "${mode#0}"
}

post_agent() {
  out="$1"
  req="$2"
  curl --connect-timeout 1 --max-time 12 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$req" \
    "http://127.0.0.1:$PORT/agent-note" || true
}

write_pdf() {
  title="$1"
  path="$2"
  TITLE="$title" python3 - "$path" <<'PY'
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
}

write_pdf "Paper note" "$TH/paper.pdf"
python3 - "$TH/post-req.json" "$TH/paper.pdf" <<'PY'
import json, sys
json.dump({"path": sys.argv[2]}, open(sys.argv[1], "w"))
PY
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/post.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/post-req.json" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; exit 1; }
PAPER_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/post.json")"
BODY="$PAPER" python3 - "$TH/body-req.json" <<'PY'
import json, os, sys
json.dump({"body": os.environ["BODY"]}, open(sys.argv[1], "w"))
PY
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/body.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/body-req.json" \
  "http://127.0.0.1:$PORT/knowledge/${PAPER_ID}" || true)"
[ "$code" = "200" ] || { echo "FAIL: replace note -> ${code}"; cat "$TH/body.json"; exit 1; }
[ "$(stub_hits)" = "0" ] || { echo "FAIL: ingest called the model"; exit 1; }
python3 - "$STATE/knowledge/${PAPER_ID}.json" "$PAPER" "$TH/note-text.txt" <<'PY'
import json, sys
note = json.load(open(sys.argv[1]))
paper = sys.argv[2]
if note.get("title") != "Paper note":
    raise SystemExit("FAIL: paper title is %r" % (note.get("title"),))
if note.get("body") != paper:
    raise SystemExit("FAIL: paper body is %r" % (note.get("body"),))
title = note["title"].strip()
body = note["body"].strip()
text = "%s\n\n%s" % (title, body) if title else body
open(sys.argv[3], "w").write(text)
PY
echo "check-note-ask: paper note is stored"

MODEL="http://127.0.0.1:${STUB_PORT}/v1"
cp "$STATE/knowledge/${PAPER_ID}.json" "$TH/note-before.json"

write_req() {
  dest="$1"
  ask_mode="$2"
  ask_value="$3"
  file="$4"
  confirm="$5"
  marker="$6"
  python3 - "$dest" "$ask_mode" "$ask_value" "$WORK" "$MODEL" "$file" "$confirm" "$marker" <<'PY'
import json, sys
dest, mode, ask, work, model, file, confirm, marker = sys.argv[1:9]
body = {
    "q": "Paper note",
    "cwd": work,
    "model": model,
    "file": file,
    "command": "touch " + marker,
    "confirm": confirm == "yes",
}
if mode == "present":
    body["ask"] = ask
json.dump(body, open(dest, "w"))
PY
}

work_files() {
  find "$WORK" -type f -print | sort
}

expect_remote() {
  label="$1"
  ask="$2"
  before="$(stub_hits)"
  files_before="$(work_files || true)"
  write_req "$TH/remote-req.json" present "$ask" "remote-draft.txt" yes "remote-ran"
  code="$(post_agent "$TH/remote.json" "$TH/remote-req.json")"
  [ "$code" = "400" ] || { echo "FAIL: ${label} -> ${code}"; cat "$TH/remote.json"; echo; exit 1; }
  python3 - "$TH/remote.json" "$label" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data != {"error": "ask must be local text"}:
    raise SystemExit("FAIL: %s body is %r" % (sys.argv[2], data))
PY
  [ "$(stub_hits)" = "$before" ] || { echo "FAIL: ${label} called the model"; exit 1; }
  [ "$(work_files || true)" = "$files_before" ] || { echo "FAIL: ${label} wrote a file"; exit 1; }
  [ ! -e "$WORK/remote-draft.txt" ] || { echo "FAIL: ${label} wrote a draft"; exit 1; }
  [ ! -e "$WORK/remote-ran" ] || { echo "FAIL: ${label} ran a command"; exit 1; }
  cmp -s "$TH/note-before.json" "$STATE/knowledge/${PAPER_ID}.json" || {
    echo "FAIL: ${label} changed the note"
    exit 1
  }
  echo "check-note-ask: ${label} wrote nothing"
}

expect_remote "ask containing ://" "http://127.0.0.1:${STUB_PORT}/reader"
expect_remote "protocol-relative ask" "//example.invalid/reader"
expect_remote "ask with an embedded separator" "build :// a reader"

expect_held() {
  label="$1"
  ask="$2"
  before="$(stub_hits)"
  write_req "$TH/held-req.json" present "$ask" "held-draft.txt" yes "held-ran"
  code="$(post_agent "$TH/held.json" "$TH/held-req.json")"
  [ "$code" = "200" ] || { echo "FAIL: ${label} -> ${code}"; cat "$TH/held.json"; echo; exit 1; }
  python3 - "$TH/held.json" "$label" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
allowed = {"local", "user-subscription"}
if set(data) != {"modelClass", "draft", "commandRan", "held", "reply"}:
    raise SystemExit("FAIL: %s keys are %r" % (sys.argv[2], sorted(data)))
if data.get("modelClass") not in allowed or data.get("modelClass") != "local":
    raise SystemExit("FAIL: %s modelClass is %r" % (sys.argv[2], data.get("modelClass")))
if data.get("draft") is not None or data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: %s was not held: %r" % (sys.argv[2], data))
raw = open(sys.argv[1]).read()
for needle in ("127.0.0.1", "http", "supabase", "chat/completions"):
    if needle in raw:
        raise SystemExit("FAIL: %s transcript contains %s" % (sys.argv[2], needle))
PY
  [ "$(stub_hits)" = "$before" ] || { echo "FAIL: ${label} called the model"; exit 1; }
  [ ! -e "$WORK/held-draft.txt" ] || { echo "FAIL: ${label} wrote a draft"; exit 1; }
  [ ! -e "$WORK/held-ran" ] || { echo "FAIL: ${label} ran a command"; exit 1; }
  if [ -n "$(find "$WORK" -type f -print)" ]; then
    echo "FAIL: ${label} wrote a file"
    exit 1
  fi
  echo "check-note-ask: ${label} did not call the model"
}

expect_held "ask to send a pairing code" "send a pairing code"
expect_held "ask naming hosts.json" "read hosts.json"
expect_held "ask naming .mesh/token" "open .mesh/token"
expect_held "ask naming a mesh token" "show the mesh token"
expect_held "ask to upload a secret" "please upload the secret"

expect_draft() {
  label="$1"
  mode="$2"
  ask="$3"
  file="$4"
  confirm="$5"
  marker="$6"
  want_ran="$7"
  want_prompt="$8"
  write_req "$TH/draft-req.json" "$mode" "$ask" "$file" "$confirm" "$marker"
  code="$(post_agent "$TH/draft.json" "$TH/draft-req.json")"
  [ "$code" = "200" ] || { echo "FAIL: ${label} -> ${code}"; cat "$TH/draft.json"; echo; tail -n 40 "$LOG"; exit 1; }
  PROMPT="$want_prompt" python3 - "$TH/draft.json" "$WORK/$file" "$TH/assistant.txt" "$label" "$want_ran" "$WORK/$marker" <<'PY'
import json, os, stat, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
label, want_ran, marker = sys.argv[4:7]
allowed = {"local", "user-subscription"}
if set(data) != {"modelClass", "draft", "commandRan", "held", "reply"}:
    raise SystemExit("FAIL: %s keys are %r" % (label, sorted(data)))
if data.get("modelClass") not in allowed or data.get("modelClass") != "local":
    raise SystemExit("FAIL: %s modelClass is %r" % (label, data.get("modelClass")))
ran = want_ran == "yes"
if data.get("commandRan") is not ran:
    raise SystemExit("FAIL: %s commandRan is %r" % (label, data.get("commandRan")))
if data.get("held") is ran:
    raise SystemExit("FAIL: %s held is %r" % (label, data.get("held")))
if data.get("draft") != os.path.basename(sys.argv[2]) or os.path.isabs(str(data.get("draft"))):
    raise SystemExit("FAIL: %s draft is %r" % (label, data.get("draft")))
for needle in ("127.0.0.1", "http", "supabase", "chat/completions"):
    if needle in raw:
        raise SystemExit("FAIL: %s transcript contains %s" % (label, needle))
if open(sys.argv[2]).read() != open(sys.argv[3]).read():
    raise SystemExit("FAIL: %s file is not the stub reply" % label)
mode = stat.S_IMODE(os.stat(sys.argv[2]).st_mode)
if mode != 0o600 or mode & 0o111:
    raise SystemExit("FAIL: %s mode is %o" % (label, mode))
if ran and not os.path.isfile(marker):
    raise SystemExit("FAIL: %s confirm did not run the command" % label)
if not ran and os.path.exists(marker):
    raise SystemExit("FAIL: %s ran a command" % label)
PY
  echo "check-note-ask: ${label}"
}

NOTE_TEXT="$(cat "$TH/note-text.txt")"
READER_PROMPT="${NOTE_TEXT}

build a reader"
expect_draft "paper note plus ask" present "build a reader" "held-reader.txt" no "unconfirmed-ran" no "$READER_PROMPT"
[ "$(stub_hits)" = "1" ] || { echo "FAIL: reader ask called the model $(stub_hits) times"; exit 1; }
held_mode="$(mode_of "$WORK/held-reader.txt")"
[ "$held_mode" = "600" ] || { echo "FAIL: held file mode is $held_mode, want 600"; exit 1; }
echo "check-note-ask: paper note plus ask wrote one relative file mode 600"

expect_draft "request with no ask" absent "" "plain.txt" no "plain-ran" no "$NOTE_TEXT"
[ "$(stub_hits)" = "2" ] || { echo "FAIL: no-ask draft called the model $(stub_hits) times"; exit 1; }
echo "check-note-ask: request with no ask still drafted"

expect_draft "whitespace ask" present "  	
  " "blank-ask.txt" no "blank-ran" no "$NOTE_TEXT"
[ "$(stub_hits)" = "3" ] || { echo "FAIL: whitespace ask called the model $(stub_hits) times"; exit 1; }
echo "check-note-ask: whitespace ask drafted the note text only"

expect_draft "ask with confirm" present "build a reader" "confirmed.txt" yes "confirmed-ran" yes "$READER_PROMPT"
[ "$(stub_hits)" = "4" ] || { echo "FAIL: confirmed ask called the model $(stub_hits) times"; exit 1; }
[ -f "$WORK/confirmed-ran" ] || { echo "FAIL: confirm true did not run the command"; exit 1; }
echo "check-note-ask: command ran only when confirm was true"

NOTE_TEXT="$NOTE_TEXT" python3 - "$TH/stub-bodies" "$TH/stub.path" "$TH/stub.headers" "$WORK" <<'PY'
import json, os, sys
body_dir, path_file, header_file, work = sys.argv[1:5]
names = sorted(name for name in os.listdir(body_dir) if name.endswith(".json"))
if names != ["1.json", "2.json", "3.json", "4.json"]:
    raise SystemExit("FAIL: stub files are %r" % (names,))
note = os.environ["NOTE_TEXT"]
reader = note + "\n\nbuild a reader"
want = [reader, note, note, reader]
allowed = {"local", "user-subscription"}
for name, expected in zip(names, want):
    payload = json.load(open(os.path.join(body_dir, name)))
    if payload.get("model") not in allowed or payload.get("model") != "local":
        raise SystemExit("FAIL: stub model class is %r" % (payload.get("model"),))
    messages = payload.get("messages")
    if not isinstance(messages, list) or len(messages) != 1:
        raise SystemExit("FAIL: stub messages are %r" % (messages,))
    if messages[0].get("content") != expected:
        raise SystemExit("FAIL: %s content is %r" % (name, messages[0].get("content")))
paths = [line.strip() for line in open(path_file).read().splitlines() if line.strip()]
if paths != ["POST /v1/chat/completions"] * 4:
    raise SystemExit("FAIL: stub paths are %r" % (paths,))
headers = open(header_file).read().lower()
if "authorization" in headers or "bearer" in headers or "supabase.co" in headers:
    raise SystemExit("FAIL: stub saw an authorization header")
session = sorted(os.listdir(work))
if session != ["blank-ask.txt", "confirmed-ran", "confirmed.txt", "held-reader.txt", "plain.txt"]:
    raise SystemExit("FAIL: session files are %r" % (session,))
PY
echo "check-note-ask: stub recorded the note, a blank line, and the ask"

cmp -s "$TH/note-before.json" "$STATE/knowledge/${PAPER_ID}.json" || {
  echo "FAIL: drafting changed the note"
  exit 1
}
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
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
if env.get("MESHD_TOKEN") != "throwaway":
    sys.exit("FAIL: daemon token is not the spare value")
if env.get("AI_GATEWAY_API_KEY"):
    sys.exit("FAIL: gateway key is set on the daemon")
state = os.environ["STATE"]
home = os.environ["HOME_DIR"]
if os.path.commonpath([state, home]) == home:
    sys.exit("FAIL: MESHD_STATE is inside the daemon home")
if state.startswith("/home/") or state.startswith("/Users/"):
    sys.exit("FAIL: MESHD_STATE is inside a home directory")
if bad:
    sys.exit("FAIL: daemon has a non-loopback socket: %s" % ", ".join(bad))
PY
fi

echo "check-note-ask: OK"

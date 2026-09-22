#!/bin/sh
# Spare daemon on 127.0.0.1:8898: POST /agent-note with q and no id selects
# one note through listNotes. One match drafts. Zero is 404. Two or more is
# 409. A remote query and an empty q are 400. None of those call the model.
# A pairing-code note or a hosts.json note is held. A unique paper match
# writes one relative file, mode 600, and does not execute it. id without q
# still drafts. This script does not use port 8899 or a real home directory.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
unset AI_GATEWAY_API_KEY
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH

if command -v bun >/dev/null 2>&1; then
  RUNNER=bun
elif command -v node >/dev/null 2>&1; then
  RUNNER=node
else
  echo "FAIL: bun or node is required"
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

run_ts() {
  if [ "$RUNNER" = "bun" ]; then
    bun "$@"
  else
    node --experimental-strip-types "$@"
  fi
}

calls="$(grep -c 'await handleKnowledge(' "$ROOT/install/payload/meshd/server.ts" || true)"
[ "$calls" = "1" ] || { echo "FAIL: server.ts must call handleKnowledge once"; exit 1; }
grep -q 'handleAgentNote' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route agent-note"
  exit 1
}
grep -q 'listNotes(' "$ROOT/install/payload/meshd/agent-note.ts" || {
  echo "FAIL: agent-note does not use listNotes"
  exit 1
}
if grep -n 'readdir(' "$ROOT/install/payload/meshd/agent-note.ts"; then
  echo "FAIL: agent-note added a second search"
  exit 1
fi
if grep -E -n 'supabase|ai-gateway' \
  "$ROOT/install/payload/meshd/agent-note.ts" \
  "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: note path names supabase or the AI gateway"
  exit 1
fi
call_name="$(printf '%s%s' 'liveGateway' 'Call')"
if grep -q "$call_name" \
  "$ROOT/install/payload/meshd/agent-note.ts" \
  "$ROOT/install/payload/meshd/knowledge.ts" \
  "$0"; then
  echo "FAIL: gateway call is named"
  exit 1
fi

run_ts -e '
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
echo "check-query-note-draft: model class is local or user-subscription"

fixture_text() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["text"], end="")' \
    "$ROOT/experiments/jev-routing/fixtures.json" "$1"
}
PAIRING="$(fixture_text sendPairingCode)"
HOSTS="$(fixture_text copyHosts)"
PAPER="$(fixture_text summarizePaper)"
[ -n "$PAIRING" ] && [ -n "$HOSTS" ] && [ -n "$PAPER" ] || {
  echo "FAIL: routing fixtures are missing"
  exit 1
}

TH="$(mktemp -d)"
HOME_DIR="$TH/home"
STATE="$TH/state"
WORK="$TH/session"
LOG="$TH/meshd.log"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
PORT=8898
SRV=
STUB=
MESH_MARK="${HOME}/.mesh"
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
printf '%s\n' 'Draft of the matching paper.' > "$TH/assistant.txt"
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
echo "check-query-note-draft: model stub is on 127.0.0.1:${STUB_PORT}"

if [ "$RUNNER" = "bun" ]; then
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
else
  MESHD_PORT="$PORT" \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$STATE" \
  MESHD_TELEMETRY=off \
  MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
  MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
  MESHD_KB_PATH="$TH/kb.sqlite" \
  HOME="$HOME_DIR" \
  node --experimental-strip-types install/payload/meshd/server.ts >"$LOG" 2>&1 &
fi
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

post_note() {
  pdf="$1"
  out="$2"
  python3 - "$TH/post-req.json" "$pdf" <<'PY'
import json, sys
json.dump({"path": sys.argv[2]}, open(sys.argv[1], "w"))
PY
  code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/post-req.json" \
    "http://127.0.0.1:$PORT/knowledge" || true)"
  [ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$out"; exit 1; }
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$out"
}

replace_body() {
  id="$1"
  text="$2"
  out="$3"
  BODY="$text" python3 - "$TH/body-req.json" <<'PY'
import json, os, sys
json.dump({"body": os.environ["BODY"]}, open(sys.argv[1], "w"))
PY
  code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/body-req.json" \
    "http://127.0.0.1:$PORT/knowledge/${id}" || true)"
  [ "$code" = "200" ] || { echo "FAIL: replace note -> ${code}"; cat "$out"; exit 1; }
}

write_pdf "Spare note" "$TH/spare.pdf"
write_pdf "Pairing paper" "$TH/pairing.pdf"
write_pdf "Hosts paper" "$TH/hosts.pdf"
write_pdf "Paper note" "$TH/paper.pdf"
SPARE_ID="$(post_note "$TH/spare.pdf" "$TH/spare-post.json")"
PAIR_ID="$(post_note "$TH/pairing.pdf" "$TH/pairing-post.json")"
HOST_ID="$(post_note "$TH/hosts.pdf" "$TH/hosts-post.json")"
PAPER_ID="$(post_note "$TH/paper.pdf" "$TH/paper-post.json")"
replace_body "$SPARE_ID" "A local spare page" "$TH/spare-body.json"
replace_body "$PAIR_ID" "$PAIRING" "$TH/pairing-body.json"
replace_body "$HOST_ID" "$HOSTS" "$TH/hosts-body.json"
replace_body "$PAPER_ID" "$PAPER" "$TH/paper-body.json"
[ "$(stub_hits)" = "0" ] || { echo "FAIL: ingest called the model"; exit 1; }
echo "check-query-note-draft: four local notes are stored"

MODEL="http://127.0.0.1:${STUB_PORT}/v1"

write_query() {
  dest="$1"
  query="$2"
  python3 - "$dest" "$query" "$WORK" "$MODEL" <<'PY'
import json, sys
json.dump({
    "q": sys.argv[2],
    "cwd": sys.argv[3],
    "model": sys.argv[4],
    "command": "touch unconfirmed-ran",
    "confirm": False,
}, open(sys.argv[1], "w"))
PY
}

expect_error() {
  label="$1"
  query="$2"
  want_code="$3"
  want_error="$4"
  write_query "$TH/err-req.json" "$query"
  code="$(post_agent "$TH/err.json" "$TH/err-req.json")"
  [ "$code" = "$want_code" ] || { echo "FAIL: ${label} -> ${code}"; cat "$TH/err.json"; echo; exit 1; }
  python3 - "$TH/err.json" "$want_error" "$PAIR_ID" "$HOST_ID" "$PAPER_ID" "$SPARE_ID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if set(data) != {"error"} or data.get("error") != sys.argv[2]:
    raise SystemExit("FAIL: error body is %r" % (data,))
raw = open(sys.argv[1]).read()
for ident in sys.argv[3:]:
    if ident and ident in raw:
        raise SystemExit("FAIL: error body guessed a note")
if "draft" in data or "notes" in data:
    raise SystemExit("FAIL: error body selected a note")
PY
}

expect_error "empty q" "" 400 "q required"
expect_error "blank q" "   " 400 "q required"
expect_error "no match" "zzzz-no-note" 404 "note not found"
expect_error "several matches" "paper" 409 "more than one note"
expect_error "remote url" "http://127.0.0.1:${STUB_PORT}/v1/chat/completions" 400 "query must be local text"
expect_error "https url" "https://example.invalid/paper" 400 "query must be local text"
expect_error "file url" "file:///tmp/paper" 400 "query must be local text"
expect_error "protocol-relative" "//example.invalid/paper" 400 "query must be local text"
expect_error "embedded separator" "notes :// stay" 400 "query must be local text"
expect_error "file scheme" "file:paper" 400 "query must be local text"
expect_error "mailto scheme" "mailto:paper@example.invalid" 400 "query must be local text"

python3 - "$TH/missing-req.json" "$WORK" "$MODEL" <<'PY'
import json, sys
json.dump({"cwd": sys.argv[2], "model": sys.argv[3]}, open(sys.argv[1], "w"))
PY
code="$(post_agent "$TH/missing.json" "$TH/missing-req.json")"
[ "$code" = "400" ] || { echo "FAIL: missing id and q -> ${code}"; exit 1; }
[ "$(stub_hits)" = "0" ] || { echo "FAIL: a refused query called the model"; exit 1; }
echo "check-query-note-draft: empty, remote, missing, and ambiguous queries did not call the model"

held_query() {
  label="$1"
  query="$2"
  write_query "$TH/held-req.json" "$query"
  code="$(post_agent "$TH/held.json" "$TH/held-req.json")"
  [ "$code" = "200" ] || { echo "FAIL: ${label} -> ${code}"; cat "$TH/held.json"; echo; exit 1; }
  python3 - "$TH/held.json" "$label" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
allowed = {"local", "user-subscription"}
if data.get("modelClass") not in allowed or data.get("modelClass") != "local":
    raise SystemExit("FAIL: %s modelClass is %r" % (sys.argv[2], data.get("modelClass")))
if data.get("held") is not True or data.get("commandRan") is not False:
    raise SystemExit("FAIL: %s was not held" % sys.argv[2])
if data.get("draft") is not None:
    raise SystemExit("FAIL: %s drafted %r" % (sys.argv[2], data.get("draft")))
raw = open(sys.argv[1]).read()
for needle in ("127.0.0.1", "http", "supabase", "chat/completions"):
    if needle in raw:
        raise SystemExit("FAIL: %s transcript contains %s" % (sys.argv[2], needle))
PY
}

held_query "pairing code" "pairing code"
held_query "hosts.json" "hosts.json"
[ "$(stub_hits)" = "0" ] || { echo "FAIL: a held note called the model"; exit 1; }
[ ! -e "$WORK/unconfirmed-ran" ] || { echo "FAIL: held query ran a command"; exit 1; }
if [ -n "$(find "$WORK" -type f -print)" ]; then
  echo "FAIL: held query wrote a file"
  exit 1
fi
echo "check-query-note-draft: pairing code was held and the model was not called"
echo "check-query-note-draft: hosts.json was held and the model was not called"

draft_query() {
  label="$1"
  query="$2"
  file="$3"
  marker="$4"
  python3 - "$TH/draft-req.json" "$query" "$WORK" "$MODEL" "$file" "$marker" <<'PY'
import json, sys
json.dump({
    "q": sys.argv[2],
    "cwd": sys.argv[3],
    "model": sys.argv[4],
    "file": sys.argv[5],
    "command": "touch " + sys.argv[6],
    "confirm": False,
}, open(sys.argv[1], "w"))
PY
  code="$(post_agent "$TH/draft.json" "$TH/draft-req.json")"
  [ "$code" = "200" ] || { echo "FAIL: ${label} -> ${code}"; cat "$TH/draft.json"; echo; tail -n 40 "$LOG"; exit 1; }
  PAPER="$PAPER" PAIRING="$PAIRING" HOSTS="$HOSTS" \
  python3 - "$TH/draft.json" "$WORK/$file" "$TH/assistant.txt" "$label" <<'PY'
import json, os, stat, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
label = sys.argv[4]
allowed = {"local", "user-subscription"}
if data.get("modelClass") not in allowed or data.get("modelClass") != "local":
    raise SystemExit("FAIL: %s modelClass is %r" % (label, data.get("modelClass")))
if data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: %s command was not held" % label)
if data.get("draft") != os.path.basename(sys.argv[2]):
    raise SystemExit("FAIL: %s draft name is %r" % (label, data.get("draft")))
if os.path.isabs(str(data.get("draft"))):
    raise SystemExit("FAIL: %s draft is absolute" % label)
for needle in ("127.0.0.1", "http", "supabase", "chat/completions"):
    if needle in raw:
        raise SystemExit("FAIL: %s transcript contains %s" % (label, needle))
assistant = open(sys.argv[3]).read()
draft = open(sys.argv[2]).read()
if draft != assistant:
    raise SystemExit("FAIL: %s file is not the stub reply" % label)
mode = stat.S_IMODE(os.stat(sys.argv[2]).st_mode)
if mode != 0o600:
    raise SystemExit("FAIL: %s mode is %o" % (label, mode))
if mode & 0o111:
    raise SystemExit("FAIL: %s file is executable" % label)
paper = os.environ["PAPER"]
if paper not in assistant and paper == "":
    raise SystemExit("FAIL: paper fixture is empty")
PY
  [ ! -e "$WORK/$marker" ] || { echo "FAIL: ${label} ran a command"; exit 1; }
}

draft_query "paper title" "Paper note" "held-paper.txt" "unconfirmed-ran"
[ "$(stub_hits)" = "1" ] || { echo "FAIL: paper query called the model $(stub_hits) times"; exit 1; }
held_mode="$(mode_of "$WORK/held-paper.txt")"
[ "$held_mode" = "600" ] || { echo "FAIL: held file mode is $held_mode, want 600"; exit 1; }
echo "check-query-note-draft: unique paper match drafted one relative file mode 600"
echo "check-query-note-draft: held file was not executed"
echo "check-query-note-draft: command without confirm did not run"

draft_query "summarize this paper" "summarize this paper" "summary.txt" "summary-ran"
[ "$(stub_hits)" = "2" ] || { echo "FAIL: summarize query called the model $(stub_hits) times"; exit 1; }
echo "check-query-note-draft: unique summarize match drafted"

python3 - "$TH/id-req.json" "$PAPER_ID" "$WORK" "$MODEL" <<'PY'
import json, sys
json.dump({
    "id": sys.argv[2],
    "cwd": sys.argv[3],
    "model": sys.argv[4],
    "file": "by-id.txt",
    "command": "touch id-ran",
    "confirm": False,
}, open(sys.argv[1], "w"))
PY
code="$(post_agent "$TH/id.json" "$TH/id-req.json")"
[ "$code" = "200" ] || { echo "FAIL: id without q -> ${code}"; cat "$TH/id.json"; echo; exit 1; }
python3 - "$TH/id.json" "$WORK/by-id.txt" "$TH/assistant.txt" <<'PY'
import json, os, stat, sys
data = json.load(open(sys.argv[1]))
if data.get("modelClass") != "local" or data.get("draft") != "by-id.txt":
    raise SystemExit("FAIL: id draft is %r" % (data,))
if data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: id command was not held")
mode = stat.S_IMODE(os.stat(sys.argv[2]).st_mode)
if mode != 0o600 or mode & 0o111:
    raise SystemExit("FAIL: id file mode is %o" % mode)
if open(sys.argv[2]).read() != open(sys.argv[3]).read():
    raise SystemExit("FAIL: id file is not the stub reply")
PY
[ ! -e "$WORK/id-ran" ] || { echo "FAIL: id command ran without confirm"; exit 1; }
[ "$(stub_hits)" = "3" ] || { echo "FAIL: id path called the model $(stub_hits) times"; exit 1; }
echo "check-query-note-draft: id without q still drafted"

PAPER="$PAPER" PAIRING="$PAIRING" HOSTS="$HOSTS" python3 - "$TH/stub-bodies" "$TH/stub.path" "$TH/stub.headers" "$WORK" <<'PY'
import json, os, sys
body_dir, path_file, header_file, work = sys.argv[1:5]
names = sorted(name for name in os.listdir(body_dir) if name.endswith(".json"))
if names != ["1.json", "2.json", "3.json"]:
    raise SystemExit("FAIL: stub files are %r" % (names,))
allowed = {"local", "user-subscription"}
paper = os.environ["PAPER"]
pairing = os.environ["PAIRING"]
hosts = os.environ["HOSTS"]
for name in names:
    payload = json.load(open(os.path.join(body_dir, name)))
    if payload.get("model") not in allowed or payload.get("model") != "local":
        raise SystemExit("FAIL: stub model class is %r" % (payload.get("model"),))
    messages = json.dumps(payload.get("messages"))
    if paper not in messages:
        raise SystemExit("FAIL: stub did not receive the paper note")
    if pairing in messages or hosts in messages:
        raise SystemExit("FAIL: stub received a secret note")
paths = [line.strip() for line in open(path_file).read().splitlines() if line.strip()]
if paths != ["/v1/chat/completions"] * 3 and paths != ["POST /v1/chat/completions"] * 3:
    raise SystemExit("FAIL: stub paths are %r" % (paths,))
headers = open(header_file).read().lower()
if "authorization" in headers or "bearer" in headers or "supabase.co" in headers:
    raise SystemExit("FAIL: stub saw an authorization header")
session = sorted(os.listdir(work))
if session != ["by-id.txt", "held-paper.txt", "summary.txt"]:
    raise SystemExit("FAIL: session files are %r" % (session,))
PY

PAIR_FILE="$STATE/knowledge/${PAIR_ID}.json"
HOST_FILE="$STATE/knowledge/${HOST_ID}.json"
PAPER_FILE="$STATE/knowledge/${PAPER_ID}.json"
cp "$PAIR_FILE" "$TH/pairing-after.json"
cp "$HOST_FILE" "$TH/hosts-after.json"
cp "$PAPER_FILE" "$TH/paper-after.json"
python3 - "$PAIR_FILE" "$HOST_FILE" "$PAPER_FILE" "$PAIRING" "$HOSTS" "$PAPER" <<'PY'
import json, sys
pairs = [
    (sys.argv[1], sys.argv[4], "pairing"),
    (sys.argv[2], sys.argv[5], "hosts"),
    (sys.argv[3], sys.argv[6], "paper"),
]
for path, text, label in pairs:
    body = json.load(open(path)).get("body")
    if body != text:
        raise SystemExit("FAIL: %s note body changed" % label)
PY

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
if env.get("AI_GATEWAY_API_KEY"):
    sys.exit("FAIL: gateway key is set on the daemon")
if bad:
    sys.exit("FAIL: daemon has a non-loopback socket: %s" % ", ".join(bad))
PY
fi

echo "check-query-note-draft: OK"

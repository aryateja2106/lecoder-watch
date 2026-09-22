#!/bin/sh
# Spare daemon on 127.0.0.1:8898: GET /knowledge still lists every note as
# {id, title}. GET /knowledge?q=paper matches a title or a body, still
# without bodies. No match is an empty list. A remote URL, a
# scheme, a protocol-relative value, or any string containing :// is refused.
# A pairing-code body and a hosts.json body are not selected into a draft,
# and the loopback model is not called for them. The matching paper note is
# drafted by POST /agent-note into one held file, mode 600, and is not
# executed. A command without confirm does not run. The model class is only
# local or user-subscription. This script does not use port 8899, does not
# read a real home directory, and does not prove a microphone or a speaker.
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
grep -q 'handleAgentNote' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route agent-note"
  exit 1
}
if grep -E -q 'child_process|Bun\.spawn|execFile\(' "$ROOT/experiments/note-route-draft/draft.ts"; then
  echo "FAIL: draft module can run a file"
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

run_ts -e '
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
echo "check-local-note-search: model class is local or user-subscription"

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

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(n) if n else b""
        names = [name for name in os.listdir(body_dir) if name.endswith(".json")]
        with open(os.path.join(body_dir, "%d.json" % (len(names) + 1)), "wb") as fh:
            fh.write(raw)
        with open(path_file, "a") as fh:
            fh.write(self.path + "\n")
        with open(header_file, "a") as fh:
            fh.write(str(self.headers))
            fh.write("\n")
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
echo "check-local-note-search: model stub is on 127.0.0.1:${STUB_PORT}"

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
  [ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; exit 1; }
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
  [ "$code" = "200" ] || { echo "FAIL: replace note -> ${code}"; exit 1; }
}

write_pdf "Spare note" "$TH/spare.pdf"
write_pdf "Pairing paper" "$TH/pairing.pdf"
write_pdf "Hosts paper" "$TH/hosts.pdf"
write_pdf "Paper note" "$TH/paper.pdf"
SPARE_ID="$(post_note "$TH/spare.pdf" "$TH/spare-post.json")"
PAIR_ID="$(post_note "$TH/pairing.pdf" "$TH/pairing-post.json")"
HOST_ID="$(post_note "$TH/hosts.pdf" "$TH/hosts-post.json")"
PAPER_ID="$(post_note "$TH/paper.pdf" "$TH/paper-post.json")"
[ "$(stub_hits)" = "0" ] || { echo "FAIL: ingest called the model"; exit 1; }

replace_body "$SPARE_ID" "A local spare page" "$TH/spare-body.json"
replace_body "$PAIR_ID" "$PAIRING" "$TH/pairing-body.json"
replace_body "$HOST_ID" "$HOSTS" "$TH/hosts-body.json"
replace_body "$PAPER_ID" "$PAPER" "$TH/paper-body.json"
[ "$(stub_hits)" = "0" ] || { echo "FAIL: replace called the model"; exit 1; }
echo "check-local-note-search: four local notes are stored"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; exit 1; }
python3 - "$TH/list.json" "$SPARE_ID" "$PAIR_ID" "$HOST_ID" "$PAPER_ID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
notes = data.get("notes")
if not isinstance(notes, list) or len(notes) != 4:
    raise SystemExit("FAIL: unfiltered list is %r" % (notes,))
want = {
    sys.argv[2]: "Spare note",
    sys.argv[3]: "Pairing paper",
    sys.argv[4]: "Hosts paper",
    sys.argv[5]: "Paper note",
}
got = {}
for note in notes:
    if set(note.keys()) != {"id", "title"}:
        raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
    got[note.get("id")] = note.get("title")
if got != want:
    raise SystemExit("FAIL: list notes are %r" % (got,))
PY
if grep -q "$PAIRING" "$TH/list.json" || grep -q "$HOSTS" "$TH/list.json" || grep -q "$PAPER" "$TH/list.json"; then
  echo "FAIL: GET /knowledge returned a body"
  exit 1
fi
echo "check-local-note-search: list is titles only"

code="$(curl -G --connect-timeout 1 --max-time 5 -sS -o "$TH/blank.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  --data-urlencode "q=" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: blank query -> ${code}"; exit 1; }
python3 - "$TH/blank.json" <<'PY'
import json, sys
notes = json.load(open(sys.argv[1])).get("notes")
if not isinstance(notes, list) or len(notes) != 4:
    raise SystemExit("FAIL: blank query did not return every note")
PY

code="$(curl -G --connect-timeout 1 --max-time 5 -sS -o "$TH/search.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  --data-urlencode "q=paper" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge?q=paper -> ${code}"; exit 1; }
python3 - "$TH/search.json" "$PAIR_ID" "$HOST_ID" "$PAPER_ID" "$SPARE_ID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
notes = data.get("notes")
if not isinstance(notes, list) or len(notes) != 3:
    raise SystemExit("FAIL: paper search is %r" % (notes,))
want = {
    sys.argv[2]: "Pairing paper",
    sys.argv[3]: "Hosts paper",
    sys.argv[4]: "Paper note",
}
got = {}
for note in notes:
    if set(note.keys()) != {"id", "title"}:
        raise SystemExit("FAIL: search note keys are %r" % (sorted(note.keys()),))
    if note.get("id") == sys.argv[5]:
        raise SystemExit("FAIL: search returned the spare note")
    got[note.get("id")] = note.get("title")
if got != want:
    raise SystemExit("FAIL: search notes are %r" % (got,))
titles = [note.get("title", "") for note in notes]
if titles != sorted(titles):
    raise SystemExit("FAIL: search order is %r" % (titles,))
PY
if grep -q "$PAIRING" "$TH/search.json" || grep -q "$HOSTS" "$TH/search.json" || grep -q "$PAPER" "$TH/search.json"; then
  echo "FAIL: title search returned a body"
  exit 1
fi
echo "check-local-note-search: q=paper returns matching titles"

code="$(curl -G --connect-timeout 1 --max-time 5 -sS -o "$TH/none.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  --data-urlencode "q=zzzz-no-title" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: missing title -> ${code}"; exit 1; }
python3 - "$TH/none.json" <<'PY'
import json, sys
notes = json.load(open(sys.argv[1])).get("notes")
if notes != []:
    raise SystemExit("FAIL: missing title returned %r" % (notes,))
PY
echo "check-local-note-search: no match is an empty list"

code="$(curl -G --connect-timeout 1 --max-time 5 -sS -o "$TH/bodyq.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  --data-urlencode "q=SUMMARIZE" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: body word search -> ${code}"; exit 1; }
python3 - "$TH/bodyq.json" "$PAPER_ID" "$SPARE_ID" "$PAIR_ID" "$HOST_ID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
notes = data.get("notes")
if not isinstance(notes, list) or len(notes) != 1:
    raise SystemExit("FAIL: body search is %r" % (notes,))
note = notes[0]
if set(note.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: body match keys are %r" % (sorted(note.keys()),))
if note.get("id") != sys.argv[2] or note.get("title") != "Paper note":
    raise SystemExit("FAIL: body match is %r" % (note,))
if note.get("id") in (sys.argv[3], sys.argv[4], sys.argv[5]):
    raise SystemExit("FAIL: body search returned another note")
PY
if grep -q "$PAPER" "$TH/bodyq.json" || grep -q "$PAIRING" "$TH/bodyq.json" || grep -q "$HOSTS" "$TH/bodyq.json"; then
  echo "FAIL: body search returned a body"
  exit 1
fi
echo "check-local-note-search: a body match is returned as id and title"

code="$(curl -G --connect-timeout 1 --max-time 5 -sS -o "$TH/pairq.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  --data-urlencode "q=send the" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: pairing body search -> ${code}"; exit 1; }
python3 - "$TH/pairq.json" "$PAIR_ID" <<'PY'
import json, sys
notes = json.load(open(sys.argv[1])).get("notes")
if not isinstance(notes, list) or len(notes) != 1:
    raise SystemExit("FAIL: pairing search is %r" % (notes,))
note = notes[0]
if set(note.keys()) != {"id", "title"} or note.get("id") != sys.argv[2] or note.get("title") != "Pairing paper":
    raise SystemExit("FAIL: pairing search note is %r" % (note,))
PY
if grep -q "$PAIRING" "$TH/pairq.json"; then
  echo "FAIL: pairing search returned the body"
  exit 1
fi
echo "check-local-note-search: pairing search did not return the body"

code="$(curl -G --connect-timeout 1 --max-time 5 -sS -o "$TH/hostq.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  --data-urlencode "q=hosts.json" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: hosts body search -> ${code}"; exit 1; }
python3 - "$TH/hostq.json" "$HOST_ID" <<'PY'
import json, sys
notes = json.load(open(sys.argv[1])).get("notes")
if not isinstance(notes, list) or len(notes) != 1:
    raise SystemExit("FAIL: hosts search is %r" % (notes,))
note = notes[0]
if set(note.keys()) != {"id", "title"} or note.get("id") != sys.argv[2] or note.get("title") != "Hosts paper":
    raise SystemExit("FAIL: hosts search note is %r" % (note,))
PY
if grep -q "$HOSTS" "$TH/hostq.json"; then
  echo "FAIL: hosts search returned the body"
  exit 1
fi
echo "check-local-note-search: hosts.json search did not return the body"

refuse_query() {
  label="$1"
  query="$2"
  code="$(curl -G --connect-timeout 1 --max-time 5 -sS -o "$TH/bad.json" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    --data-urlencode "q=${query}" \
    "http://127.0.0.1:$PORT/knowledge" || true)"
  [ "$code" = "400" ] || { echo "FAIL: ${label} -> ${code}"; exit 1; }
  python3 - "$TH/bad.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("error") != "query must be local text" or "notes" in data:
    raise SystemExit("FAIL: refused query returned %r" % (data,))
PY
}
refuse_query "remote url" "http://example.invalid/paper"
refuse_query "https url" "https://example.invalid/paper"
refuse_query "file url" "file:///tmp/paper"
refuse_query "protocol-relative" "//example.invalid/paper"
refuse_query "embedded separator" "notes :// stay"
refuse_query "file scheme" "file:paper"
refuse_query "mailto scheme" "mailto:paper@example.invalid"
[ "$(stub_hits)" = "0" ] || { echo "FAIL: a refused query called the model"; exit 1; }
echo "check-local-note-search: remote queries are refused"

PAIR_FILE="$STATE/knowledge/${PAIR_ID}.json"
HOST_FILE="$STATE/knowledge/${HOST_ID}.json"
PAPER_FILE="$STATE/knowledge/${PAPER_ID}.json"
cp "$PAIR_FILE" "$TH/pairing.json"
cp "$HOST_FILE" "$TH/hosts.json"
cp "$PAPER_FILE" "$TH/paper.json"

cat > "$TH/select.ts" <<'TS'
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const root = process.argv[2];
const paperId = process.argv[3];
const pairingPath = process.argv[4];
const hostsPath = process.argv[5];
const paperPath = process.argv[6];

function fail(message: string): never {
  console.error("FAIL: " + message);
  process.exit(1);
}

if (process.env.AI_GATEWAY_API_KEY) fail("gateway key is set");

const routeMod = await import(pathToFileURL(join(root, "experiments/jev-routing/route.ts")).href);
const filterMod = await import(pathToFileURL(join(root, "experiments/jev-routing/filter.ts")).href);
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
  if (typeof note.id !== "string" || typeof note.title !== "string" || typeof note.body !== "string") {
    fail("stored note has no body");
  }
  return note;
}

const pairingText = process.env.PAIRING ?? "";
const hostsText = process.env.HOSTS ?? "";
const paperText = process.env.PAPER ?? "";
const pairing = noteOf(pairingPath);
const hosts = noteOf(hostsPath);
const paper = noteOf(paperPath);
if (pairing.body !== pairingText) fail("stored pairing body is not the fixture");
if (hosts.body !== hostsText) fail("stored hosts body is not the fixture");
if (paper.body !== paperText || paper.id !== paperId) fail("stored paper body is not the fixture");

let drafted = "";
for (const note of [pairing, hosts, paper]) {
  const decision = route(filter(note), allow);
  const secret = String(note.body).includes("pairing code") || String(note.body).includes("hosts.json");
  if (secret) {
    if (decision !== "hold-for-review") fail("secret note was selected");
    continue;
  }
  if (decision !== "allow-local-tool") fail("paper note was held");
  if (drafted) fail("more than one note was selected");
  drafted = String(note.id);
}
if (drafted !== paperId) fail("the selected note is not the paper");
process.stdout.write(drafted);
TS

if [ "$RUNNER" = "bun" ]; then
  SELECTED="$(PAIRING="$PAIRING" HOSTS="$HOSTS" PAPER="$PAPER" \
    bun "$TH/select.ts" "$ROOT" "$PAPER_ID" "$TH/pairing.json" "$TH/hosts.json" "$TH/paper.json")"
else
  SELECTED="$(PAIRING="$PAIRING" HOSTS="$HOSTS" PAPER="$PAPER" \
    node --experimental-strip-types "$TH/select.ts" "$ROOT" "$PAPER_ID" "$TH/pairing.json" "$TH/hosts.json" "$TH/paper.json")"
fi
[ "$SELECTED" = "$PAPER_ID" ] || { echo "FAIL: selector returned another note"; exit 1; }
[ "$(stub_hits)" = "0" ] || { echo "FAIL: pairing or hosts called the model"; exit 1; }
echo "check-local-note-search: pairing code stayed out of the draft"
echo "check-local-note-search: hosts.json stayed out of the draft"

python3 - "$TH/job.json" "$PAPER_ID" "$WORK" "$STUB_PORT" <<'PY'
import json, sys
json.dump({
    "id": sys.argv[2],
    "cwd": sys.argv[3],
    "model": "http://127.0.0.1:%s/v1" % sys.argv[4],
    "file": "held-paper.txt",
    "command": "touch draft-executed",
    "confirm": False,
}, open(sys.argv[1], "w"))
PY
code="$(curl --connect-timeout 1 --max-time 12 -sS -o "$TH/draft.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/job.json" \
  "http://127.0.0.1:$PORT/agent-note" || true)"
[ "$code" = "200" ] || { echo "FAIL: POST /agent-note -> ${code}"; exit 1; }
PAPER="$PAPER" PAIRING="$PAIRING" HOSTS="$HOSTS" \
python3 - "$TH/draft.json" "$WORK/held-paper.txt" "$TH/stub-bodies" "$TH/stub.path" "$TH/stub.headers" "$TH/assistant.txt" "$WORK" <<'PY'
import json, os, stat, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
allowed = {"local", "user-subscription"}
if data.get("modelClass") not in allowed or data.get("modelClass") != "local":
    raise SystemExit("FAIL: modelClass is %r" % (data.get("modelClass"),))
if data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: unconfirmed command was not held")
if data.get("draft") != "held-paper.txt":
    raise SystemExit("FAIL: draft name is %r" % (data.get("draft"),))
for needle in ("127.0.0.1", "http", "supabase", "chat/completions"):
    if needle in raw:
        raise SystemExit("FAIL: transcript contains %s" % needle)
assistant = open(sys.argv[6]).read()
draft = open(sys.argv[2]).read()
if draft != assistant:
    raise SystemExit("FAIL: held file is not the stub reply")
mode = stat.S_IMODE(os.stat(sys.argv[2]).st_mode)
if mode != 0o600:
    raise SystemExit("FAIL: held file mode is %o" % mode)
if mode & 0o111:
    raise SystemExit("FAIL: held file is executable")
names = sorted(name for name in os.listdir(sys.argv[3]) if name.endswith(".json"))
if names != ["1.json"]:
    raise SystemExit("FAIL: stub files are %r" % (names,))
payload = json.load(open(os.path.join(sys.argv[3], "1.json")))
if payload.get("model") not in allowed or payload.get("model") != "local":
    raise SystemExit("FAIL: stub model class is %r" % (payload.get("model"),))
messages = json.dumps(payload.get("messages"))
paper = os.environ["PAPER"]
pairing = os.environ["PAIRING"]
hosts = os.environ["HOSTS"]
if paper not in messages:
    raise SystemExit("FAIL: stub did not receive the paper note")
if pairing in messages or hosts in messages:
    raise SystemExit("FAIL: stub received a secret note")
paths = [line.strip() for line in open(sys.argv[4]).read().splitlines() if line.strip()]
if paths != ["/v1/chat/completions"]:
    raise SystemExit("FAIL: stub path is not the completions endpoint")
headers = open(sys.argv[5]).read().lower()
if "authorization" in headers or "bearer" in headers or "supabase.co" in headers:
    raise SystemExit("FAIL: stub saw an authorization header")
session = sorted(os.listdir(sys.argv[7]))
if session != ["held-paper.txt"]:
    raise SystemExit("FAIL: session files are %r" % (session,))
if os.path.exists(os.path.join(sys.argv[7], "draft-executed")):
    raise SystemExit("FAIL: held file was executed")
PY
[ ! -e "$WORK/draft-executed" ] || { echo "FAIL: unconfirmed command ran"; exit 1; }
[ "$(stub_hits)" = "1" ] || { echo "FAIL: model was called $(stub_hits) times"; exit 1; }
held_mode="$(mode_of "$WORK/held-paper.txt")"
[ "$held_mode" = "600" ] || { echo "FAIL: held file mode is $held_mode, want 600"; exit 1; }
cmp -s "$PAIR_FILE" "$TH/pairing.json" || { echo "FAIL: draft rewrote the pairing note"; exit 1; }
cmp -s "$HOST_FILE" "$TH/hosts.json" || { echo "FAIL: draft rewrote the hosts note"; exit 1; }
cmp -s "$PAPER_FILE" "$TH/paper.json" || { echo "FAIL: draft rewrote the paper note"; exit 1; }
echo "check-local-note-search: agent drafted the matching paper note"
echo "check-local-note-search: held file is one relative path mode 600"
echo "check-local-note-search: held file was not executed"
echo "check-local-note-search: command without confirm did not run"

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

echo "check-local-note-search: OK"

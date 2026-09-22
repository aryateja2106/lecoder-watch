#!/bin/sh
# One local note is replaced in place, then drafted through a loopback model.
# The stub request contains the new body and not the old one. The held file
# is one relative path, mode 600, and it is not executed. A command without
# confirm does not run. A missing id does not call the model. A remote URL
# does not write. The model class is only local or user-subscription.
# The spare daemon is 127.0.0.1:8898. This script does not use port 8899
# or a real home directory.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

if grep -E -n 'supabase|ai-gateway' \
  "$ROOT/install/payload/meshd/agent-note.ts" \
  "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: note path names supabase or the AI gateway"
  exit 1
fi
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

# Classify in process. This does not open a socket.
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
echo "check-updated-note-draft: model class is local or user-subscription"

TH="$(mktemp -d)"
HOME_DIR="$TH/home"
STATE="$TH/state"
WORK="$TH/session"
PDF="$TH/paper.pdf"
LOG="$TH/meshd.log"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
PORT=8898
OLD='Old body stays until replaced'
NEW='New body is what the draft reads'
SRV=
STUB=

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

mkdir -p "$HOME_DIR" "$STATE" "$WORK"
chmod 700 "$HOME_DIR" "$STATE" "$WORK"

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
echo "check-updated-note-draft: model stub is on 127.0.0.1:${STUB_PORT}"

env -u AI_GATEWAY_API_KEY \
  MESHD_PORT=$PORT \
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
echo "check-updated-note-draft: spare daemon is on 127.0.0.1:${PORT}"

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
echo "check-updated-note-draft: one note stored the old body"

NEW="$NEW" python3 - "$TH/update.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"body": os.environ["NEW"]}))
PY
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/updated.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/update.json" \
  "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
[ "$code" = "200" ] || { echo "FAIL: POST /knowledge/:id -> ${code}"; cat "$TH/updated.json"; echo; cat "$LOG"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: update created a second note, found $(note_count)"; exit 1; }
OLD="$OLD" NEW="$NEW" python3 - "$NOTE_FILE" "$ID" <<'PY'
import json, os, sys
note = json.load(open(sys.argv[1]))
if note.get("id") != sys.argv[2]:
    raise SystemExit("FAIL: updated file id is %r" % (note.get("id"),))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: update changed the title to %r" % (note.get("title"),))
if note.get("body") != os.environ["NEW"]:
    raise SystemExit("FAIL: updated body is %r" % (note.get("body"),))
if os.environ["OLD"] in note.get("body", ""):
    raise SystemExit("FAIL: updated body still contains the old text")
PY
fmode="$(mode_of "$NOTE_FILE")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-updated-note-draft: note replaced in place"

post_note() {
  name="$1"
  out="$2"
  curl --connect-timeout 1 --max-time 12 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$name" \
    "http://127.0.0.1:$PORT/agent-note" || true
}

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
code="$(post_note "$TH/missing-req.json" "$TH/missing.json")"
[ "$code" = "404" ] || { echo "FAIL: missing note -> ${code}"; cat "$TH/missing.json"; echo; exit 1; }
python3 - "$TH/missing.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("error") != "note not found":
    raise SystemExit("FAIL: missing note error is %r" % (data.get("error"),))
PY
[ ! -e "$TH/stub.body" ] || { echo "FAIL: missing id called the model"; exit 1; }
[ ! -e "$WORK/missing-ran" ] || { echo "FAIL: missing id ran a command"; exit 1; }
[ ! -e "$WORK/held-note.txt" ] || { echo "FAIL: missing id wrote a file"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: missing id changed the note count"; exit 1; }
echo "check-updated-note-draft: missing id did not call the model"

cp "$NOTE_FILE" "$TH/frozen.json"
refuse_remote() {
  label="$1"
  payload="$2"
  python3 - "$TH/remote.json" "$payload" <<'PY'
import sys
open(sys.argv[1], "w").write(sys.argv[2])
PY
  code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/remote-out.json" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/remote.json" \
    "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
  cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: $label wrote the note"; exit 1; }
  [ "$(note_count)" = "1" ] || { echo "FAIL: $label created another note"; exit 1; }
  case "$code" in
    200|201) echo "FAIL: $label was stored ($code)"; cat "$TH/remote-out.json"; echo; exit 1 ;;
  esac
  echo "check-updated-note-draft: $label"
}
refuse_remote "remote url did not write" '{"body":"http://127.0.0.1:9/stolen"}'
refuse_remote "https url did not write" '{"body":"https://example.com/stolen"}'
refuse_remote "scheme url did not write" '{"body":"notes://stolen"}'
refuse_remote "protocol-relative url did not write" '{"body":"//127.0.0.1/stolen"}'

NOTE_ID="$ID" WORK="$WORK" python3 - "$TH/refuse-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": os.environ["NOTE_ID"],
    "cwd": os.environ["WORK"],
    "model": "ftp://files.example/v1",
    "file": "held-note.txt",
    "command": "touch " + os.environ["WORK"] + "/refused-ran",
    "confirm": True,
}))
PY
code="$(post_note "$TH/refuse-req.json" "$TH/refuse.json")"
[ "$code" = "400" ] || { echo "FAIL: remote model url -> ${code}"; cat "$TH/refuse.json"; echo; exit 1; }
python3 - "$TH/refuse.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("error") != "model url not allowed":
    raise SystemExit("FAIL: remote model url was not rejected")
PY
[ ! -e "$TH/stub.body" ] || { echo "FAIL: remote model url called the model"; exit 1; }
[ ! -e "$WORK/refused-ran" ] || { echo "FAIL: remote model url ran a command"; exit 1; }
[ ! -e "$WORK/held-note.txt" ] || { echo "FAIL: remote model url wrote a file"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: remote model url wrote the note"; exit 1; }
echo "check-updated-note-draft: remote model url did not write"

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
OLD="$OLD" NEW="$NEW" python3 - "$TH/job.json" "$WORK/held-note.txt" "$TH/stub.reply" "$TH/stub.body" "$TH/stub.path" "$TH/stub.headers" "$WORK" <<'PY'
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
if payload.get("model") not in ("local", "user-subscription"):
    raise SystemExit("FAIL: stub saw a model name that is not a class")
if payload.get("model") != "local":
    raise SystemExit("FAIL: stub model class is %r" % (payload.get("model"),))
messages = json.dumps(payload.get("messages"))
new = os.environ["NEW"]
old = os.environ["OLD"]
if new not in messages:
    raise SystemExit("FAIL: stub did not receive the new body")
if old in messages:
    raise SystemExit("FAIL: stub received the old body")
for needle in ("supabase", "http", "127.0.0.1"):
    if needle in messages:
        raise SystemExit("FAIL: stub body contains %s" % needle)
paths = [ln.strip() for ln in open(sys.argv[5]).read().splitlines() if ln.strip()]
if paths != ["/v1/chat/completions"]:
    raise SystemExit("FAIL: stub path is not the completions endpoint")
headers = open(sys.argv[6]).read().lower()
if "supabase.co" in headers or "authorization" in headers or "bearer" in headers:
    raise SystemExit("FAIL: stub saw supabase.co or an authorization header")
names = sorted(os.listdir(sys.argv[7]))
if names != ["held-note.txt"]:
    raise SystemExit("FAIL: session files are %r" % (names,))
if os.path.exists(os.path.join(sys.argv[7], "draft-executed")):
    raise SystemExit("FAIL: held file was executed")
PY
[ ! -e "$WORK/draft-executed" ] || { echo "FAIL: held file was executed"; exit 1; }
[ ! -e "$WORK/missing-ran" ] || { echo "FAIL: missing-id command ran later"; exit 1; }
[ ! -e "$WORK/refused-ran" ] || { echo "FAIL: remote model command ran later"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: draft wrote another note"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: draft rewrote the note"; exit 1; }
[ ! -d "$HOME_DIR/.mesh" ] || { echo "FAIL: daemon wrote under its home directory"; exit 1; }
echo "check-updated-note-draft: stub received the new body"
echo "check-updated-note-draft: held file is one relative path mode 600"
echo "check-updated-note-draft: held file was not executed"
echo "check-updated-note-draft: command without confirm did not run"

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
echo "check-updated-note-draft: no supabase.co call"
echo "check-updated-note-draft: OK"

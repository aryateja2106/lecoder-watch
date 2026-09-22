#!/bin/sh
# Spare daemon on 127.0.0.1:8898: a temp MESH_PDF prints one sentence that
# includes "summarize this paper". POST /knowledge {pdf, title} writes one
# note. GET /knowledge?q= returns {id, title} only. POST /agent-note with q
# and no id drafts that note to one relative file, mode 600, and does not
# execute it. A command without confirm does not run. The model class is
# only local or user-subscription. A second note whose body asks to send a
# pairing code, or to copy hosts.json, is held by the daemon's existing
# text check: no model call and no draft file. A remote MESH_PDF or a pdf
# value containing :// writes nothing. This script does not use port 8899,
# a real home directory, or the AI gateway, and it does not import the
# routing experiment. The stub is the proof. It does not prove a
# microphone, a speaker, or a PDF parser.
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
if grep -n 'experiments/jev-routing' \
  "$ROOT/install/payload/meshd/agent-note.ts" \
  "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: note path imports the routing experiment"
  exit 1
fi
if grep -E -n 'Bun\.spawn\(\[?"?(sh|bash|curl|wget)' "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: knowledge.ts spawns a shell or a downloader"
  exit 1
fi
grep -q 'MESH_PDF' "$ROOT/install/payload/meshd/knowledge.ts" || {
  echo "FAIL: knowledge.ts does not name MESH_PDF"
  exit 1
}
grep -F -q 'pairing\s+code' "$ROOT/install/payload/meshd/agent-note.ts" || {
  echo "FAIL: agent-note no longer holds a pairing code"
  exit 1
}
grep -F -q 'hosts\.json' "$ROOT/install/payload/meshd/agent-note.ts" || {
  echo "FAIL: agent-note no longer holds hosts.json"
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
echo "check-pdf-note-draft: model class is local or user-subscription"

fixture_text() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["text"], end="")' \
    "$ROOT/experiments/jev-routing/fixtures.json" "$1"
}
PAIRING="$(fixture_text sendPairingCode)"
HOSTS="$(fixture_text copyHosts)"
[ -n "$PAIRING" ] && [ -n "$HOSTS" ] || {
  echo "FAIL: routing fixtures are missing"
  exit 1
}

TH="$(mktemp -d)"
HOME_DIR="$TH/home"
STATE="$TH/state"
WORK="$TH/session"
LOG="$TH/meshd.log"
ALL="$TH/all.log"
HITS="$TH/hits"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
PORT=8898
SRV=
STUB=
DECOY_PID=
PDF="$TH/quarter.pdf"
PAIR_PDF="$TH/pairing.pdf"
HOST_PDF="$TH/hosts.pdf"
SENTENCE='Please summarize this paper on this machine.'
MESH_MARK="${HOME}/.mesh"
had_mesh=0
[ -e "$MESH_MARK" ] && had_mesh=1

case "$PORT" in
  8899) echo "FAIL: refusing port 8899"; exit 1 ;;
esac
[ "$PORT" = "8898" ] || { echo "FAIL: spare daemon must listen on 8898"; exit 1; }

stop_decoy() {
  [ -n "${DECOY_PID:-}" ] || return 0
  kill "$DECOY_PID" 2>/dev/null || true
  n=0
  while kill -0 "$DECOY_PID" 2>/dev/null && [ "$n" -lt 20 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -KILL "$DECOY_PID" 2>/dev/null || true
  wait "$DECOY_PID" 2>/dev/null || true
  DECOY_PID=
}

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
  if [ -f "$LOG" ]; then
    cat "$LOG" >> "$ALL" || true
  fi
  SRV=
}

cleanup() {
  ec=$?
  stop_srv
  stop_stub
  stop_decoy
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
: > "$ALL"
printf 'local page\n' > "$PDF"
printf 'local page\n' > "$PAIR_PDF"
printf 'local page\n' > "$HOST_PDF"
printf '%s\n' 'Draft of the matching paper.' > "$TH/assistant.txt"

cat > "$TH/pdfbin" <<EOF
#!/bin/sh
if [ "\$#" -ne 1 ]; then
  printf '%s\n' "argc:\$#" >> "$TH/pdf-args"
  exit 2
fi
printf '%s\n' "\$1" >> "$TH/pdf-args"
printf '%s\n' '$SENTENCE'
exit 0
EOF
chmod 700 "$TH/pdfbin"

python3 - "$TH/pairbin" "$PAIRING" "$TH/hostbin" "$HOSTS" <<'PY'
import os, shlex, sys
pairs = [(sys.argv[1], sys.argv[2]), (sys.argv[3], sys.argv[4])]
for path, text in pairs:
    if "summarize this paper" in text:
        raise SystemExit("FAIL: secret fixture includes the paper sentence")
    open(path, "w").write("#!/bin/sh\nprintf '%s\\n' %s\n" % ("%s", shlex.quote(text)))
    os.chmod(path, 0o700)
PY

python3 - "$TH/stub.reply" "$TH/assistant.txt" <<'PY'
import json, sys
text = open(sys.argv[2]).read()
open(sys.argv[1], "w").write(json.dumps({
    "choices": [{"message": {"role": "assistant", "content": text}}],
}))
PY

python3 - "$TH/decoy.port" "$HITS" 2>"$TH/decoy.err" <<'PY' &
import os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file, hit_file = sys.argv[1:3]

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        self._hit()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or "0")
        if n:
            self.rfile.read(n)
        self._hit()

    def do_PUT(self):
        self.do_POST()

    def _hit(self):
        with open(hit_file, "a") as fh:
            fh.write(self.command + " " + self.path + "\n")
        body = b""
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()
        self.wfile.write(body)

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
DECOY_PID=$!

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

wait_port() {
  file="$1"
  pid="$2"
  label="$3"
  i=0
  while [ ! -s "$file" ] && [ "$i" -lt 300 ]; do
    kill -0 "$pid" 2>/dev/null || {
      echo "FAIL: ${label} exited"
      exit 1
    }
    sleep 0.1
    i=$((i + 1))
  done
  [ -s "$file" ] || { echo "FAIL: ${label} port file never appeared"; exit 1; }
  got="$(tr -d '[:space:]' < "$file")"
  if [ -z "$got" ] || [ "$got" = "8899" ] || [ "$got" = "8898" ]; then
    echo "FAIL: ${label} port is not a spare 127.0.0.1 port"
    exit 1
  fi
  printf '%s' "$got"
}

DECOY="$(wait_port "$TH/decoy.port" "$DECOY_PID" "decoy")"
STUB_PORT="$(wait_port "$TH/stub.port" "$STUB" "model stub")"
echo "check-pdf-note-draft: model stub is on 127.0.0.1:${STUB_PORT}"

hits_ok() {
  if [ -s "$HITS" ]; then
    echo "FAIL: a remote URL received requests"
    exit 1
  fi
}

args_lines() {
  if [ ! -f "$TH/pdf-args" ]; then
    echo 0
    return 0
  fi
  wc -l < "$TH/pdf-args" | tr -d ' '
}

freeze_notes() {
  python3 - "$STATE/knowledge" "$1" <<'PY'
import hashlib, os, sys
root, out = sys.argv[1], sys.argv[2]
rows = []
if os.path.isdir(root):
    for name in sorted(os.listdir(root)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(root, name)
        digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
        rows.append(digest + " " + name)
text = "\n".join(rows)
if rows:
    text += "\n"
open(out, "w").write(text)
PY
}

mode_of() {
  mode="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1")"
  printf '%s' "${mode#0}"
}

stub_hits() {
  find "$TH/stub-bodies" -name '*.json' | wc -l | tr -d ' '
}

start_daemon() {
  pdf_bin="$1"
  stop_srv
  : > "$LOG"
  MESHD_PORT="$PORT" \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$STATE" \
  MESHD_TELEMETRY=off \
  MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
  MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
  MESHD_KB_PATH="$TH/kb.sqlite" \
  HOME="$HOME_DIR" \
  MESH_PDF="$pdf_bin" \
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
}

post_pdf() {
  out="$1"
  pdf="$2"
  title="${3-}"
  if [ -n "$title" ]; then
    PDF_VALUE="$pdf" TITLE_VALUE="$title" python3 - "$TH/req.json" <<'PY'
import json, os, sys
json.dump({"pdf": os.environ["PDF_VALUE"], "title": os.environ["TITLE_VALUE"]}, open(sys.argv[1], "w"))
PY
  else
    PDF_VALUE="$pdf" python3 - "$TH/req.json" <<'PY'
import json, os, sys
json.dump({"pdf": os.environ["PDF_VALUE"]}, open(sys.argv[1], "w"))
PY
  fi
  curl --connect-timeout 1 --max-time 8 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/req.json" \
    "http://127.0.0.1:$PORT/knowledge" || true
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

start_daemon "$TH/pdfbin"
code="$(post_pdf "$TH/post.json" "$PDF" "Quarter")"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge pdf -> ${code}"; cat "$TH/post.json"; echo; tail -n 40 "$LOG"; exit 1; }
PDF_PATH="$PDF" SENTENCE="$SENTENCE" python3 - "$TH/post.json" "$STATE" "$TH/pdf-args" "$TH/note.id" <<'PY'
import json, os, sys
post = json.load(open(sys.argv[1]))
state, args_path, id_path = sys.argv[2:5]
pdf = os.environ["PDF_PATH"]
sentence = os.environ["SENTENCE"]
if "summarize this paper" not in sentence:
    raise SystemExit("FAIL: stub sentence lost the paper phrase")
if set(post.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: create keys are %r" % (sorted(post.keys()),))
if post.get("title") != "Quarter":
    raise SystemExit("FAIL: title is %r" % (post.get("title"),))
if pdf in json.dumps(post):
    raise SystemExit("FAIL: create response includes the absolute path")
note_path = os.path.join(state, "knowledge", post["id"] + ".json")
note = json.load(open(note_path))
if note.get("body") != sentence:
    raise SystemExit("FAIL: note body is %r" % (note.get("body"),))
if note.get("title") != "Quarter":
    raise SystemExit("FAIL: stored title is %r" % (note.get("title"),))
if note.get("source") != "quarter.pdf":
    raise SystemExit("FAIL: stored source is %r" % (note.get("source"),))
if pdf in json.dumps(note):
    raise SystemExit("FAIL: stored note includes the absolute path")
args = open(args_path).read().splitlines()
if args != [pdf]:
    raise SystemExit("FAIL: extractor args are %r" % (args,))
names = [name for name in os.listdir(os.path.join(state, "knowledge")) if name.endswith(".json")]
if names != [post["id"] + ".json"]:
    raise SystemExit("FAIL: knowledge files are %r" % (names,))
open(id_path, "w").write(post["id"])
PY
note_file="$STATE/knowledge/$(cat "$TH/note.id").json"
fmode="$(mode_of "$note_file")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-pdf-note-draft: file mode 600"
echo "check-pdf-note-draft: directory mode 700"

code="$(curl -G --connect-timeout 1 --max-time 5 -sS -o "$TH/search.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  --data-urlencode "q=summarize this paper" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge?q= -> ${code}"; cat "$TH/search.json"; echo; exit 1; }
PDF_PATH="$PDF" SENTENCE="$SENTENCE" python3 - "$TH/search.json" "$TH/note.id" <<'PY'
import json, os, sys
raw = open(sys.argv[1]).read()
pdf = os.environ["PDF_PATH"]
sentence = os.environ["SENTENCE"]
if pdf in raw or sentence in raw:
    raise SystemExit("FAIL: query returned the path or the body")
data = json.loads(raw)
if set(data.keys()) != {"notes"}:
    raise SystemExit("FAIL: query keys are %r" % (sorted(data.keys()),))
notes = data["notes"]
if len(notes) != 1:
    raise SystemExit("FAIL: query has %d notes" % (len(notes),))
note = notes[0]
if set(note.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: query note keys are %r" % (sorted(note.keys()),))
if note.get("id") != open(sys.argv[2]).read() or note.get("title") != "Quarter":
    raise SystemExit("FAIL: query note is %r" % (note,))
PY
echo "check-pdf-note-draft: query is id and title"
[ "$(stub_hits)" = "0" ] || { echo "FAIL: ingest called the model"; exit 1; }

freeze_notes "$TH/frozen.txt"
before="$(args_lines)"
code="$(post_pdf "$TH/rej.json" "http://127.0.0.1:${DECOY}/quarter.pdf")"
[ "$code" = "400" ] || { echo "FAIL: pdf containing :// -> ${code}"; cat "$TH/rej.json"; echo; exit 1; }
freeze_notes "$TH/after.txt"
cmp -s "$TH/frozen.txt" "$TH/after.txt" || { echo "FAIL: pdf containing :// wrote a note"; exit 1; }
after="$(args_lines)"
[ "$before" = "$after" ] || { echo "FAIL: pdf containing :// spawned the local executable"; exit 1; }
hits_ok
echo "check-pdf-note-draft: pdf containing :// wrote nothing"

start_daemon "http://127.0.0.1:${DECOY}/pdftotext"
freeze_notes "$TH/frozen.txt"
code="$(post_pdf "$TH/remote.json" "$PDF" "Quarter")"
[ "$code" = "400" ] || { echo "FAIL: remote MESH_PDF -> ${code}"; cat "$TH/remote.json"; echo; tail -n 40 "$LOG"; exit 1; }
freeze_notes "$TH/after.txt"
cmp -s "$TH/frozen.txt" "$TH/after.txt" || { echo "FAIL: remote MESH_PDF wrote a note"; exit 1; }
hits_ok
echo "check-pdf-note-draft: remote MESH_PDF wrote nothing"

post_secret() {
  label="$1"
  bin="$2"
  pdf="$3"
  title="$4"
  body="$5"
  id_file="$6"
  start_daemon "$bin"
  code="$(post_pdf "$TH/secret-post.json" "$pdf" "$title")"
  [ "$code" = "201" ] || { echo "FAIL: ${label} pdf -> ${code}"; cat "$TH/secret-post.json"; echo; tail -n 40 "$LOG"; exit 1; }
  BODY="$body" TITLE="$title" python3 - "$TH/secret-post.json" "$STATE" "$pdf" "$id_file" <<'PY'
import json, os, sys
post = json.load(open(sys.argv[1]))
if set(post.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: secret create keys are %r" % (sorted(post.keys()),))
if post.get("title") != os.environ["TITLE"]:
    raise SystemExit("FAIL: secret title is %r" % (post.get("title"),))
note = json.load(open(os.path.join(sys.argv[2], "knowledge", post["id"] + ".json")))
if note.get("body") != os.environ["BODY"]:
    raise SystemExit("FAIL: secret body is %r" % (note.get("body"),))
if sys.argv[3] in json.dumps(note):
    raise SystemExit("FAIL: secret note includes the absolute path")
mode = os.stat(os.path.join(sys.argv[2], "knowledge", post["id"] + ".json")).st_mode & 0o777
if mode != 0o600:
    raise SystemExit("FAIL: secret note mode is %o" % mode)
open(sys.argv[4], "w").write(post["id"])
PY
}

post_secret "pairing code" "$TH/pairbin" "$PAIR_PDF" "Pairing paper" "$PAIRING" "$TH/pair.id"
post_secret "hosts.json" "$TH/hostbin" "$HOST_PDF" "Hosts paper" "$HOSTS" "$TH/host.id"
[ "$(stub_hits)" = "0" ] || { echo "FAIL: a secret note called the model"; exit 1; }
echo "check-pdf-note-draft: pairing-code note is stored"
echo "check-pdf-note-draft: hosts.json note is stored"

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

held_query() {
  label="$1"
  query="$2"
  write_query "$TH/held-req.json" "$query"
  code="$(post_agent "$TH/held.json" "$TH/held-req.json")"
  [ "$code" = "200" ] || { echo "FAIL: ${label} -> ${code}"; cat "$TH/held.json"; echo; tail -n 40 "$LOG"; exit 1; }
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
echo "check-pdf-note-draft: pairing code was held and the model was not called"
echo "check-pdf-note-draft: hosts.json was held and the model was not called"

python3 - "$TH/draft-req.json" "$WORK" "$MODEL" <<'PY'
import json, sys
json.dump({
    "q": "summarize this paper",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "held-paper.txt",
    "command": "touch unconfirmed-ran",
    "confirm": False,
}, open(sys.argv[1], "w"))
PY
code="$(post_agent "$TH/draft.json" "$TH/draft-req.json")"
[ "$code" = "200" ] || { echo "FAIL: paper draft -> ${code}"; cat "$TH/draft.json"; echo; tail -n 40 "$LOG"; exit 1; }
PAPER_SENTENCE="$SENTENCE" PAIRING="$PAIRING" HOSTS="$HOSTS" \
python3 - "$TH/draft.json" "$WORK/held-paper.txt" "$TH/assistant.txt" <<'PY'
import json, os, stat, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
allowed = {"local", "user-subscription"}
if data.get("modelClass") not in allowed or data.get("modelClass") != "local":
    raise SystemExit("FAIL: draft modelClass is %r" % (data.get("modelClass"),))
if data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: command without confirm was not held")
if data.get("draft") != "held-paper.txt":
    raise SystemExit("FAIL: draft name is %r" % (data.get("draft"),))
if os.path.isabs(str(data.get("draft"))):
    raise SystemExit("FAIL: draft is absolute")
for needle in ("127.0.0.1", "http", "supabase", "chat/completions"):
    if needle in raw:
        raise SystemExit("FAIL: draft transcript contains %s" % needle)
assistant = open(sys.argv[3]).read()
draft = open(sys.argv[2]).read()
if draft != assistant:
    raise SystemExit("FAIL: file is not the stub reply")
if os.environ["PAPER_SENTENCE"] in draft:
    raise SystemExit("FAIL: file is the pdf sentence, not a draft")
mode = stat.S_IMODE(os.stat(sys.argv[2]).st_mode)
if mode != 0o600:
    raise SystemExit("FAIL: draft mode is %o" % mode)
if mode & 0o111:
    raise SystemExit("FAIL: draft file is executable")
PY
[ ! -e "$WORK/unconfirmed-ran" ] || { echo "FAIL: command without confirm ran"; exit 1; }
[ "$(stub_hits)" = "1" ] || { echo "FAIL: paper query called the model $(stub_hits) times"; exit 1; }
held_mode="$(mode_of "$WORK/held-paper.txt")"
[ "$held_mode" = "600" ] || { echo "FAIL: held file mode is $held_mode, want 600"; exit 1; }
echo "check-pdf-note-draft: unique paper match drafted one relative file mode 600"
echo "check-pdf-note-draft: held file was not executed"
echo "check-pdf-note-draft: command without confirm did not run"

PAPER_SENTENCE="$SENTENCE" PAIRING="$PAIRING" HOSTS="$HOSTS" \
python3 - "$TH/stub-bodies" "$TH/stub.path" "$TH/stub.headers" "$WORK" <<'PY'
import json, os, sys
body_dir, path_file, header_file, work = sys.argv[1:5]
names = sorted(name for name in os.listdir(body_dir) if name.endswith(".json"))
if names != ["1.json"]:
    raise SystemExit("FAIL: stub files are %r" % (names,))
payload = json.load(open(os.path.join(body_dir, "1.json")))
allowed = {"local", "user-subscription"}
if payload.get("model") not in allowed or payload.get("model") != "local":
    raise SystemExit("FAIL: stub model class is %r" % (payload.get("model"),))
messages = json.dumps(payload.get("messages"))
sentence = os.environ["PAPER_SENTENCE"]
if sentence not in messages or "summarize this paper" not in messages:
    raise SystemExit("FAIL: stub did not receive the pdf note")
if os.environ["PAIRING"] in messages or os.environ["HOSTS"] in messages:
    raise SystemExit("FAIL: stub received a secret note")
paths = [line.strip() for line in open(path_file).read().splitlines() if line.strip()]
if paths != ["POST /v1/chat/completions"]:
    raise SystemExit("FAIL: stub paths are %r" % (paths,))
headers = open(header_file).read().lower()
if "authorization" in headers or "bearer" in headers or "supabase.co" in headers:
    raise SystemExit("FAIL: stub saw an authorization header")
session = sorted(os.listdir(work))
if session != ["held-paper.txt"]:
    raise SystemExit("FAIL: session files are %r" % (session,))
PY

python3 - "$STATE/knowledge/$(cat "$TH/note.id").json" \
  "$STATE/knowledge/$(cat "$TH/pair.id").json" \
  "$STATE/knowledge/$(cat "$TH/host.id").json" \
  "$SENTENCE" "$PAIRING" "$HOSTS" <<'PY'
import json, sys
pairs = [
    (sys.argv[1], sys.argv[4], "paper"),
    (sys.argv[2], sys.argv[5], "pairing"),
    (sys.argv[3], sys.argv[6], "hosts"),
]
for path, text, label in pairs:
    body = json.load(open(path)).get("body")
    if body != text:
        raise SystemExit("FAIL: %s note body changed" % label)
PY

dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
hits_ok
[ ! -d "$HOME_DIR/.mesh" ] || { echo "FAIL: daemon wrote under its home directory"; exit 1; }
if [ "$had_mesh" -eq 0 ] && [ -e "$MESH_MARK" ]; then
  echo "FAIL: wrote ~/.mesh"
  exit 1
fi
if [ -f "$LOG" ]; then
  cat "$LOG" >> "$ALL" || true
fi
if grep -E -q 'supabase\.co|ai-gateway' "$ALL"; then
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

echo "check-pdf-note-draft: OK"

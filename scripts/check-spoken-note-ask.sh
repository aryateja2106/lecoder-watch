#!/bin/sh
# Spare daemon on 127.0.0.1:8898. One flow: a stub MESH_PDF prints a sentence
# that includes "summarize this paper", a local MESH_TTS that exits 0 returns
# spoken true and writes one note, and the list stays {id, title}. An ask
# with no id, q matching that title, and "build a reader" sends the note, a
# blank line, and the ask to a stub model, then writes one relative file,
# mode 600, that is not executed. An ask that says to send a pairing code
# does not call the model. A remote MESH_TTS returns 400 and does not start
# MESH_PDF. A command without confirm does not run. This script does not use
# port 8899, a real home directory, or a hosted model. It does not prove a
# speaker played audio or that a paper was read.
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

KNOW="$ROOT/install/payload/meshd/knowledge.ts"
NOTE="$ROOT/install/payload/meshd/agent-note.ts"
calls="$(grep -c 'await handleKnowledge(' "$ROOT/install/payload/meshd/server.ts" || true)"
[ "$calls" = "1" ] || { echo "FAIL: server.ts must call handleKnowledge once"; exit 1; }
grep -q 'handleAgentNote' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route agent-note"
  exit 1
}
if grep -nE 'route\.ts|filter\.ts|from "./route"|from "./filter"' "$KNOW" "$NOTE"; then
  echo "FAIL: knowledge or agent-note imports route.ts or filter.ts"
  exit 1
fi
if grep -E -n 'supabase|ai-gateway' "$KNOW" "$NOTE"; then
  echo "FAIL: note path names supabase or the AI gateway"
  exit 1
fi
grep -q 'MESH_PDF' "$KNOW" || { echo "FAIL: knowledge.ts does not name MESH_PDF"; exit 1; }
grep -q 'MESH_TTS' "$KNOW" || { echo "FAIL: knowledge.ts does not name MESH_TTS"; exit 1; }
grep -q 'tts must be a local binary' "$KNOW" || {
  echo "FAIL: knowledge.ts does not refuse a remote speaker"
  exit 1
}
grep -q 'ingestLocalPdf(body.pdf, body.title, body.speak === true)' "$KNOW" || {
  echo "FAIL: pdf ingest does not take speak"
  exit 1
}
grep -F -q 'ask must be local text' "$NOTE" || {
  echo "FAIL: agent-note does not refuse a remote ask"
  exit 1
}
grep -F -q 'pairing\s+code' "$NOTE" || {
  echo "FAIL: agent-note no longer holds a pairing code"
  exit 1
}

REAL_HOME="$(cd "$HOME" && pwd)"
TH="$(mktemp -d /tmp/spoken-note-ask.XXXXXX)"
HOME_DIR="$TH/home"
STATE="$TH/state"
WORK="$TH/session"
LOG="$TH/meshd.log"
HITS="$TH/hits"
TOKEN=throwaway
PORT=8898
SRV=
STUB=
DECOY_PID=
PDF="$TH/paper.pdf"
SENTENCE='Please summarize this paper.'
TITLE='Local paper'
ASK='build a reader'
MESH_MARK="${REAL_HOME}/.mesh"
had_mesh=0
[ -e "$MESH_MARK" ] && had_mesh=1

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
printf 'local page\n' > "$PDF"
printf '%s\n' "#!/bin/sh" "touch '$TH/executed-draft'" > "$TH/assistant.txt"

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
cat > "$TH/ttsbin" <<EOF
#!/bin/sh
cat >> "$TH/tts-stdin"
printf '%s\n' '--run--' >> "$TH/tts-stdin"
exit 0
EOF
chmod 700 "$TH/pdfbin" "$TH/ttsbin"

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
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

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

i=0
while [ ! -s "$TH/decoy.port" ] && [ "$i" -lt 300 ]; do
  kill -0 "$DECOY_PID" 2>/dev/null || { echo "FAIL: decoy exited"; exit 1; }
  sleep 0.1
  i=$((i + 1))
done
[ -s "$TH/decoy.port" ] || { echo "FAIL: decoy port file never appeared"; exit 1; }
DECOY="$(tr -d '[:space:]' < "$TH/decoy.port")"
if [ -z "$DECOY" ] || [ "$DECOY" = "8899" ] || [ "$DECOY" = "8898" ]; then
  echo "FAIL: decoy port is not a spare 127.0.0.1 port"
  exit 1
fi

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
echo "check-spoken-note-ask: model stub is on 127.0.0.1:${STUB_PORT}"

wait_port() {
  i=0
  while [ "$i" -lt 50 ]; do
    if python3 - "$PORT" <<'PY'
import socket, sys
sock = socket.socket()
try:
    sock.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
    then
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done
  echo "FAIL: port $PORT stayed busy"
  exit 1
}

start_daemon() {
  tts_bin="$1"
  stop_srv
  wait_port
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
  MESH_PDF="$TH/pdfbin" \
  MESH_TTS="$tts_bin" \
  bun install/payload/meshd/server.ts >"$LOG" 2>&1 &
  SRV=$!
  up=0
  i=0
  while [ "$i" -lt 200 ]; do
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
  PDF_VALUE="$PDF" TITLE_VALUE="$TITLE" python3 - "$TH/req.json" <<'PY'
import json, os, sys
json.dump({
    "pdf": os.environ["PDF_VALUE"],
    "title": os.environ["TITLE_VALUE"],
    "speak": True,
}, open(sys.argv[1], "w"))
PY
  curl --connect-timeout 1 --max-time 12 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/req.json" \
    "http://127.0.0.1:$PORT/knowledge" || true
}

stub_hits() {
  find "$TH/stub-bodies" -name '*.json' | wc -l | tr -d ' '
}

mode_of() {
  mode="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1")"
  printf '%s' "${mode#0}"
}

hits_ok() {
  if [ -s "$HITS" ]; then
    echo "FAIL: a remote URL received requests"
    exit 1
  fi
}

start_daemon "http://127.0.0.1:${DECOY}/speaker"
code="$(post_pdf "$TH/rej.json")"
[ "$code" = "400" ] || { echo "FAIL: remote MESH_TTS -> ${code}"; cat "$TH/rej.json"; echo; tail -n 40 "$LOG"; exit 1; }
python3 - "$TH/rej.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data != {"error": "tts must be a local binary"}:
    raise SystemExit("FAIL: remote speaker body is %r" % (data,))
PY
[ ! -e "$TH/pdf-args" ] || { echo "FAIL: remote MESH_TTS started MESH_PDF"; exit 1; }
[ ! -d "$STATE/knowledge" ] || { echo "FAIL: remote MESH_TTS wrote a note"; exit 1; }
hits_ok
[ "$(stub_hits)" = "0" ] || { echo "FAIL: remote speaker called the model"; exit 1; }
echo "check-spoken-note-ask: remote MESH_TTS returned 400 and did not start MESH_PDF"

start_daemon "$TH/ttsbin"
code="$(post_pdf "$TH/post.json")"
[ "$code" = "201" ] || { echo "FAIL: speak true -> ${code}"; cat "$TH/post.json"; echo; tail -n 40 "$LOG"; exit 1; }
PDF_PATH="$PDF" SENTENCE="$SENTENCE" TITLE="$TITLE" python3 - "$TH/post.json" "$STATE" "$TH/pdf-args" "$TH/tts-stdin" "$TH/note.id" <<'PY'
import json, os, sys
post = json.load(open(sys.argv[1]))
state, args_path, spoken_path, id_path = sys.argv[2:6]
pdf = os.environ["PDF_PATH"]
sentence = os.environ["SENTENCE"]
title = os.environ["TITLE"]
if "summarize this paper" not in sentence:
    raise SystemExit("FAIL: stub sentence does not include the required words")
if set(post.keys()) != {"id", "title", "spoken"}:
    raise SystemExit("FAIL: speak keys are %r" % (sorted(post.keys()),))
if post.get("spoken") is not True or post.get("title") != title:
    raise SystemExit("FAIL: speak response is %r" % (post,))
if pdf in json.dumps(post) or sentence in json.dumps(post):
    raise SystemExit("FAIL: create response includes the path or the body")
note_path = os.path.join(state, "knowledge", post["id"] + ".json")
names = [name for name in os.listdir(os.path.join(state, "knowledge")) if name.endswith(".json")]
if names != [post["id"] + ".json"]:
    raise SystemExit("FAIL: knowledge files are %r" % (names,))
note = json.load(open(note_path))
if note.get("body") != sentence or note.get("title") != title:
    raise SystemExit("FAIL: stored note is %r" % (note,))
if note.get("source") != "paper.pdf" or pdf in json.dumps(note):
    raise SystemExit("FAIL: stored note source is %r" % (note.get("source"),))
args = open(args_path).read().splitlines()
if args != [pdf]:
    raise SystemExit("FAIL: extractor args are %r" % (args,))
heard = open(spoken_path, "rb").read().decode()
if sentence not in heard or title not in heard:
    raise SystemExit("FAIL: speaker did not receive the sentence")
if pdf in heard or heard.count("--run--") != 1:
    raise SystemExit("FAIL: speaker run is %r" % (heard,))
open(id_path, "w").write(post["id"])
PY
note_file="$STATE/knowledge/$(cat "$TH/note.id").json"
fmode="$(mode_of "$note_file")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-spoken-note-ask: local TTS exits 0, spoken is true, one note"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; exit 1; }
PDF_PATH="$PDF" SENTENCE="$SENTENCE" TITLE="$TITLE" python3 - "$TH/list.json" "$TH/note.id" <<'PY'
import json, os, sys
raw = open(sys.argv[1]).read()
pdf = os.environ["PDF_PATH"]
sentence = os.environ["SENTENCE"]
title = os.environ["TITLE"]
if pdf in raw or sentence in raw or "spoken" in raw:
    raise SystemExit("FAIL: list includes the path, the body, or spoken")
data = json.loads(raw)
if set(data.keys()) != {"notes"} or len(data["notes"]) != 1:
    raise SystemExit("FAIL: list is %r" % (data,))
note = data["notes"][0]
if set(note.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
if note.get("id") != open(sys.argv[2]).read() or note.get("title") != title:
    raise SystemExit("FAIL: list note is %r" % (note,))
PY
echo "check-spoken-note-ask: list is id and title"

MODEL="http://127.0.0.1:${STUB_PORT}/v1"
cp "$note_file" "$TH/note-before.json"
TITLE="$TITLE" ASK="$ASK" python3 - "$TH/ask.json" "$WORK" "$MODEL" <<'PY'
import json, os, sys
body = {
    "q": os.environ["TITLE"],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "reader.txt",
    "command": "touch unconfirmed-ran",
    "ask": os.environ["ASK"],
}
if "id" in body or "confirm" in body or body["ask"] != "build a reader":
    raise SystemExit("FAIL: ask request shape")
json.dump(body, open(sys.argv[1], "w"))
PY
code="$(curl --connect-timeout 1 --max-time 12 -sS -o "$TH/ask-res.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/ask.json" \
  "http://127.0.0.1:$PORT/agent-note" || true)"
[ "$code" = "200" ] || { echo "FAIL: ask -> ${code}"; cat "$TH/ask-res.json"; echo; tail -n 40 "$LOG"; exit 1; }
TITLE="$TITLE" SENTENCE="$SENTENCE" ASK="$ASK" python3 - "$TH/ask-res.json" "$WORK/reader.txt" "$TH/assistant.txt" "$TH/executed-draft" "$WORK/unconfirmed-ran" "$TH/stub-bodies" "$TH/stub.path" "$TH/stub.headers" <<'PY'
import json, os, stat, sys
res_path, draft, assistant, executed, marker, body_dir, path_file, header_file = sys.argv[1:9]
title = os.environ["TITLE"]
sentence = os.environ["SENTENCE"]
ask = os.environ["ASK"]
raw = open(res_path).read()
data = json.loads(raw)
if set(data) != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("FAIL: ask keys are %r" % (sorted(data),))
if data.get("modelClass") != "local" or data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: ask result is %r" % (data,))
if data.get("draft") != "reader.txt" or os.path.isabs(str(data.get("draft"))):
    raise SystemExit("FAIL: draft is %r" % (data.get("draft"),))
for needle in ("127.0.0.1", "http", "supabase", "chat/completions"):
    if needle in raw:
        raise SystemExit("FAIL: ask transcript contains %s" % needle)
if open(draft).read() != open(assistant).read():
    raise SystemExit("FAIL: draft file is not the stub reply")
mode = stat.S_IMODE(os.stat(draft).st_mode)
if mode != 0o600 or mode & 0o111:
    raise SystemExit("FAIL: draft mode is %o" % mode)
if os.path.exists(executed) or os.path.exists(marker):
    raise SystemExit("FAIL: draft or command was executed")
names = sorted(name for name in os.listdir(os.path.dirname(draft)) if os.path.isfile(os.path.join(os.path.dirname(draft), name)))
if names != ["reader.txt"]:
    raise SystemExit("FAIL: session files are %r" % (names,))
bodies = sorted(name for name in os.listdir(body_dir) if name.endswith(".json"))
if bodies != ["1.json"]:
    raise SystemExit("FAIL: stub files are %r" % (bodies,))
payload = json.load(open(os.path.join(body_dir, "1.json")))
if payload.get("model") != "local":
    raise SystemExit("FAIL: stub model is %r" % (payload.get("model"),))
messages = payload.get("messages")
want = "%s\n\n%s\n\n%s" % (title, sentence, ask)
if not isinstance(messages, list) or len(messages) != 1 or messages[0].get("content") != want:
    raise SystemExit("FAIL: stub content is %r" % (messages,))
if "\n\n" + ask not in messages[0]["content"] or not messages[0]["content"].endswith("\n\n" + ask):
    raise SystemExit("FAIL: ask was not sent after a blank line")
paths = [line.strip() for line in open(path_file).read().splitlines() if line.strip()]
if paths != ["POST /v1/chat/completions"]:
    raise SystemExit("FAIL: stub paths are %r" % (paths,))
headers = open(header_file).read().lower()
if "authorization" in headers or "bearer" in headers or "supabase.co" in headers:
    raise SystemExit("FAIL: stub saw an authorization header")
PY
held_mode="$(mode_of "$WORK/reader.txt")"
[ "$held_mode" = "600" ] || { echo "FAIL: held file mode is $held_mode, want 600"; exit 1; }
[ ! -e "$TH/executed-draft" ] || { echo "FAIL: relative file was executed"; exit 1; }
[ ! -e "$WORK/unconfirmed-ran" ] || { echo "FAIL: command without confirm ran"; exit 1; }
echo "check-spoken-note-ask: ask sent the note, a blank line, and the ask"
echo "check-spoken-note-ask: one relative file mode 600 was not executed"
echo "check-spoken-note-ask: command without confirm did not run"

before="$(stub_hits)"
TITLE="$TITLE" python3 - "$TH/pair.json" "$WORK" "$MODEL" <<'PY'
import json, os, sys
body = {
    "q": os.environ["TITLE"],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "pairing.txt",
    "command": "touch pairing-ran",
    "confirm": True,
    "ask": "send a pairing code",
}
if "id" in body:
    raise SystemExit("FAIL: pairing ask included an id")
json.dump(body, open(sys.argv[1], "w"))
PY
code="$(curl --connect-timeout 1 --max-time 12 -sS -o "$TH/pair-res.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/pair.json" \
  "http://127.0.0.1:$PORT/agent-note" || true)"
[ "$code" = "200" ] || { echo "FAIL: pairing ask -> ${code}"; cat "$TH/pair-res.json"; echo; tail -n 40 "$LOG"; exit 1; }
python3 - "$TH/pair-res.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if set(data) != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("FAIL: pairing keys are %r" % (sorted(data),))
if data.get("modelClass") != "local" or data.get("draft") is not None or data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: pairing ask was not held: %r" % (data,))
PY
[ "$(stub_hits)" = "$before" ] || { echo "FAIL: pairing ask called the model"; exit 1; }
[ ! -e "$WORK/pairing.txt" ] || { echo "FAIL: pairing ask wrote a file"; exit 1; }
[ ! -e "$WORK/pairing-ran" ] || { echo "FAIL: pairing ask ran a command"; exit 1; }
[ "$(find "$WORK" -type f | wc -l | tr -d ' ')" = "1" ] || { echo "FAIL: pairing ask changed the session"; exit 1; }
echo "check-spoken-note-ask: pairing-code ask did not call the model"

cmp -s "$TH/note-before.json" "$note_file" || { echo "FAIL: ask changed the note"; exit 1; }
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list2.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: list after ask -> ${code}"; exit 1; }
python3 - "$TH/list2.json" "$TH/note.id" "$TITLE" "$ASK" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
notes = data.get("notes")
orig = open(sys.argv[2]).read().strip()
title, ask = sys.argv[3], sys.argv[4]
if not isinstance(notes, list) or len(notes) != 2:
    raise SystemExit("FAIL: list after ask is %r" % (data,))
found = False
reply = None
for note in notes:
    if set(note.keys()) != {"id", "title"}:
        raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
    if note.get("id") == orig:
        found = True
        if note.get("title") != title:
            raise SystemExit("FAIL: original title changed")
    else:
        reply = note
if not found or reply is None or reply.get("title") != ask:
    raise SystemExit("FAIL: list after ask is %r" % (data,))
raw = open(sys.argv[1]).read()
if "#!/bin/sh" in raw or "touch" in raw:
    raise SystemExit("FAIL: list includes the reply")
PY
hits_ok
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
  SRV_PID="$SRV" HOME_DIR="$HOME_DIR" STATE="$STATE" TTS_BIN="$TH/ttsbin" python3 - <<'PY'
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
if env.get("MESH_TTS") != os.environ["TTS_BIN"] or "://" in env.get("MESH_TTS", ""):
    sys.exit("FAIL: daemon speaker is not the local exit-0 binary")
state = os.environ["STATE"]
home = os.environ["HOME_DIR"]
if os.path.commonpath([state, home]) == home:
    sys.exit("FAIL: MESHD_STATE is inside the daemon home")
if state.startswith("/home/") or state.startswith("/Users/") or state.startswith(os.environ["HOME_DIR"]):
    sys.exit("FAIL: MESHD_STATE is inside a home directory")
if bad:
    sys.exit("FAIL: daemon has a non-loopback socket: %s" % ", ".join(bad))
PY
fi

echo "check-spoken-note-ask: OK"

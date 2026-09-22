#!/bin/sh
# One spare daemon holds two extracted pages. Asking the oak page sends that
# sentence to the model and leaves the pairing page out. A query that matches
# both notes is refused before another model call or another draft.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }
command -v lsof >/dev/null 2>&1 || { echo "FAIL: lsof is required"; exit 1; }

TH="$(mktemp -d)"
PORT=8898
SRV=
STUB=
HOSTS_ADDED=0
HOSTS_MARK="mesh-extracted-note-scope-$$"
USERINFO="sk-meshkey"
STUB_BODIES="$TH/stub-bodies"
mkdir -p "$STUB_BODIES"

stop_group() {
  pid=$1
  [ -n "$pid" ] || return 0
  kill -TERM "-${pid}" 2>/dev/null || true
  n=0
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 30 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -KILL "-${pid}" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

stop_srv() {
  stop_group "${SRV:-}"
  SRV=
}

stop_stub() {
  stop_group "${STUB:-}"
  STUB=
}

remove_hosts() {
  [ "$HOSTS_ADDED" = 1 ] || return 0
  python3 -c '
import sys
path, marker = "/etc/hosts", sys.argv[1]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines(True)
kept = [ln for ln in lines if marker not in ln]
try:
    with open(path, "w", encoding="utf-8") as fh:
        fh.writelines(kept)
except PermissionError:
    sys.exit(13)
' "$HOSTS_MARK" 2>/dev/null || sudo -n python3 -c '
import sys
path, marker = "/etc/hosts", sys.argv[1]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines(True)
kept = [ln for ln in lines if marker not in ln]
with open(path, "w", encoding="utf-8") as fh:
    fh.writelines(kept)
' "$HOSTS_MARK" 2>/dev/null || true
  HOSTS_ADDED=0
}

cleanup() {
  ec=$?
  set +e
  stop_srv
  stop_stub
  remove_hosts
  rm -rf "$TH"
  exit "$ec"
}
trap cleanup EXIT

port_busy() {
  lsof -nP -iTCP:8898 -sTCP:LISTEN >/dev/null 2>&1
}

write_pdf() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
path, sentence, title = sys.argv[1:4]
stream = ("BT /F1 12 Tf 72 720 Td (%s) Tj ET\n" % sentence).encode()
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

write_speaker() {
  bin=$1
  marker=$2
  cat >"$bin" <<EOF
#!/bin/sh
cat >> "$marker"
exit 0
EOF
  chmod 700 "$bin"
}

start_daemon() {
  case_dir=$1
  token=$2
  state=$3
  tts=$4
  log=$5
  if port_busy; then
    echo "FAIL: port 8898 is already in use"
    exit 1
  fi
  env -u AI_GATEWAY_API_KEY \
    MESHD_PORT="$PORT" \
    MESHD_HOST=127.0.0.1 \
    MESHD_TOKEN="$token" \
    MESHD_STATE="$state" \
    MESHD_TELEMETRY=off \
    MESHD_EVENTS_PATH="$case_dir/agent-events.jsonl" \
    MESHD_TELEMETRY_STATE="$case_dir/telemetry.json" \
    MESHD_KB_PATH="$case_dir/kb.sqlite" \
    HOME="$case_dir" \
    MESH_TTS="$tts" \
    python3 -c 'import os; os.setsid(); os.execvp("bun", ["bun", "server.ts"])' >"$log" 2>&1 &
  SRV=$!
  up=0
  i=0
  while [ "$i" -lt 300 ]; do
    if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      up=1
      break
    fi
    kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited before listening"; cat "$log"; exit 1; }
    sleep 0.1
    i=$((i + 1))
  done
  [ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on $PORT"; cat "$log"; exit 1; }
}

post_json() {
  token=$1
  url=$2
  body=$3
  out=$4
  curl --connect-timeout 1 --max-time 20 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${token}" \
    -H 'content-type: application/json' \
    --data-binary @"$body" \
    "$url" || true
}

stub_hits() {
  find "$STUB_BODIES" -type f -name '*.json' | wc -l | tr -d '[:space:]'
}

write_agent_req() {
  dest=$1
  query=$2
  work=$3
  model=$4
  file=$5
  marker=$6
  ask_mode=$7
  ask_value=$8
  confirm_mode=$9
  python3 - "$dest" "$query" "$work" "$model" "$file" "$marker" "$ask_mode" "$ask_value" "$confirm_mode" <<'PY'
import json, sys
dest, query, work, model, file, marker, ask_mode, ask_value, confirm_mode = sys.argv[1:10]
body = {
    "q": query,
    "cwd": work,
    "model": model,
    "file": file,
    "command": "touch " + marker + " && printf x >> " + marker + ".count",
}
if ask_mode == "present":
    body["ask"] = ask_value
if confirm_mode == "yes":
    body["confirm"] = True
json.dump(body, open(dest, "w"))
PY
}

# Model stub on loopback. The configured host stays llm.example.
cat >"$TH/stub.py" <<'PY'
import json, os
base = os.path.dirname(os.path.abspath(__file__))
port_path = os.path.join(base, "stub.port")
body_dir = os.path.join(base, "stub-bodies")
reply_path = os.path.join(base, "stub.reply")
reply = json.dumps({"choices": [{"message": {"content": "A reader for the margin."}}]}).encode()
open(reply_path, "wb").write(reply)
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.end_headers()
        self.wfile.write(b"{}")
    def do_POST(self):
        n = int(self.headers.get("content-length") or 0)
        raw = self.rfile.read(n)
        name = "%d" % (len(os.listdir(body_dir)) + 1)
        open(os.path.join(body_dir, name + ".json"), "wb").write(raw)
        open(os.path.join(body_dir, name + ".host"), "w").write(self.headers.get("host") or "")
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)
    def log_message(self, fmt, *args):
        return

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_path, "w", encoding="utf-8") as fh:
    fh.write(str(server.server_address[1]))
    fh.flush()
server.serve_forever()
PY
python3 -c 'import os,sys; os.setsid(); os.execvp("python3", ["python3", sys.argv[1]])' "$TH/stub.py" >"$TH/stub.err" 2>&1 &
STUB=$!
i=0
while [ ! -s "$TH/stub.port" ] && [ "$i" -lt 100 ]; do
  kill -0 "$STUB" 2>/dev/null || { echo "FAIL: model stub exited"; cat "$TH/stub.err" 2>/dev/null || true; exit 1; }
  sleep 0.1
  i=$((i + 1))
done
[ -s "$TH/stub.port" ] || { echo "FAIL: model stub port never appeared"; cat "$TH/stub.err" 2>/dev/null || true; exit 1; }
STUB_PORT="$(tr -d '[:space:]' < "$TH/stub.port")"
case "$STUB_PORT" in
  ''|*[!0-9]*) echo "FAIL: model stub port is not numeric"; exit 1 ;;
esac

python3 -c '
import sys
path, marker = "/etc/hosts", sys.argv[1]
line = "127.0.0.1 llm.example %s\n" % marker
with open(path, encoding="utf-8") as fh:
    text = fh.read()
if marker not in text:
    text = line + ("" if not text or text.startswith("\n") else "") + text
    if text and not text.endswith("\n"):
        text += "\n"
try:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
except PermissionError:
    sys.exit(13)
' "$HOSTS_MARK" || sudo -n python3 -c '
import sys
path, marker = "/etc/hosts", sys.argv[1]
line = "127.0.0.1 llm.example %s\n" % marker
with open(path, encoding="utf-8") as fh:
    text = fh.read()
if marker not in text:
    text = line + text
    if text and not text.endswith("\n"):
        text += "\n"
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
' "$HOSTS_MARK" || { echo "FAIL: cannot map llm.example to 127.0.0.1"; exit 1; }
HOSTS_ADDED=1

python3 - "$STUB_PORT" <<'PY' || { echo "FAIL: llm.example did not resolve to 127.0.0.1"; exit 1; }
import socket, sys
port = int(sys.argv[1])
infos = socket.getaddrinfo("llm.example", port, type=socket.SOCK_STREAM)
addrs = {item[4][0] for item in infos}
if addrs != {"127.0.0.1"}:
    raise SystemExit("resolved %s" % (addrs,))
PY
curl -sf --max-time 2 "http://llm.example:${STUB_PORT}/v1" >/dev/null || {
  echo "FAIL: llm.example did not reach the stub"
  exit 1
}

MODEL="http://${USERINFO}@llm.example:${STUB_PORT}/v1"
python3 - "$MODEL" "$USERINFO" <<'PY' || exit 1
import sys
from urllib.parse import urlparse
model, userinfo = sys.argv[1], sys.argv[2]
parsed = urlparse(model)
if parsed.hostname != "llm.example":
    raise SystemExit("FAIL: model host is %r" % (parsed.hostname,))
if parsed.username != userinfo:
    raise SystemExit("FAIL: model userinfo is %r" % (parsed.username,))
if "127.0.0.1" in (parsed.netloc or ""):
    raise SystemExit("FAIL: model host must stay llm.example")
PY

CASE="$TH/both"
mkdir -p "$CASE"
PDF1="$CASE/oak.pdf"
PDF2="$CASE/pair.pdf"
MARKER="$CASE/spoken.txt"
BIN="$CASE/speak"
STATE="$CASE/state"
LOG="$CASE/meshd.log"
WORK="$CASE/work"
RAN="$CASE/ran"
mkdir -p "$STATE" "$WORK"
: >"$MARKER"
write_pdf "$PDF1" "The oak margin names the extracted page." "Oak page"
write_pdf "$PDF2" "The pairing code stays on this machine." "Pairing page"
write_speaker "$BIN" "$MARKER"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
python3 - "$PDF1" "$CASE/oak-body.json" <<'PY'
import json, sys
json.dump({"path": sys.argv[1], "speak": True}, open(sys.argv[2], "w"))
PY
python3 - "$PDF2" "$CASE/pair-body.json" <<'PY'
import json, sys
json.dump({"path": sys.argv[1], "speak": True}, open(sys.argv[2], "w"))
PY
start_daemon "$CASE" "$TOKEN" "$STATE" "$BIN" "$LOG"

code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/knowledge" "$CASE/oak-body.json" "$CASE/oak-post.json")"
[ "$code" = "201" ] || { echo "FAIL: oak POST /knowledge -> ${code}"; cat "$CASE/oak-post.json"; echo; cat "$LOG"; exit 1; }
python3 - "$CASE/oak-post.json" <<'PY' || { echo "FAIL: oak knowledge response"; cat "$CASE/oak-post.json"; echo; cat "$LOG"; exit 1; }
import json, sys
post = json.load(open(sys.argv[1]))
if post.get("title") != "Oak page":
    raise SystemExit("title is %r" % (post.get("title"),))
if post.get("spoken") is not True:
    raise SystemExit("spoken is %r" % (post.get("spoken"),))
PY

code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/knowledge" "$CASE/pair-body.json" "$CASE/pair-post.json")"
[ "$code" = "201" ] || { echo "FAIL: pairing POST /knowledge -> ${code}"; cat "$CASE/pair-post.json"; echo; cat "$LOG"; exit 1; }
python3 - "$CASE/pair-post.json" <<'PY' || { echo "FAIL: pairing knowledge response"; cat "$CASE/pair-post.json"; echo; cat "$LOG"; exit 1; }
import json, sys
post = json.load(open(sys.argv[1]))
if post.get("title") != "Pairing page":
    raise SystemExit("title is %r" % (post.get("title"),))
PY
[ "$(stub_hits)" = "0" ] || { echo "FAIL: ingest called the model"; exit 1; }

write_agent_req "$CASE/ask.json" "Oak page" "$WORK" "$MODEL" "reader.txt" "$RAN" present "build a reader" yes
code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/agent-note" "$CASE/ask.json" "$CASE/ask-out.json")"
[ "$code" = "200" ] || { echo "FAIL: oak ask -> ${code}"; cat "$CASE/ask-out.json"; echo; cat "$LOG"; exit 1; }
python3 - "$CASE/ask-out.json" "$WORK" "$RAN.count" "$USERINFO" <<'PY' || { echo "FAIL: oak confirmed ask"; cat "$CASE/ask-out.json"; echo; cat "$LOG"; exit 1; }
import json, os, stat, sys
data = json.load(open(sys.argv[1]))
work, count_path, userinfo = sys.argv[2], sys.argv[3], sys.argv[4]
if data.get("modelClass") != "user-subscription":
    raise SystemExit("modelClass is %r" % (data.get("modelClass"),))
if data.get("commandRan") is not True:
    raise SystemExit("commandRan is %r" % (data.get("commandRan"),))
draft = data.get("draft")
if draft != "reader.txt" or os.path.isabs(str(draft)):
    raise SystemExit("draft is %r" % (draft,))
files = [name for name in os.listdir(work) if os.path.isfile(os.path.join(work, name))]
if files != ["reader.txt"]:
    raise SystemExit("work files are %r" % (files,))
path = os.path.join(work, "reader.txt")
mode = stat.S_IMODE(os.stat(path).st_mode)
if mode != 0o600:
    raise SystemExit("mode is %o" % mode)
raw = open(path, "rb").read()
if b"sk-" in raw or userinfo.encode() in raw or b"@llm.example" in raw or b"pairing code" in raw:
    raise SystemExit("draft contains a secret, model userinfo, or the other note")
count = open(count_path, "rb").read()
if count != b"x":
    raise SystemExit("command ran %r" % (count,))
PY
[ "$(stub_hits)" = "1" ] || { echo "FAIL: oak ask model calls $(stub_hits)"; exit 1; }
python3 - "$STUB_BODIES" <<'PY' || { echo "FAIL: oak model request"; exit 1; }
import os, sys
root = sys.argv[1]
files = sorted(name for name in os.listdir(root) if name.endswith(".json"))
if files != ["1.json"]:
    raise SystemExit("bodies %r" % (files,))
raw = open(os.path.join(root, "1.json"), "rb").read()
if b"The oak margin names the extracted page." not in raw:
    raise SystemExit("oak sentence missing from the model request")
if b"pairing code" in raw:
    raise SystemExit("pairing note was sent to the model")
host = open(os.path.join(root, "1.host"), encoding="utf-8").read().strip()
if not host.startswith("llm.example:"):
    raise SystemExit("host %r" % (host,))
PY
cp "$WORK/reader.txt" "$CASE/draft.before"
cp "$RAN.count" "$CASE/count.before"

write_agent_req "$CASE/both.json" "page" "$WORK" "$MODEL" "reader.txt" "$RAN" present "build a reader" yes
code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/agent-note" "$CASE/both.json" "$CASE/both-out.json")"
[ "$code" = "409" ] || { echo "FAIL: both-note ask -> ${code}"; cat "$CASE/both-out.json"; echo; cat "$LOG"; exit 1; }
python3 - "$CASE/both-out.json" "$WORK" "$RAN.count" "$CASE/draft.before" "$CASE/count.before" <<'PY' || { echo "FAIL: both-note refusal"; cat "$CASE/both-out.json"; echo; cat "$LOG"; exit 1; }
import json, os, sys
data = json.load(open(sys.argv[1]))
work, count_path, draft_before, count_before = sys.argv[2:6]
if data.get("error") != "more than one note":
    raise SystemExit("error is %r" % (data.get("error"),))
files = sorted(name for name in os.listdir(work) if os.path.isfile(os.path.join(work, name)))
if files != ["reader.txt"]:
    raise SystemExit("work files are %r" % (files,))
draft = open(os.path.join(work, "reader.txt"), "rb").read()
if draft != open(draft_before, "rb").read():
    raise SystemExit("draft changed after the refusal")
count = open(count_path, "rb").read()
if count != open(count_before, "rb").read() or count != b"x":
    raise SystemExit("command ran %r" % (count,))
PY
[ "$(stub_hits)" = "1" ] || { echo "FAIL: both-note ask called the model"; exit 1; }
python3 - "$STUB_BODIES" <<'PY' || { echo "FAIL: model request changed"; exit 1; }
import os, sys
root = sys.argv[1]
files = sorted(name for name in os.listdir(root) if name.endswith(".json"))
if files != ["1.json"]:
    raise SystemExit("bodies %r" % (files,))
raw = open(os.path.join(root, "1.json"), "rb").read()
if b"The oak margin names the extracted page." not in raw or b"pairing code" in raw:
    raise SystemExit("recorded model request changed")
PY

echo "check-extracted-note-scope: ok"

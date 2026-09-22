#!/bin/sh
# Spare daemon: a local speech-to-text binary writes one note, and that note
# is drafted into one held file. The model stub listens on 127.0.0.1. A remote
# URL, a protocol-relative URL, or any string containing :// is not started
# and does not call the model. The held file is mode 600 and is not executed.
# A shell command runs only when confirm is true. This script starts the
# daemon and stops it. It uses port 8898, not 8899, and does not read a real
# home directory. It does not prove a microphone or a speaker.
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
grep -q 'MESH_STT' "$ROOT/install/payload/meshd/knowledge.ts" || {
  echo "FAIL: knowledge.ts does not name MESH_STT"
  exit 1
}
grep -q 'handleKnowledge' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route knowledge"
  exit 1
}
grep -q 'handleAgentNote' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route agent-note"
  exit 1
}

TH="$(mktemp -d)"
HOME_DIR="$TH/home"
STATE="$TH/state"
WORK="$TH/session"
AUDIO="$TH/clip.wav"
COLON_AUDIO="$TH/clip://wav"
LOG="$TH/meshd.log"
ALL="$TH/all.log"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
PORT=8898
SRV=
STUB=

cleanup() {
  ec=$?
  [ -n "${SRV:-}" ] || SRV=
  [ -n "${STUB:-}" ] || STUB=
  if [ -n "$SRV" ]; then
    kill "$SRV" 2>/dev/null || true
    n=0
    while kill -0 "$SRV" 2>/dev/null && [ "$n" -lt 20 ]; do
      sleep 0.1
      n=$((n + 1))
    done
    kill -KILL "$SRV" 2>/dev/null || true
    wait "$SRV" 2>/dev/null || true
  fi
  if [ -n "$STUB" ]; then
    kill "$STUB" 2>/dev/null || true
    n=0
    while kill -0 "$STUB" 2>/dev/null && [ "$n" -lt 20 ]; do
      sleep 0.1
      n=$((n + 1))
    done
    kill -KILL "$STUB" 2>/dev/null || true
    wait "$STUB" 2>/dev/null || true
  fi
  rm -rf "$TH"
  exit "$ec"
}
trap cleanup EXIT

case "$PORT" in
  8899) echo "FAIL: refusing port 8899"; exit 1 ;;
esac
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

mkdir -p "$HOME_DIR" "$STATE" "$WORK" "$TH/fakebin"
chmod 700 "$HOME_DIR" "$STATE" "$WORK"
printf 'RIFF' > "$AUDIO"
mkdir -p "$TH/clip:"
printf 'RIFF' > "$TH/clip:/wav"
: > "$ALL"

cat > "$TH/stt" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >> "$TH/stt-args"
printf '%s\n' "Heard on this machine"
printf '%s\n' "The rest stays in the note body"
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

# The port file is written only after Python imports http.server and binds.
# On the macOS CI runner that startup was still in progress after 5s, so the
# process was alive and stub.port did not exist yet.
python3 - "$TH/stub.port" "$TH/stub.body" "$TH/stub.path" "$TH/stub.headers" "$TH/stub.reply" "$TH/stub.hits" "$WORK" 2>"$TH/stub.err" <<'PY' &
import json, os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file, body_file, path_file, header_file, reply_file, hit_file, work = sys.argv[1:8]
reply = "touch " + work + "/draft-executed\n"
with open(reply_file, "w") as fh:
    fh.write(reply)

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        self._record(b"")
        self._empty()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(n) if n else b""
        self._record(raw)
        host = self.headers.get("Host", "")
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

    def do_PUT(self):
        self.do_POST()

    def _record(self, raw):
        with open(hit_file, "a") as fh:
            fh.write(self.command + " " + self.path + "\n")
        with open(body_file, "ab") as fh:
            fh.write(raw + b"\n")
        with open(path_file, "a") as fh:
            fh.write(self.path + "\n")
        with open(header_file, "a") as fh:
            fh.write(str(self.headers))
            fh.write("\n")

    def _empty(self):
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

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
STUB_PID="$STUB" STUB_PORT="$STUB_PORT" python3 - <<'PY'
import os, subprocess, sys
pid = os.environ["STUB_PID"]
port = int(os.environ["STUB_PORT"])

def fail(msg):
    sys.exit("FAIL: " + msg)

if sys.platform == "darwin":
    out = subprocess.run(
        ["lsof", "-nP", "-a", "-p", pid, "-iTCP", "-sTCP:LISTEN"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    rows = [ln for ln in out.stdout.splitlines() if "LISTEN" in ln]
    if not rows:
        fail("model stub has no listening socket")
    for ln in rows:
        if "0.0.0.0" in ln or "*:" in ln or "[::]:" in ln:
            fail("model stub listens outside 127.0.0.1")
        if ("127.0.0.1:%d" % port) not in ln:
            fail("model stub is not on 127.0.0.1:%d" % port)
else:
    inodes = set()
    fd_dir = "/proc/%s/fd" % pid
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink("%s/%s" % (fd_dir, name))
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            inodes.add(target[len("socket:["):-1])
    found = False
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            parts = line.split()
            if len(parts) < 10 or parts[3] != "0A" or parts[9] not in inodes:
                continue
            ip, hexport = parts[1].split(":")
            if int(hexport, 16) != port:
                continue
            found = True
            if ip not in ("0100007F", "00000000000000000000000001000000"):
                fail("model stub listens on %s" % parts[1])
    if not found:
        fail("model stub has no listening socket")
PY
echo "check-spoken-note-to-app: model stub is on 127.0.0.1:${STUB_PORT}"

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

start_daemon() {
  stt_bin="$1"
  stop_srv
  mkdir -p "$STATE"
  PATH="$TH/fakebin:$PATH" \
  MESHD_PORT="$PORT" \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$STATE" \
  MESHD_TELEMETRY=off \
  MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
  MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
  MESHD_KB_PATH="$TH/kb.sqlite" \
  MESH_STT="$stt_bin" \
  HOME="$HOME_DIR" \
  bun "$ROOT/install/payload/meshd/server.ts" >"$LOG" 2>&1 &
  SRV=$!
  up=0
  i=0
  while [ "$i" -lt 100 ]; do
    if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      up=1
      break
    fi
    kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited before listening"; cat "$LOG"; exit 1; }
    sleep 0.1
    i=$((i + 1))
  done
  [ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on $PORT"; cat "$LOG"; exit 1; }
}

json_notes() {
  python3 -c 'import os, sys
root = os.path.join(sys.argv[1], "knowledge")
if not os.path.isdir(root):
    print(0)
    raise SystemExit(0)
print(sum(1 for name in os.listdir(root) if name.endswith(".json")))' "$1"
}

mode_of() {
  python3 -c 'import os, stat, sys; print(format(stat.S_IMODE(os.stat(sys.argv[1]).st_mode), "o"))' "$1"
}

post_auth() {
  curl --connect-timeout 1 --max-time "$3" -sS -o "$1" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data "$2" \
    "http://127.0.0.1:$PORT/knowledge" || true
}

post_note() {
  curl --connect-timeout 1 --max-time 12 -sS -o "$2" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$1" \
    "http://127.0.0.1:$PORT/agent-note" || true
}

quiet_side() {
  label="$1"
  if [ -s "$TH/stub.hits" ] || [ -s "$TH/stub.body" ]; then
    echo "FAIL: $label called the model"
    cat "$TH/stub.hits" 2>/dev/null || true
    exit 1
  fi
  if [ -s "$TH/stt-args" ]; then
    echo "FAIL: $label ran the transcriber"
    exit 1
  fi
  if [ -e "$TH/curl-ran" ] || [ -e "$TH/wget-ran" ]; then
    echo "FAIL: $label spawned a downloader"
    exit 1
  fi
  [ "$(json_notes "$STATE")" -eq 0 ] || { echo "FAIL: $label wrote a note"; exit 1; }
  [ ! -e "$WORK/held-note.txt" ] || { echo "FAIL: $label wrote a file"; exit 1; }
  [ ! -e "$WORK/draft-executed" ] || { echo "FAIL: $label executed a draft"; exit 1; }
}

AUDIO_JSON="$(python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1]}))' "$AUDIO")"

bad_stt() {
  label="$1"
  bin="$2"
  start_daemon "$bin"
  code="$(post_auth "$TH/bad.json" "$AUDIO_JSON" 5)"
  if [ "$code" = "201" ] || [ "$code" = "000" ]; then
    echo "FAIL: $label -> ${code}"
    cat "$TH/bad.json" 2>/dev/null || true
    echo
    exit 1
  fi
  quiet_side "$label"
  echo "check-spoken-note-to-app: $label"
}

bad_stt "remote transcriber did not run" "http://127.0.0.1:${STUB_PORT}/stt"
bad_stt "https transcriber did not run" "https://127.0.0.1:${STUB_PORT}/stt"
bad_stt "protocol-relative transcriber did not run" "//127.0.0.1/stt"
bad_stt "scheme transcriber did not run" "${TH}/bin://stt"

start_daemon "$TH/stt"
echo "check-spoken-note-to-app: spare daemon is on 127.0.0.1:${PORT}"

bad_audio() {
  label="$1"
  target="$2"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1]}))' "$target")"
  code="$(post_auth "$TH/rej.json" "$payload" 5)"
  if [ "$code" = "201" ] || [ "$code" = "000" ]; then
    echo "FAIL: $label -> ${code}"
    cat "$TH/rej.json" 2>/dev/null || true
    echo
    exit 1
  fi
  quiet_side "$label"
  echo "check-spoken-note-to-app: $label"
}

bad_audio "remote audio did not run" "http://127.0.0.1:${STUB_PORT}/clip.wav"
bad_audio "https audio did not run" "https://127.0.0.1:${STUB_PORT}/clip.wav"
bad_audio "protocol-relative audio did not run" "//127.0.0.1/clip.wav"
bad_audio "audio containing :// did not run" "$COLON_AUDIO"

code="$(post_auth "$TH/post.json" "$AUDIO_JSON" 5)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge audio -> ${code}"; cat "$TH/post.json"; echo; cat "$LOG"; exit 1; }
[ "$(json_notes "$STATE")" -eq 1 ] || { echo "FAIL: expected one spoken note"; exit 1; }
python3 - "$TH/post.json" "$TH/note.id" "$AUDIO" "$TH/stt-args" "$STATE" <<'PY'
import json, os, sys
post_path, id_path, audio, args_path, state = sys.argv[1:6]
post = json.load(open(post_path))
if post.get("spoken") is not False:
    raise SystemExit("FAIL: spoken is %r" % (post.get("spoken"),))
if post.get("title") != "Heard on this machine":
    raise SystemExit("FAIL: title is %r" % (post.get("title"),))
if not isinstance(post.get("id"), str) or not post["id"]:
    raise SystemExit("FAIL: missing id")
open(id_path, "w").write(post["id"])
args = open(args_path).read().splitlines()
if args != [audio]:
    raise SystemExit("FAIL: transcriber args are %r" % (args,))
note_path = os.path.join(state, "knowledge", post["id"] + ".json")
note = json.load(open(note_path))
body = "Heard on this machine\nThe rest stays in the note body"
if note.get("body") != body:
    raise SystemExit("FAIL: note body is %r" % (note.get("body"),))
if note.get("title") != "Heard on this machine":
    raise SystemExit("FAIL: stored title is %r" % (note.get("title"),))
PY
echo "check-spoken-note-to-app: transcript is the note body"

ID="$(cat "$TH/note.id")"
note_file="$STATE/knowledge/${ID}.json"
fmode="$(mode_of "$note_file")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
wmode="$(mode_of "$WORK")"
[ "$wmode" = "700" ] || { echo "FAIL: session directory mode is $wmode, want 700"; exit 1; }
echo "check-spoken-note-to-app: file mode 600"
echo "check-spoken-note-to-app: directory mode 700"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/one.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge/$ID" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge/:id -> ${code}"; cat "$TH/one.json"; echo; exit 1; }
python3 - "$TH/one.json" "$ID" <<'PY'
import json, sys
note = json.load(open(sys.argv[1]))
if note.get("id") != sys.argv[2]:
    raise SystemExit("FAIL: read id is %r" % (note.get("id"),))
if note.get("title") != "Heard on this machine":
    raise SystemExit("FAIL: read title is %r" % (note.get("title"),))
if note.get("body") != "Heard on this machine\nThe rest stays in the note body":
    raise SystemExit("FAIL: read body is %r" % (note.get("body"),))
PY
echo "check-spoken-note-to-app: note read by id"
[ "$(wc -l < "$TH/stt-args" | tr -d ' ')" -eq 1 ] || { echo "FAIL: reading the note spawned the transcriber"; exit 1; }
if [ -s "$TH/stub.hits" ] || [ -s "$TH/stub.body" ]; then
  echo "FAIL: reading the note called the model"
  exit 1
fi

refuse_model() {
  label="$1"
  model="$2"
  NOTE_ID="$ID" WORK="$WORK" MODEL="$model" python3 - "$TH/refuse-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": os.environ["NOTE_ID"],
    "cwd": os.environ["WORK"],
    "model": os.environ["MODEL"],
    "file": "held-note.txt",
    "command": "sh " + os.environ["WORK"] + "/held-note.txt",
    "confirm": True,
}))
PY
  code="$(post_note "$TH/refuse-req.json" "$TH/refuse.json")"
  [ "$code" = "400" ] || { echo "FAIL: $label -> ${code}"; cat "$TH/refuse.json"; echo; exit 1; }
  python3 - "$TH/refuse.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("error") != "model url not allowed":
    raise SystemExit("FAIL: refused model error is %r" % (data.get("error"),))
PY
  if [ -s "$TH/stub.hits" ] || [ -s "$TH/stub.body" ]; then
    echo "FAIL: $label called the model"
    exit 1
  fi
  [ ! -e "$WORK/held-note.txt" ] || { echo "FAIL: $label wrote a file"; exit 1; }
  [ ! -e "$WORK/draft-executed" ] || { echo "FAIL: $label executed a draft"; exit 1; }
  [ ! -e "$WORK/confirmed-ran" ] || { echo "FAIL: $label ran a command"; exit 1; }
  [ "$(json_notes "$STATE")" -eq 1 ] || { echo "FAIL: $label wrote another note"; exit 1; }
  echo "check-spoken-note-to-app: $label"
}

refuse_model "ftp model did not run" "ftp://127.0.0.1:${STUB_PORT}/v1"
refuse_model "notes model did not run" "notes://127.0.0.1:${STUB_PORT}/v1"

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
python3 - "$TH/job.json" "$WORK/held-note.txt" "$TH/stub.reply" "$TH/stub.body" "$TH/stub.path" "$TH/stub.headers" "$WORK" <<'PY'
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
if draft != "held-note.txt" or os.path.isabs(draft) or "://" in draft or draft.startswith(".."):
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
if payload.get("model") != "local":
    raise SystemExit("FAIL: stub saw a model name that is not a class")
messages = json.dumps(payload.get("messages"))
if "Heard on this machine" not in messages or "The rest stays in the note body" not in messages:
    raise SystemExit("FAIL: stub did not receive the spoken note")
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
PY
[ ! -e "$WORK/draft-executed" ] || { echo "FAIL: drafted file was executed"; exit 1; }
[ "$(json_notes "$STATE")" -eq 1 ] || { echo "FAIL: draft wrote another note"; exit 1; }
[ "$(wc -l < "$TH/stt-args" | tr -d ' ')" -eq 1 ] || { echo "FAIL: draft spawned the transcriber"; exit 1; }
echo "check-spoken-note-to-app: held file is the stub reply"
echo "check-spoken-note-to-app: drafted file was not executed"
echo "check-spoken-note-to-app: command without confirm did not run"

NOTE_ID="$ID" WORK="$WORK" STUB_PORT="$STUB_PORT" python3 - "$TH/confirm-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": os.environ["NOTE_ID"],
    "cwd": os.environ["WORK"],
    "model": "http://127.0.0.1:%s/v1" % os.environ["STUB_PORT"],
    "file": "held-note.txt",
    "command": "touch " + os.environ["WORK"] + "/confirmed-ran",
    "confirm": True,
}))
PY
code="$(post_note "$TH/confirm-req.json" "$TH/confirm.json")"
[ "$code" = "200" ] || { echo "FAIL: confirmed POST /agent-note -> ${code}"; cat "$TH/confirm.json"; echo; cat "$LOG"; exit 1; }
python3 - "$TH/confirm.json" "$WORK/held-note.txt" "$TH/stub.reply" "$TH/stub.path" "$WORK" <<'PY'
import json, os, stat, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
if data.get("modelClass") not in ("local", "user-subscription"):
    raise SystemExit("FAIL: modelClass is %r" % (data.get("modelClass"),))
if data.get("modelClass") != "local":
    raise SystemExit("FAIL: localhost model was not class local")
if data.get("commandRan") is not True or data.get("held") is not False:
    raise SystemExit("FAIL: confirmed command did not run")
if data.get("draft") != "held-note.txt":
    raise SystemExit("FAIL: confirmed draft name is %r" % (data.get("draft"),))
for needle in ("127.0.0.1", "http", "supabase", "chat/completions"):
    if needle in raw:
        raise SystemExit("FAIL: transcript contains %s" % needle)
reply = open(sys.argv[3], "rb").read()
got = open(sys.argv[2], "rb").read()
if got != reply:
    raise SystemExit("FAIL: confirmed draft is not the stub reply")
mode = stat.S_IMODE(os.stat(sys.argv[2]).st_mode)
if mode != 0o600 or mode & 0o111:
    raise SystemExit("FAIL: confirmed draft mode is %o" % mode)
paths = [ln.strip() for ln in open(sys.argv[4]).read().splitlines() if ln.strip()]
if paths != ["/v1/chat/completions", "/v1/chat/completions"]:
    raise SystemExit("FAIL: stub paths are %r" % (paths,))
names = sorted(os.listdir(sys.argv[5]))
if names != ["confirmed-ran", "held-note.txt"]:
    raise SystemExit("FAIL: session files are %r" % (names,))
if os.path.exists(os.path.join(sys.argv[5], "draft-executed")):
    raise SystemExit("FAIL: drafted file was executed")
PY
[ -f "$WORK/confirmed-ran" ] || { echo "FAIL: confirmed command did not run"; exit 1; }
[ ! -e "$WORK/draft-executed" ] || { echo "FAIL: drafted file was executed after confirm"; exit 1; }
[ "$(json_notes "$STATE")" -eq 1 ] || { echo "FAIL: confirm wrote another note"; exit 1; }
echo "check-spoken-note-to-app: confirmed command ran"
echo "check-spoken-note-to-app: unconfirmed command stayed unrun"

if [ -d "$HOME_DIR/.mesh/knowledge" ]; then
  echo "FAIL: a note was written under the home directory"
  exit 1
fi
if grep -i -E -q 'supabase\.co|ai-gateway' "$ALL" "$LOG"; then
  echo "FAIL: daemon log names supabase or the AI gateway"
  exit 1
fi

# Linux reads /proc. Darwin has no /proc; ps -E and lsof check the same facts.
if [ "$(uname -s)" = "Darwin" ]; then
  command -v lsof >/dev/null 2>&1 || { echo "FAIL: lsof is required on Darwin"; exit 1; }
  SRV_PID="$SRV" python3 - <<'PY'
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
if "MESHD_TELEMETRY=off" not in env_text.split():
    sys.exit("FAIL: daemon is not running with telemetry off")

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
  SRV_PID="$SRV" python3 - <<'PY'
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

env_ok = False
try:
    raw = open(f"/proc/{root}/environ", "rb").read().split(b"\0")
except OSError:
    raw = []
for item in raw:
    if item == b"MESHD_TELEMETRY=off":
        env_ok = True
        break
if not env_ok:
    sys.exit("FAIL: daemon is not running with telemetry off")
if bad:
    sys.exit("FAIL: daemon has a non-loopback socket: %s" % ", ".join(bad))
PY
fi
echo "check-spoken-note-to-app: no supabase.co call"
echo "check-spoken-note-to-app: OK"

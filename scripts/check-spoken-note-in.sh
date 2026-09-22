#!/bin/sh
# Spare daemon: a local audio file plus MESH_STT becomes one knowledge note.
# The transcript is the note body. A scheme:// value or any other remote URL
# is not started. A missing binary or a nonzero exit writes no note. Speak-out
# (MESH_TTS) still receives the PDF note text. This script starts the daemon
# and stops it. It does not use port 8899, does not read a real home directory,
# and does not prove a microphone or a speaker.
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

if grep -E -n 'supabase|fetch\(|ai-gateway' "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: knowledge.ts reaches the network"
  exit 1
fi
if grep -E -n 'Bun\.spawn\(\[?"?(sh|bash|curl|wget)' "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: knowledge.ts spawns a shell or a downloader"
  exit 1
fi
grep -q 'MESH_STT' "$ROOT/install/payload/meshd/knowledge.ts" || {
  echo "FAIL: knowledge.ts does not name MESH_STT"
  exit 1
}
grep -q 'MESH_TTS' "$ROOT/install/payload/meshd/knowledge.ts" || {
  echo "FAIL: knowledge.ts dropped speak-out"
  exit 1
}
grep -q 'handleKnowledge' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route knowledge"
  exit 1
}

TH="$(mktemp -d)"
HOME_DIR="$TH/home"
OK_STATE="$TH/state-ok"
AUDIO="$TH/clip.wav"
PDF="$TH/paper.pdf"
LOG="$TH/meshd.log"
ALL="$TH/all.log"
HITS="$TH/hits"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
SRV=
STUB=
PORT="$(python3 - <<'PY'
import socket
reserved = {8898, 8899}
for _ in range(16):
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    if port not in reserved:
        print(port)
        raise SystemExit(0)
raise SystemExit("FAIL: no spare localhost port")
PY
)"
case "$PORT" in
  ""|8898|8899) echo "FAIL: spare daemon port is not free"; exit 1 ;;
esac

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
  if [ -f "$TH/slow.pid" ]; then
    slowpid="$(tr -d '[:space:]' < "$TH/slow.pid" 2>/dev/null || true)"
    if [ -n "${slowpid:-}" ]; then
      kill "$slowpid" 2>/dev/null || true
      kill -KILL "$slowpid" 2>/dev/null || true
    fi
  fi
  stop_srv
  stop_stub
  rm -rf "$TH"
  exit "$ec"
}
trap cleanup EXIT

mkdir -p "$HOME_DIR" "$OK_STATE" "$TH/fakebin"
printf 'RIFF' > "$AUDIO"
: > "$ALL"

cat > "$TH/stt" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >> "$TH/stt-args"
printf '%s\n' "Heard on this machine"
printf '%s\n' "The rest stays in the note body"
exit 0
EOF
cat > "$TH/stt-fail" <<EOF
#!/bin/sh
printf '%s\n' ran >> "$TH/fail-ran"
exit 1
EOF
cat > "$TH/stt-slow" <<EOF
#!/bin/sh
echo \$\$ > "$TH/slow.pid"
printf '%s\n' "This line must not become a note"
exec sleep 30
EOF
cat > "$TH/tts" <<EOF
#!/bin/sh
cat > "$TH/tts-out"
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
chmod 700 "$TH/stt" "$TH/stt-fail" "$TH/stt-slow" "$TH/tts" "$TH/fakebin/curl" "$TH/fakebin/wget"

python3 - "$PDF" <<'PY'
import sys
path = sys.argv[1]
stream = b"BT /F1 12 Tf 72 720 Td (The body stays on this machine) Tj ET\n"
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

python3 - "$TH/stub.port" "$HITS" 2>"$TH/stub.err" <<'PY' &
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
STUB=$!
i=0
while [ ! -s "$TH/stub.port" ] && [ "$i" -lt 300 ]; do
  kill -0 "$STUB" 2>/dev/null || {
    echo "FAIL: decoy exited"
    tail -n 40 "$TH/stub.err" || true
    exit 1
  }
  sleep 0.1
  i=$((i + 1))
done
if [ ! -s "$TH/stub.port" ]; then
  echo "FAIL: decoy port file never appeared"
  tail -n 40 "$TH/stub.err" || true
  exit 1
fi
DECOY="$(tr -d '[:space:]' < "$TH/stub.port")"
if [ -z "$DECOY" ] || [ "$DECOY" = "$PORT" ] || [ "$DECOY" = "8899" ] || [ "$DECOY" = "8898" ]; then
  echo "FAIL: decoy port is not a spare localhost port"
  exit 1
fi

json_notes() {
  dir="$1/knowledge"
  if [ ! -d "$dir" ]; then
    echo 0
    return 0
  fi
  set -- "$dir"/*.json
  if [ ! -e "$1" ]; then
    echo 0
    return 0
  fi
  echo "$#"
}

mode_of() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1"
}

start_daemon() {
  state_dir="$1"
  stt_bin="$2"
  tts_bin="${3:-}"
  stop_srv
  mkdir -p "$state_dir"
  PATH="$TH/fakebin:$PATH" \
  MESHD_PORT="$PORT" \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$state_dir" \
  MESHD_TELEMETRY=off \
  MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
  MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
  MESHD_KB_PATH="$TH/kb.sqlite" \
  MESH_STT="$stt_bin" \
  MESH_TTS="$tts_bin" \
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

post_auth() {
  curl --connect-timeout 1 --max-time "$3" -sS -o "$1" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data "$2" \
    "http://127.0.0.1:$PORT/knowledge" || true
}

assert_quiet() {
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
}

hits_ok() {
  if [ -s "$HITS" ]; then
    echo "FAIL: a remote URL received requests"
    exit 1
  fi
  if [ -e "$TH/curl-ran" ] || [ -e "$TH/wget-ran" ]; then
    echo "FAIL: a downloader was spawned"
    exit 1
  fi
}

start_daemon "$OK_STATE" "$TH/stt" "$TH/tts"
AUDIO_JSON="$(python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1]}))' "$AUDIO")"
code="$(post_auth "$TH/post.json" "$AUDIO_JSON" 5)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge audio -> ${code}"; cat "$TH/post.json"; echo; cat "$LOG"; exit 1; }
[ "$(json_notes "$OK_STATE")" -eq 1 ] || { echo "FAIL: expected one spoken note"; exit 1; }

python3 - "$TH/post.json" "$TH/note.id" "$AUDIO" "$TH/stt-args" "$OK_STATE" <<'PY'
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
echo "check-spoken-note-in: transcript is the note body"

note_file="$OK_STATE/knowledge/$(cat "$TH/note.id").json"
fmode="$(mode_of "$note_file")"
fmode="${fmode#0}"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
echo "check-spoken-note-in: file mode 600"
dmode="$(mode_of "$OK_STATE/knowledge")"
dmode="${dmode#0}"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-spoken-note-in: directory mode 700"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; cat "$TH/list.json"; echo; exit 1; }
python3 - "$TH/list.json" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
if "The rest stays in the note body" in raw:
    raise SystemExit("FAIL: list includes the note body")
data = json.loads(raw)
if set(data.keys()) != {"notes"}:
    raise SystemExit("FAIL: list keys are %r" % (sorted(data.keys()),))
notes = data["notes"]
if len(notes) != 1:
    raise SystemExit("FAIL: list has %d notes" % (len(notes),))
if set(notes[0].keys()) != {"id", "title"}:
    raise SystemExit("FAIL: list note keys are %r" % (sorted(notes[0].keys()),))
if notes[0]["title"] != "Heard on this machine":
    raise SystemExit("FAIL: list title is %r" % (notes[0]["title"],))
PY
echo "check-spoken-note-in: list is id and title"

ID="$(cat "$TH/note.id")"
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/one.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge/$ID" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge/:id -> ${code}"; cat "$TH/one.json"; echo; exit 1; }
python3 - "$TH/one.json" <<'PY'
import json, sys
note = json.load(open(sys.argv[1]))
if note.get("body") != "Heard on this machine\nThe rest stays in the note body":
    raise SystemExit("FAIL: single note hid the transcript")
PY

reject_audio() {
  label="$1"
  target="$2"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1]}))' "$target")"
  before="$(wc -l < "$TH/stt-args" | tr -d ' ')"
  code="$(post_auth "$TH/rej.json" "$payload" 5)"
  if [ "$code" = "201" ] || [ "$code" = "000" ]; then
    echo "FAIL: $label -> ${code}"
    cat "$TH/rej.json" 2>/dev/null || true
    echo
    exit 1
  fi
  after="$(wc -l < "$TH/stt-args" | tr -d ' ')"
  [ "$before" = "$after" ] || { echo "FAIL: $label spawned the transcriber"; exit 1; }
  [ "$(json_notes "$OK_STATE")" -eq 1 ] || { echo "FAIL: $label wrote a note"; exit 1; }
  hits_ok
  echo "check-spoken-note-in: $label"
}

reject_audio "remote audio did not run" "http://127.0.0.1:${DECOY}/clip.wav"
reject_audio "https audio did not run" "https://example.com/clip.wav"
reject_audio "scheme audio did not run" "file://${AUDIO}"
reject_audio "protocol-relative audio did not run" "//127.0.0.1/clip.wav"

missing_payload="$(python3 -c 'import json,sys; print(json.dumps({"audio": sys.argv[1]}))' "$TH/missing-clip.wav")"
code="$(post_auth "$TH/miss.json" "$missing_payload" 5)"
[ "$code" != "201" ] || { echo "FAIL: missing audio wrote a note"; exit 1; }
[ "$(wc -l < "$TH/stt-args" | tr -d ' ')" -eq 1 ] || { echo "FAIL: missing audio spawned"; exit 1; }
[ "$(json_notes "$OK_STATE")" -eq 1 ] || { echo "FAIL: missing audio changed the store"; exit 1; }
echo "check-spoken-note-in: missing audio did not run"

PDF_JSON="$(python3 -c 'import json,sys; print(json.dumps({"path": sys.argv[1], "speak": True}))' "$PDF")"
code="$(post_auth "$TH/pdf.json" "$PDF_JSON" 5)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge pdf -> ${code}"; cat "$TH/pdf.json"; echo; cat "$LOG"; exit 1; }
python3 - "$TH/pdf.json" "$TH/tts-out" <<'PY'
import json, sys
post = json.load(open(sys.argv[1]))
if post.get("spoken") is not True:
    raise SystemExit("FAIL: speak-out returned spoken %r" % (post.get("spoken"),))
if post.get("title") != "Spare note":
    raise SystemExit("FAIL: pdf title is %r" % (post.get("title"),))
heard = open(sys.argv[2]).read()
if "Spare note" not in heard:
    raise SystemExit("FAIL: MESH_TTS did not receive the note")
PY
[ "$(wc -l < "$TH/stt-args" | tr -d ' ')" -eq 1 ] || { echo "FAIL: speak-out spawned the transcriber"; exit 1; }
[ "$(json_notes "$OK_STATE")" -eq 2 ] || { echo "FAIL: pdf note was not written"; exit 1; }
echo "check-spoken-note-in: speak-out still hands the note to MESH_TTS"

# Loopback skips the bearer, which is the existing rule. A browser Origin is
# still rejected before that exemption, so this request must not write or spawn.
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/anon.json" -w '%{http_code}' \
  -H 'content-type: application/json' \
  -H 'origin: https://evil.example' \
  --data "$AUDIO_JSON" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "401" ] || { echo "FAIL: cross-site request -> ${code}"; cat "$TH/anon.json"; echo; exit 1; }
[ "$(json_notes "$OK_STATE")" -eq 2 ] || { echo "FAIL: cross-site request wrote a note"; exit 1; }
[ "$(wc -l < "$TH/stt-args" | tr -d ' ')" -eq 1 ] || { echo "FAIL: cross-site request spawned"; exit 1; }
echo "check-spoken-note-in: cross-site request wrote no note"

assert_quiet
hits_ok
if [ -d "$HOME_DIR/.mesh/knowledge" ]; then
  echo "FAIL: a note was written under the home directory"
  exit 1
fi
echo "check-spoken-note-in: no supabase.co request"

bad_stt() {
  label="$1"
  bin="$2"
  state="$TH/state-$3"
  mkdir -p "$state"
  start_daemon "$state" "$bin" ""
  code="$(post_auth "$TH/bad.json" "$AUDIO_JSON" 5)"
  if [ "$code" = "201" ] || [ "$code" = "000" ]; then
    echo "FAIL: $label -> ${code}"
    cat "$TH/bad.json" 2>/dev/null || true
    echo
    exit 1
  fi
  [ "$(json_notes "$state")" -eq 0 ] || { echo "FAIL: $label wrote a note"; exit 1; }
  [ "$(wc -l < "$TH/stt-args" | tr -d ' ')" -eq 1 ] || { echo "FAIL: $label spawned the local transcriber"; exit 1; }
  hits_ok
  echo "check-spoken-note-in: $label"
}

bad_stt "http URL did not run" "http://127.0.0.1:${DECOY}/stt" "http"
bad_stt "https URL did not run" "https://example.com/v1/stt" "https"
bad_stt "scheme URL did not run" "stt://transcribe" "scheme"
bad_stt "protocol-relative URL did not run" "//127.0.0.1/stt" "relative"
bad_stt "missing binary wrote no note" "$TH/missing-stt" "missing"
bad_stt "unset binary wrote no note" "" "unset"

FAIL_STATE="$TH/state-fail"
mkdir -p "$FAIL_STATE"
start_daemon "$FAIL_STATE" "$TH/stt-fail" ""
code="$(post_auth "$TH/fail.json" "$AUDIO_JSON" 5)"
[ "$code" != "201" ] || { echo "FAIL: nonzero exit wrote a note"; cat "$TH/fail.json"; echo; exit 1; }
[ "$(json_notes "$FAIL_STATE")" -eq 0 ] || { echo "FAIL: nonzero exit left a note"; exit 1; }
[ -s "$TH/fail-ran" ] || { echo "FAIL: nonzero binary did not run"; exit 1; }
echo "check-spoken-note-in: nonzero exit wrote no note"

SLOW_STATE="$TH/state-slow"
mkdir -p "$SLOW_STATE"
start_daemon "$SLOW_STATE" "$TH/stt-slow" ""
started="$(date +%s)"
code="$(post_auth "$TH/slow.json" "$AUDIO_JSON" 20)"
elapsed="$(( $(date +%s) - started ))"
[ "$code" != "201" ] || { echo "FAIL: timed-out transcriber wrote a note"; exit 1; }
[ "$code" != "000" ] || { echo "FAIL: timed-out transcriber did not return"; exit 1; }
[ "$elapsed" -ge 5 ] || { echo "FAIL: timeout returned in ${elapsed}s"; exit 1; }
[ "$elapsed" -lt 16 ] || { echo "FAIL: timeout took ${elapsed}s"; exit 1; }
[ "$(json_notes "$SLOW_STATE")" -eq 0 ] || { echo "FAIL: timeout left a note"; exit 1; }
[ -s "$TH/slow.pid" ] || { echo "FAIL: timeout case did not start the binary"; exit 1; }
slowpid="$(tr -d '[:space:]' < "$TH/slow.pid")"
if kill -0 "$slowpid" 2>/dev/null; then
  echo "FAIL: timed out transcriber is still running"
  exit 1
fi
echo "check-spoken-note-in: timeout wrote no note"

stop_srv
if grep -i -E -n 'supabase\.co|ai-gateway' "$ALL"; then
  echo "FAIL: daemon log names supabase or the AI gateway"
  exit 1
fi
hits_ok
echo "check-spoken-note-in: OK"

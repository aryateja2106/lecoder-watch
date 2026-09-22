#!/bin/sh
# Spare daemon: read one local note, ask the caller's model for a draft,
# and write that text to one held file in the session directory. A missing
# note is not sent to the model. A shell command runs only when confirm is
# true. The note stays on this machine: the model stub is loopback, and the
# daemon is not allowed a socket to supabase.co. This script starts the
# daemon and stops it. It does not use port 8899 and does not kill a
# foreign listener.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

if grep -E -n 'supabase|ai-gateway' \
  "$ROOT/install/payload/meshd/agent-note.ts" \
  "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: note path names supabase or the AI gateway"
  exit 1
fi

TH="$(mktemp -d)"
STATE="$TH/state"
WORK="$TH/session"
PDF="$TH/paper.pdf"
LOG="$TH/meshd.log"
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

mkdir -p "$WORK"
python3 - "$TH/stub.port" "$TH/stub.body" "$TH/stub.path" "$TH/stub.headers" "$TH/stub.reply" <<'PY' &
import json, os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file, body_file, path_file, header_file, reply_file = sys.argv[1:6]
reply = "Draft stays on this machine.\n"
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
tmp_port = port_file + ".tmp"
with open(tmp_port, "w") as fh:
    fh.write(str(server.server_address[1]))
    fh.write("\n")
os.rename(tmp_port, port_file)
server.serve_forever()
PY
STUB=$!
i=0
while [ ! -s "$TH/stub.port" ] && [ "$i" -lt 50 ]; do
  kill -0 "$STUB" 2>/dev/null || { echo "FAIL: model stub exited"; exit 1; }
  sleep 0.1
  i=$((i + 1))
done
STUB_PORT="$(tr -d '[:space:]' < "$TH/stub.port")"
if [ -z "$STUB_PORT" ] || [ "$STUB_PORT" = "$PORT" ] || [ "$STUB_PORT" = "8899" ] || [ "$STUB_PORT" = "8898" ]; then
  echo "FAIL: model stub port is not a spare localhost port"
  exit 1
fi
echo "check-note-to-app: model stub is on 127.0.0.1:${STUB_PORT}"

MESHD_PORT=$PORT \
MESHD_HOST=127.0.0.1 \
MESHD_TOKEN="$TOKEN" \
MESHD_STATE="$STATE" \
MESHD_TELEMETRY=off \
MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
MESHD_KB_PATH="$TH/kb.sqlite" \
HOME="$TH" \
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
[ "$up" -eq 1 ] || { echo "FAIL: meshd never came up"; cat "$LOG"; exit 1; }
echo "check-note-to-app: spare daemon is on 127.0.0.1:${PORT}"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/post.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "{\"path\":\"${PDF}\"}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; echo; cat "$LOG"; exit 1; }
python3 - "$TH/post.json" "$TH/id" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
ident = data.get("id")
if not isinstance(ident, str) or not ident:
    raise SystemExit("FAIL: POST /knowledge returned no id")
open(sys.argv[2], "w").write(ident)
PY
ID="$(cat "$TH/id")"
[ -f "$STATE/knowledge/${ID}.json" ] || { echo "FAIL: note is not in the local knowledge store"; exit 1; }
echo "check-note-to-app: local note stored"

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
[ ! -e "$TH/stub.body" ] || { echo "FAIL: missing note called the model"; exit 1; }
[ ! -e "$WORK/missing-ran" ] || { echo "FAIL: missing note ran a command"; exit 1; }
[ ! -e "$WORK/draft.txt" ] || { echo "FAIL: missing note wrote a file"; exit 1; }
echo "check-note-to-app: missing note did not call the model"

NOTE_ID="$ID" WORK="$WORK" python3 - "$TH/refuse-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": os.environ["NOTE_ID"],
    "cwd": os.environ["WORK"],
    "model": "ftp://127.0.0.1/v1",
    "command": "touch " + os.environ["WORK"] + "/refused-ran",
    "confirm": True,
}))
PY
code="$(post_note "$TH/refuse-req.json" "$TH/refuse.json")"
[ "$code" = "400" ] || { echo "FAIL: refused url -> ${code}"; cat "$TH/refuse.json"; echo; exit 1; }
python3 - "$TH/refuse.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("error") != "model url not allowed":
    raise SystemExit("FAIL: refused url was not rejected")
PY
[ ! -e "$TH/stub.body" ] || { echo "FAIL: refused url called the model"; exit 1; }
[ ! -e "$WORK/refused-ran" ] || { echo "FAIL: refused url ran a command"; exit 1; }
[ ! -e "$WORK/draft.txt" ] || { echo "FAIL: refused url wrote a file"; exit 1; }
echo "check-note-to-app: refused url was not fetched"

NOTE_ID="$ID" WORK="$WORK" STUB_PORT="$STUB_PORT" python3 - "$TH/job-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": os.environ["NOTE_ID"],
    "cwd": os.environ["WORK"],
    "model": "http://127.0.0.1:%s/v1" % os.environ["STUB_PORT"],
    "command": "touch " + os.environ["WORK"] + "/held-ran",
    "confirm": False,
}))
PY
code="$(post_note "$TH/job-req.json" "$TH/job.json")"
[ "$code" = "200" ] || { echo "FAIL: POST /agent-note -> ${code}"; cat "$TH/job.json"; echo; cat "$LOG"; exit 1; }
python3 - "$TH/job.json" "$WORK/draft.txt" "$TH/stub.reply" "$TH/stub.body" "$TH/stub.path" "$TH/stub.headers" <<'PY'
import json, os, stat, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
if data.get("modelClass") not in ("local", "user-subscription"):
    raise SystemExit("FAIL: modelClass is %r" % (data.get("modelClass"),))
if data.get("modelClass") != "local":
    raise SystemExit("FAIL: localhost model was not class local")
if data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: command was not held")
if data.get("draft") != "draft.txt":
    raise SystemExit("FAIL: draft name is %r" % (data.get("draft"),))
for needle in ("127.0.0.1", "http", "supabase", "chat/completions"):
    if needle in raw:
        raise SystemExit("FAIL: transcript contains %s" % needle)
reply = open(sys.argv[3], "rb").read()
got = open(sys.argv[2], "rb").read()
if got != reply:
    raise SystemExit("FAIL: held file is not the stub reply")
if b"Draft stays on this machine." not in got:
    raise SystemExit("FAIL: held file is not the assistant text")
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
if "Spare note" not in messages or "The body stays on this machine" not in messages:
    raise SystemExit("FAIL: stub did not receive the note title and body")
for needle in ("supabase", "http", "127.0.0.1"):
    if needle in messages:
        raise SystemExit("FAIL: stub body contains %s" % needle)
paths = [ln.strip() for ln in open(sys.argv[5]).read().splitlines() if ln.strip()]
if paths != ["/v1/chat/completions"]:
    raise SystemExit("FAIL: stub path is not the completions endpoint")
headers = open(sys.argv[6]).read().lower()
if "supabase.co" in headers or "authorization" in headers or "bearer" in headers:
    raise SystemExit("FAIL: stub saw supabase.co or an authorization header")
PY
[ ! -e "$WORK/held-ran" ] || { echo "FAIL: command ran without confirm"; exit 1; }
[ ! -e "$WORK/missing-ran" ] || { echo "FAIL: missing-note command ran later"; exit 1; }
echo "check-note-to-app: held file is the stub reply"
echo "check-note-to-app: command without confirm did not run"

if grep -E -q 'supabase\.co|ai-gateway' "$LOG"; then
  echo "FAIL: daemon log records supabase.co or the AI gateway"
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
echo "check-note-to-app: no supabase.co call"
echo "check-note-to-app: OK"

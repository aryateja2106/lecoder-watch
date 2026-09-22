#!/bin/sh
# Spoken notes: spoken is true only when speak is true and MESH_TTS is a
# local binary that exits 0. A URL is not started. speak false does not
# start the binary. This script starts its own daemon and stops it.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
command -v bun >/dev/null 2>&1 || { echo "check-knowledge-speak: SKIP (bun not installed)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }

TH="$(mktemp -d)"
STATE="$TH/state"
PDF="$TH/paper.pdf"
SINK="$TH/spoken.txt"
FAIL_SINK="$TH/failed.txt"
DECOY_LOG="$TH/decoy.log"
PORT=8898
DECOY_PORT=8877
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
SRV=
DECOY=

stop_pid() {
  pid="${1:-}"
  [ -n "$pid" ] || return 0
  kill "$pid" 2>/dev/null || true
  n=0
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 20 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

stop_srv() {
  stop_pid "${SRV:-}"
  SRV=
}

stop_decoy() {
  stop_pid "${DECOY:-}"
  DECOY=
}

cleanup() {
  ec=$?
  stop_srv
  stop_decoy
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

cat > "$TH/speak.sh" <<EOF
#!/bin/sh
cat > "$SINK"
EOF
cat > "$TH/fail.sh" <<EOF
#!/bin/sh
cat > "$FAIL_SINK"
exit 1
EOF
chmod +x "$TH/speak.sh" "$TH/fail.sh"

port_busy() {
  p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn | grep -q ":$p " && return 0
    return 1
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    return 1
  fi
  return 1
}

if port_busy "$PORT"; then
  echo "FAIL: port $PORT is already in use"
  exit 1
fi
if port_busy "$DECOY_PORT"; then
  echo "FAIL: port $DECOY_PORT is already in use"
  exit 1
fi

start_srv() {
  tts="$1"
  log="$2"
  if port_busy "$PORT"; then
    echo "FAIL: port $PORT is already in use"
    exit 1
  fi
  MESHD_PORT=$PORT \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$STATE" \
  MESHD_TELEMETRY=off \
  MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
  MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
  MESHD_KB_PATH="$TH/kb.sqlite" \
  MESH_TTS="$tts" \
  HOME="$TH" \
  bun server.ts >"$log" 2>&1 &
  SRV=$!
  up=0
  i=0
  while [ "$i" -lt 50 ]; do
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

post_pdf() {
  speak="$1"
  out="$2"
  python3 - "$PDF" "$speak" "$TH/body.json" <<'PY'
import json, sys
json.dump({"path": sys.argv[1], "speak": sys.argv[2] == "true"}, open(sys.argv[3], "w"))
PY
  code="$(curl --connect-timeout 1 --max-time 15 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data-binary @"$TH/body.json" \
    "http://127.0.0.1:$PORT/knowledge" || true)"
  [ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$out"; echo; exit 1; }
}

assert_spoken() {
  file="$1"
  want="$2"
  python3 - "$file" "$want" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
got = data.get("spoken")
want = sys.argv[2] == "true"
if got is not want:
    raise SystemExit("FAIL: spoken is %r, want %s" % (got, "true" if want else "false"))
PY
}

assert_no_supabase() {
  log="$1"
  if grep -F 'supabase.co' "$log" >/dev/null 2>&1; then
    echo "FAIL: daemon log names supabase.co"
    exit 1
  fi
  if grep -E -i 'ai-gateway|ai\.gateway' "$log" >/dev/null 2>&1; then
    echo "FAIL: daemon log names an AI gateway"
    exit 1
  fi
  # Linux reads /proc. The macOS job has no /proc; it uses ps -E and lsof
  # for the same facts: telemetry is off, and no TCP socket leaves loopback.
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

rm -f "$SINK"
start_srv "$TH/speak.sh" "$TH/meshd-local.log"
post_pdf false "$TH/quiet.json"
assert_spoken "$TH/quiet.json" false
[ ! -f "$SINK" ] || { echo "FAIL: speak false wrote the spoken file"; exit 1; }
echo "check-knowledge-speak: speak false did not run"
post_pdf true "$TH/spoken.json"
assert_spoken "$TH/spoken.json" true
[ -f "$SINK" ] || { echo "FAIL: local TTS did not write the spoken file"; exit 1; }
grep -q 'Spare note' "$SINK" || { echo "FAIL: spoken file has no note title"; exit 1; }
echo "check-knowledge-speak: local binary exited 0 and spoke the title"
assert_no_supabase "$TH/meshd-local.log"
stop_srv

rm -f "$SINK" "$DECOY_LOG"
python3 - "$DECOY_PORT" "$DECOY_LOG" <<'PY' &
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
port = int(sys.argv[1])
log_path = sys.argv[2]
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self._hit()
    def do_POST(self):
        self._hit()
    def _hit(self):
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write(self.command + " " + self.path + "\n")
        self.send_response(204)
        self.end_headers()
    def log_message(self, fmt, *args):
        return
ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
PY
DECOY=$!
i=0
up=0
while [ "$i" -lt 30 ]; do
  if curl --connect-timeout 1 --max-time 2 -sf -o /dev/null "http://127.0.0.1:$DECOY_PORT/ping" 2>/dev/null; then
    up=1
    break
  fi
  sleep 0.1
  i=$((i + 1))
done
[ "$up" -eq 1 ] || { echo "FAIL: decoy HTTP server did not listen"; exit 1; }
# The ping above is the check, not the daemon. Clear it before the case.
: > "$DECOY_LOG"

start_srv "http://127.0.0.1:$DECOY_PORT/tts" "$TH/meshd-http.log"
post_pdf true "$TH/http.json"
assert_spoken "$TH/http.json" false
[ ! -f "$SINK" ] || { echo "FAIL: http MESH_TTS created the spoken file"; exit 1; }
if [ -s "$DECOY_LOG" ]; then
  echo "FAIL: http MESH_TTS was requested"
  exit 1
fi
echo "check-knowledge-speak: http URL did not run"
assert_no_supabase "$TH/meshd-http.log"
stop_srv
stop_decoy

rm -f "$FAIL_SINK"
start_srv "$TH/fail.sh" "$TH/meshd-fail.log"
post_pdf true "$TH/fail.json"
assert_spoken "$TH/fail.json" false
[ -f "$FAIL_SINK" ] || { echo "FAIL: failing binary did not run"; exit 1; }
grep -q 'Spare note' "$FAIL_SINK" || { echo "FAIL: failing binary did not receive the title"; exit 1; }
echo "check-knowledge-speak: exit 1 returned spoken false"
assert_no_supabase "$TH/meshd-fail.log"
stop_srv

echo "check-knowledge-speak: no supabase.co request"
echo "check-knowledge-speak: OK"

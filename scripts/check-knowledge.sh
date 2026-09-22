#!/bin/sh
# A spare daemon reads one local PDF, writes one note under MESHD_STATE, and
# lists that note's title. The note directory is mode 700. The process must
# not call Supabase. This script starts the daemon and stops it before exit.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
command -v bun >/dev/null 2>&1 || { echo "check-knowledge: SKIP (bun not installed)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }

grep -q 'handleKnowledge' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route knowledge"
  exit 1
}
if grep -E -n 'supabase|fetch\(|ai-gateway' "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: knowledge.ts reaches the network"
  exit 1
fi

TH="$(mktemp -d)"
STATE="$TH/state"
PDF="$TH/paper.pdf"
LOG="$TH/meshd.log"
PORT=8898
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
SRV=

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

if command -v ss >/dev/null 2>&1; then
  if ss -ltn | grep -q ':8898 '; then
    echo "FAIL: port 8898 is already in use"
    exit 1
  fi
fi

MESHD_PORT=$PORT \
MESHD_HOST=127.0.0.1 \
MESHD_TOKEN="$TOKEN" \
MESHD_STATE="$STATE" \
MESHD_TELEMETRY=off \
MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
MESHD_KB_PATH="$TH/kb.sqlite" \
HOME="$TH" \
bun server.ts >"$LOG" 2>&1 &
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

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/post.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "{\"path\":\"${PDF}\"}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; echo; cat "$LOG"; exit 1; }

found=0
for f in "$STATE/knowledge"/*.json; do
  [ -f "$f" ] || continue
  found=$((found + 1))
  grep -q 'Spare note' "$f" || { echo "FAIL: note file has no title"; exit 1; }
  fmode="$(stat -c '%a' "$f" 2>/dev/null || stat -f '%OLp' "$f")"
  fmode="${fmode#0}"
  [ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
done
[ "$found" -eq 1 ] || { echo "FAIL: expected one note file, found $found"; exit 1; }
echo "check-knowledge: note file exists"

dmode="$(stat -c '%a' "$STATE/knowledge" 2>/dev/null || stat -f '%OLp' "$STATE/knowledge")"
dmode="${dmode#0}"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-knowledge: directory mode 700"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; cat "$TH/list.json"; echo; exit 1; }
python3 - "$TH/list.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
titles = [n.get("title") for n in data.get("notes", [])]
if "Spare note" not in titles:
    raise SystemExit("FAIL: list titles are %r" % (titles,))
PY
echo "check-knowledge: list contains title"

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
echo "check-knowledge: daemon did not call Supabase"
echo "check-knowledge: OK"

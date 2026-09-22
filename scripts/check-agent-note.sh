#!/bin/sh
# Spare daemon: a local PDF becomes a note, GET /knowledge/:id returns the
# body, one draft file is written, and a second command does not run unless
# the caller passes confirm. The model is recorded as a hostname class.
# This script starts the daemon and stops it. It does not kill a foreign
# listener on 8898.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

if grep -E -n 'supabase|fetch\(|ai-gateway' "$ROOT/install/payload/meshd/agent-note.ts"; then
  echo "FAIL: agent-note.ts reaches the network"
  exit 1
fi

TH="$(mktemp -d)"
STATE="$TH/state"
WORK="$TH/session"
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

if command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:8898 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "FAIL: port 8898 is already in use"
    exit 1
  fi
elif command -v ss >/dev/null 2>&1; then
  if ss -ltn | grep -q ':8898 '; then
    echo "FAIL: port 8898 is already in use"
    exit 1
  fi
else
  if python3 - <<'PY'
import socket
s = socket.socket()
try:
    s.bind(("127.0.0.1", 8898))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY
  then
    :
  else
    echo "FAIL: port 8898 is already in use"
    exit 1
  fi
fi

mkdir -p "$WORK"
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
[ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on $PORT"; cat "$LOG"; exit 1; }

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
echo "check-agent-note: local PDF became a note"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/one.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge/:id -> ${code}"; cat "$TH/one.json"; echo; exit 1; }
python3 - "$TH/one.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("title") != "Spare note":
    raise SystemExit("FAIL: title is %r" % (data.get("title"),))
if "The body stays on this machine" not in str(data.get("body") or ""):
    raise SystemExit("FAIL: body is %r" % (data.get("body"),))
PY
echo "check-agent-note: GET /knowledge/:id returned the body"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/missing.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge/00000000-0000-4000-8000-000000000000" || true)"
[ "$code" = "404" ] || { echo "FAIL: missing note -> ${code}"; cat "$TH/missing.json"; echo; exit 1; }
echo "check-agent-note: missing id is 404"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; cat "$TH/list.json"; echo; exit 1; }
python3 - "$TH/list.json" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
titles = []
for note in data.get("notes", []):
    if set(note) - {"id", "title"}:
        raise SystemExit("FAIL: list note is not titles only: %r" % (sorted(note),))
    titles.append(note.get("title"))
if "Spare note" not in titles:
    raise SystemExit("FAIL: list titles are %r" % (titles,))
if "The body stays on this machine" in raw:
    raise SystemExit("FAIL: list included the note body")
PY
echo "check-agent-note: list route is titles only"

NOTE_ID="$ID" WORK="$WORK" python3 - "$TH/job-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": os.environ["NOTE_ID"],
    "cwd": os.environ["WORK"],
    "model": "http://127.0.0.1:11434/v1?access=not-a-key",
    "command": "touch " + os.environ["WORK"] + "/second-ran",
    "confirm": False,
}))
PY
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/job.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/job-req.json" \
  "http://127.0.0.1:$PORT/agent-note" || true)"
[ "$code" = "200" ] || { echo "FAIL: POST /agent-note -> ${code}"; cat "$TH/job.json"; echo; cat "$LOG"; exit 1; }
python3 - "$TH/job.json" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
if data.get("modelClass") != "local":
    raise SystemExit("FAIL: modelClass is %r" % (data.get("modelClass"),))
if data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit("FAIL: second command was not held: %r" % (data,))
if data.get("draft") != "draft.txt":
    raise SystemExit("FAIL: draft name is %r" % (data.get("draft"),))
for needle in ("127.0.0.1", "11434", "not-a-key", "http", "supabase"):
    if needle in raw:
        raise SystemExit("FAIL: transcript contains %s" % needle)
PY
[ -f "$WORK/draft.txt" ] || { echo "FAIL: draft file was not written"; exit 1; }
grep -q 'The body stays on this machine' "$WORK/draft.txt" || { echo "FAIL: draft is not the note"; exit 1; }
[ ! -e "$WORK/second-ran" ] || { echo "FAIL: second command ran without confirm"; exit 1; }
drafts=0
for f in "$WORK"/*; do
  [ -e "$f" ] || continue
  drafts=$((drafts + 1))
  [ "$(basename "$f")" = "draft.txt" ] || { echo "FAIL: extra file $(basename "$f")"; exit 1; }
done
[ "$drafts" -eq 1 ] || { echo "FAIL: expected one draft file, found $drafts"; exit 1; }
echo "check-agent-note: draft file exists"
echo "check-agent-note: second command without confirm did not run"

NOTE_ID="$ID" WORK="$WORK" python3 - "$TH/confirm-req.json" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "id": os.environ["NOTE_ID"],
    "cwd": os.environ["WORK"],
    "model": "https://models.example/v1?access=paid-marker",
    "command": "touch " + os.environ["WORK"] + "/confirmed-ran",
    "confirm": True,
}))
PY
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/confirm.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/confirm-req.json" \
  "http://127.0.0.1:$PORT/agent-note" || true)"
[ "$code" = "200" ] || { echo "FAIL: confirmed POST /agent-note -> ${code}"; cat "$TH/confirm.json"; echo; exit 1; }
python3 - "$TH/confirm.json" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
if data.get("modelClass") != "user-subscription":
    raise SystemExit("FAIL: modelClass is %r" % (data.get("modelClass"),))
if data.get("commandRan") is not True or data.get("held") is not False:
    raise SystemExit("FAIL: confirmed command did not run: %r" % (data,))
for needle in ("models.example", "paid-marker", "https", "supabase"):
    if needle in raw:
        raise SystemExit("FAIL: transcript contains %s" % needle)
PY
[ -f "$WORK/confirmed-ran" ] || { echo "FAIL: confirmed command did not run"; exit 1; }
[ ! -e "$WORK/second-ran" ] || { echo "FAIL: unconfirmed command ran later"; exit 1; }
echo "check-agent-note: confirmed command ran"

if grep -q 'supabase.co' "$LOG"; then
  echo "FAIL: daemon log mentions supabase.co"
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
echo "check-agent-note: no supabase.co call"
echo "check-agent-note: OK"

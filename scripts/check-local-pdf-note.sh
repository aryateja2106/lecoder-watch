#!/bin/sh
# Spare daemon on 127.0.0.1:8898: a local file plus MESH_PDF becomes one
# knowledge note. The executable's stdout is the note body. GET /knowledge
# still lists {id, title} only, without the absolute path. A remote MESH_PDF,
# a pdf value containing ://, and empty stdout return 400 and write nothing.
# bun boots the daemon. node --experimental-strip-types is only a fallback
# for a script that does not need bun; this daemon spawns a local executable,
# so it needs bun. This script does not use port 8899, does not read a real
# home directory, and does not prove a microphone, a speaker, or a PDF parser.
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
if grep -E -n 'supabase|fetch\(|ai-gateway' "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: knowledge.ts reaches the network"
  exit 1
fi
if grep -n 'experiments/jev-routing' "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: knowledge.ts imports the routing experiment"
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

TH="$(mktemp -d)"
HOME_DIR="$TH/home"
STATE="$TH/state"
LOG="$TH/meshd.log"
ALL="$TH/all.log"
HITS="$TH/hits"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
PORT=8898
SRV=
STUB=
PDF="$TH/quarter.pdf"
SENTENCE='The local page stays on this machine.'
MESH_MARK="${HOME}/.mesh"
had_mesh=0
[ -e "$MESH_MARK" ] && had_mesh=1

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
  if [ -f "$LOG" ]; then
    cat "$LOG" >> "$ALL" || true
  fi
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

mkdir -p "$HOME_DIR" "$STATE"
chmod 700 "$HOME_DIR" "$STATE"
: > "$ALL"
printf 'local page\n' > "$PDF"

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
cat > "$TH/pdf-empty" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >> "$TH/empty-args"
exit 0
EOF
cat > "$TH/pdf-fail" <<EOF
#!/bin/sh
printf '%s\n' 'This must not be stored'
exit 1
EOF
cp "$TH/pdfbin" "$TH/pdf-plain"
chmod 700 "$TH/pdfbin" "$TH/pdf-empty" "$TH/pdf-fail"
chmod 644 "$TH/pdf-plain"

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
[ -s "$TH/stub.port" ] || { echo "FAIL: decoy port file never appeared"; exit 1; }
DECOY="$(tr -d '[:space:]' < "$TH/stub.port")"
if [ -z "$DECOY" ] || [ "$DECOY" = "8899" ] || [ "$DECOY" = "8898" ]; then
  echo "FAIL: decoy port is not a spare 127.0.0.1 port"
  exit 1
fi

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

start_daemon() {
  pdf_bin="$1"
  stop_srv
  : > "$LOG"
  if [ -n "$pdf_bin" ]; then
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
  else
    env -u MESH_PDF \
    MESHD_PORT="$PORT" \
    MESHD_HOST=127.0.0.1 \
    MESHD_TOKEN="$TOKEN" \
    MESHD_STATE="$STATE" \
    MESHD_TELEMETRY=off \
    MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
    MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
    MESHD_KB_PATH="$TH/kb.sqlite" \
    HOME="$HOME_DIR" \
    bun install/payload/meshd/server.ts >"$LOG" 2>&1 &
  fi
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
  curl --connect-timeout 1 --max-time 5 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/req.json" \
    "http://127.0.0.1:$PORT/knowledge" || true
}

assert_quiet() {
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
}

start_daemon "$TH/pdfbin"
code="$(post_pdf "$TH/post.json" "$PDF")"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge pdf -> ${code}"; cat "$TH/post.json"; echo; tail -n 40 "$LOG"; exit 1; }
PDF_PATH="$PDF" SENTENCE="$SENTENCE" python3 - "$TH/post.json" "$STATE" "$TH/pdf-args" "$TH/note.id" <<'PY'
import json, os, sys
post = json.load(open(sys.argv[1]))
state, args_path, id_path = sys.argv[2:5]
pdf = os.environ["PDF_PATH"]
sentence = os.environ["SENTENCE"]
if set(post.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: create keys are %r" % (sorted(post.keys()),))
if post.get("title") != "quarter":
    raise SystemExit("FAIL: title is %r" % (post.get("title"),))
if pdf in json.dumps(post):
    raise SystemExit("FAIL: create response includes the absolute path")
note_path = os.path.join(state, "knowledge", post["id"] + ".json")
note = json.load(open(note_path))
if note.get("body") != sentence:
    raise SystemExit("FAIL: note body is %r" % (note.get("body"),))
if note.get("title") != "quarter":
    raise SystemExit("FAIL: stored title is %r" % (note.get("title"),))
if note.get("source") != "quarter.pdf":
    raise SystemExit("FAIL: stored source is %r" % (note.get("source"),))
if pdf in json.dumps(note):
    raise SystemExit("FAIL: stored note includes the absolute path")
args = open(args_path).read().splitlines()
if args != [pdf]:
    raise SystemExit("FAIL: extractor args are %r" % (args,))
open(id_path, "w").write(post["id"])
PY
note_file="$STATE/knowledge/$(cat "$TH/note.id").json"
fmode="$(mode_of "$note_file")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-local-pdf-note: file mode 600"
echo "check-local-pdf-note: directory mode 700"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; exit 1; }
PDF_PATH="$PDF" SENTENCE="$SENTENCE" python3 - "$TH/list.json" "$TH/note.id" <<'PY'
import json, os, sys
raw = open(sys.argv[1]).read()
pdf = os.environ["PDF_PATH"]
sentence = os.environ["SENTENCE"]
if pdf in raw:
    raise SystemExit("FAIL: list includes the absolute path")
if sentence in raw:
    raise SystemExit("FAIL: list includes the note body")
data = json.loads(raw)
if set(data.keys()) != {"notes"}:
    raise SystemExit("FAIL: list keys are %r" % (sorted(data.keys()),))
notes = data["notes"]
if len(notes) != 1:
    raise SystemExit("FAIL: list has %d notes" % (len(notes),))
note = notes[0]
if set(note.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
if note.get("id") != open(sys.argv[2]).read() or note.get("title") != "quarter":
    raise SystemExit("FAIL: list note is %r" % (note,))
PY
echo "check-local-pdf-note: list is id and title"

code="$(post_pdf "$TH/titled.json" "$PDF" "Desk copy")"
[ "$code" = "201" ] || { echo "FAIL: titled pdf -> ${code}"; cat "$TH/titled.json"; echo; exit 1; }
python3 - "$TH/titled.json" "$STATE" "$PDF" <<'PY'
import json, os, sys
post = json.load(open(sys.argv[1]))
if post.get("title") != "Desk copy":
    raise SystemExit("FAIL: optional title is %r" % (post.get("title"),))
note = json.load(open(os.path.join(sys.argv[2], "knowledge", post["id"] + ".json")))
if note.get("title") != "Desk copy" or note.get("body") != "The local page stays on this machine.":
    raise SystemExit("FAIL: titled note is %r" % (note,))
if sys.argv[3] in json.dumps(note):
    raise SystemExit("FAIL: titled note includes the absolute path")
mode = os.stat(os.path.join(sys.argv[2], "knowledge", post["id"] + ".json")).st_mode & 0o777
if mode != 0o600:
    raise SystemExit("FAIL: titled note mode is %o" % mode)
PY
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list2.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge after title -> ${code}"; exit 1; }
PDF_PATH="$PDF" python3 - "$TH/list2.json" <<'PY'
import json, os, sys
raw = open(sys.argv[1]).read()
if os.environ["PDF_PATH"] in raw:
    raise SystemExit("FAIL: list includes the absolute path")
data = json.loads(raw)
notes = data.get("notes")
if not isinstance(notes, list) or len(notes) != 2:
    raise SystemExit("FAIL: titled list is %r" % (notes,))
got = []
for note in notes:
    if set(note.keys()) != {"id", "title"}:
        raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
    got.append(note.get("title"))
if sorted(got) != ["Desk copy", "quarter"]:
    raise SystemExit("FAIL: list titles are %r" % (got,))
PY
echo "check-local-pdf-note: optional title is the list title"

refuse_same_daemon() {
  label="$1"
  target="$2"
  freeze_notes "$TH/frozen.txt"
  before="$(args_lines)"
  code="$(post_pdf "$TH/rej.json" "$target")"
  [ "$code" = "400" ] || { echo "FAIL: ${label} -> ${code}"; cat "$TH/rej.json"; echo; exit 1; }
  freeze_notes "$TH/after.txt"
  cmp -s "$TH/frozen.txt" "$TH/after.txt" || { echo "FAIL: ${label} wrote a note"; exit 1; }
  after="$(args_lines)"
  [ "$before" = "$after" ] || { echo "FAIL: ${label} spawned the local executable"; exit 1; }
  hits_ok
  echo "check-local-pdf-note: ${label}"
}

refuse_same_daemon "pdf containing :// wrote nothing" "http://127.0.0.1:${DECOY}/quarter.pdf"
refuse_same_daemon "protocol-relative pdf wrote nothing" "//127.0.0.1/quarter.pdf"
refuse_same_daemon "missing pdf wrote nothing" "$TH/missing.pdf"
hits_ok
echo "check-local-pdf-note: remote pdf was not fetched"

assert_quiet

refuse_restart() {
  label="$1"
  pdf_bin="$2"
  ran_file="${3-}"
  start_daemon "$pdf_bin"
  freeze_notes "$TH/frozen.txt"
  before="$(args_lines)"
  code="$(post_pdf "$TH/rej.json" "$PDF")"
  [ "$code" = "400" ] || { echo "FAIL: ${label} -> ${code}"; cat "$TH/rej.json"; echo; tail -n 40 "$LOG"; exit 1; }
  freeze_notes "$TH/after.txt"
  cmp -s "$TH/frozen.txt" "$TH/after.txt" || { echo "FAIL: ${label} wrote a note"; exit 1; }
  after="$(args_lines)"
  [ "$before" = "$after" ] || { echo "FAIL: ${label} spawned the local executable"; exit 1; }
  if [ -n "$ran_file" ]; then
    [ -s "$ran_file" ] || { echo "FAIL: ${label} did not run"; exit 1; }
  fi
  hits_ok
  echo "check-local-pdf-note: ${label}"
}

refuse_restart "remote MESH_PDF wrote nothing" "http://127.0.0.1:${DECOY}/pdftotext"
refuse_restart "non-executable MESH_PDF wrote nothing" "$TH/pdf-plain"
refuse_restart "empty stdout wrote nothing" "$TH/pdf-empty" "$TH/empty-args"
refuse_restart "nonzero exit wrote nothing" "$TH/pdf-fail"
refuse_restart "missing MESH_PDF wrote nothing" ""

[ "$(args_lines)" = "2" ] || { echo "FAIL: extractor was started for a refused pdf"; exit 1; }
PDF_PATH="$PDF" python3 - "$TH/empty-args" <<'PY'
import os, sys
lines = open(sys.argv[1]).read().splitlines()
if lines != [os.environ["PDF_PATH"]]:
    raise SystemExit("FAIL: empty extractor args are %r" % (lines,))
PY
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
echo "check-local-pdf-note: OK"

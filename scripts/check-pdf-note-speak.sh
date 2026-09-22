#!/bin/sh
# Spare daemon on 127.0.0.1:8898. POST /knowledge {pdf, title?, speak?}
# speaks a MESH_PDF note with a local TTS binary. A stub MESH_PDF prints one
# sentence. A stub MESH_TTS that exits 0 returns spoken true and receives
# that sentence. A remote, scheme, or protocol-relative MESH_TTS returns
# 400 and does not start MESH_PDF or write a note. speak omitted writes the
# note and does not start MESH_TTS. A missing or failing TTS binary still
# stores the note and returns spoken false. The list stays {id, title}.
# This script does not use port 8899, a real home directory, or a hosted
# model. The stub is the proof. It does not prove a speaker played audio.
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
calls="$(grep -c 'await handleKnowledge(' "$ROOT/install/payload/meshd/server.ts" || true)"
[ "$calls" = "1" ] || { echo "FAIL: server.ts must call handleKnowledge once"; exit 1; }
if grep -nE 'route\.ts|filter\.ts|from "./route"|from "./filter"' "$KNOW"; then
  echo "FAIL: knowledge.ts imports route.ts or filter.ts"
  exit 1
fi
if grep -E -n 'supabase|fetch\(|ai-gateway' "$KNOW"; then
  echo "FAIL: knowledge.ts reaches the network"
  exit 1
fi
if grep -n 'experiments/jev-routing' "$KNOW"; then
  echo "FAIL: knowledge.ts imports the routing experiment"
  exit 1
fi
if grep -E -n 'Bun\.spawn\(\[?"?(sh|bash|curl|wget)' "$KNOW"; then
  echo "FAIL: knowledge.ts spawns a shell or a downloader"
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
grep -q 'speakReplaced(' "$KNOW" || {
  echo "FAIL: pdf speech does not use the exit-0 speaker"
  exit 1
}

REAL_HOME="$(cd "$HOME" && pwd)"
TH="$(mktemp -d)"
HOME_DIR="$TH/home"
STATE="$TH/state"
LOG="$TH/meshd.log"
ALL="$TH/all.log"
HITS="$TH/hits"
TOKEN=throwaway
PORT=8898
SRV=
DECOY_PID=
PDF="$TH/quarter.pdf"
SENTENCE='The local page stays on this machine.'
MESH_MARK="${REAL_HOME}/.mesh"
had_mesh=0
[ -e "$MESH_MARK" ] && had_mesh=1

case "$STATE" in
  "$REAL_HOME"|"$REAL_HOME"/*|/home/*|/Users/*)
    echo "FAIL: state is inside a home directory"
    exit 1
    ;;
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
cat > "$TH/ttsbin" <<EOF
#!/bin/sh
cat >> "$TH/tts-stdin"
printf '%s\n' '--run--' >> "$TH/tts-stdin"
exit 0
EOF
cat > "$TH/ttsfail" <<EOF
#!/bin/sh
cat >> "$TH/tts-fail"
printf '%s\n' '--fail--' >> "$TH/tts-fail"
exit 1
EOF
chmod 700 "$TH/pdfbin" "$TH/ttsbin" "$TH/ttsfail"

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
i=0
while [ ! -s "$TH/decoy.port" ] && [ "$i" -lt 300 ]; do
  kill -0 "$DECOY_PID" 2>/dev/null || {
    echo "FAIL: decoy exited"
    exit 1
  }
  sleep 0.1
  i=$((i + 1))
done
[ -s "$TH/decoy.port" ] || { echo "FAIL: decoy port file never appeared"; exit 1; }
DECOY="$(tr -d '[:space:]' < "$TH/decoy.port")"
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

lines_of() {
  if [ ! -f "$1" ]; then
    echo 0
    return 0
  fi
  wc -l < "$1" | tr -d ' '
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
  mode="$1"
  tts_bin="${2-}"
  stop_srv
  : > "$LOG"
  if [ "$mode" = "set" ]; then
    MESHD_PORT="$PORT" \
    MESHD_HOST=127.0.0.1 \
    MESHD_TOKEN=throwaway \
    MESHD_STATE="$STATE" \
    MESHD_TELEMETRY=off \
    MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
    MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
    MESHD_KB_PATH="$TH/kb.sqlite" \
    HOME="$HOME_DIR" \
    MESH_PDF="$TH/pdfbin" \
    MESH_TTS="$tts_bin" \
    bun install/payload/meshd/server.ts >"$LOG" 2>&1 &
  else
    env -u MESH_TTS \
    MESHD_PORT="$PORT" \
    MESHD_HOST=127.0.0.1 \
    MESHD_TOKEN=throwaway \
    MESHD_STATE="$STATE" \
    MESHD_TELEMETRY=off \
    MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
    MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
    MESHD_KB_PATH="$TH/kb.sqlite" \
    HOME="$HOME_DIR" \
    MESH_PDF="$TH/pdfbin" \
    bun install/payload/meshd/server.ts >"$LOG" 2>&1 &
  fi
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
  speak_mode="$2"
  title="${3-}"
  PDF_VALUE="$PDF" TITLE_VALUE="$title" SPEAK_MODE="$speak_mode" python3 - "$TH/req.json" <<'PY'
import json, os, sys
body = {"pdf": os.environ["PDF_VALUE"]}
title = os.environ["TITLE_VALUE"]
if title:
    body["title"] = title
mode = os.environ["SPEAK_MODE"]
if mode == "true":
    body["speak"] = True
elif mode == "false":
    body["speak"] = False
elif mode != "omit":
    raise SystemExit("bad speak mode")
json.dump(body, open(sys.argv[1], "w"))
PY
  curl --connect-timeout 1 --max-time 12 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/req.json" \
    "http://127.0.0.1:$PORT/knowledge" || true
}

refuse_tts() {
  label="$1"
  tts_bin="$2"
  start_daemon set "$tts_bin"
  freeze_notes "$TH/frozen.txt"
  before="$(lines_of "$TH/pdf-args")"
  code="$(post_pdf "$TH/rej.json" true "Quarter")"
  [ "$code" = "400" ] || { echo "FAIL: ${label} -> ${code}"; cat "$TH/rej.json"; echo; tail -n 40 "$LOG"; exit 1; }
  python3 - "$TH/rej.json" "$label" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("error") != "tts must be a local binary":
    raise SystemExit("FAIL: %s error is %r" % (sys.argv[2], data.get("error")))
if set(data.keys()) != {"error"}:
    raise SystemExit("FAIL: %s keys are %r" % (sys.argv[2], sorted(data.keys())))
PY
  freeze_notes "$TH/after.txt"
  cmp -s "$TH/frozen.txt" "$TH/after.txt" || { echo "FAIL: ${label} wrote a note"; exit 1; }
  after="$(lines_of "$TH/pdf-args")"
  [ "$before" = "$after" ] || { echo "FAIL: ${label} started MESH_PDF"; exit 1; }
  hits_ok
  echo "check-pdf-note-speak: ${label}"
}

refuse_tts "remote MESH_TTS wrote nothing" "http://127.0.0.1:${DECOY}/speaker"
refuse_tts "protocol-relative MESH_TTS wrote nothing" "//127.0.0.1/speaker"
refuse_tts "MESH_TTS containing :// wrote nothing" "speaker://local"
[ ! -d "$STATE/knowledge" ] || { echo "FAIL: a refused speaker created a note directory"; exit 1; }
[ ! -e "$TH/pdf-args" ] || { echo "FAIL: a refused speaker started MESH_PDF"; exit 1; }
hits_ok

start_daemon set "$TH/ttsbin"
code="$(post_pdf "$TH/post.json" true "Quarter")"
[ "$code" = "201" ] || { echo "FAIL: speak true -> ${code}"; cat "$TH/post.json"; echo; tail -n 40 "$LOG"; exit 1; }
PDF_PATH="$PDF" SENTENCE="$SENTENCE" python3 - "$TH/post.json" "$STATE" "$TH/pdf-args" "$TH/tts-stdin" "$TH/note.id" <<'PY'
import json, os, sys
post = json.load(open(sys.argv[1]))
state, args_path, spoken_path, id_path = sys.argv[2:6]
pdf = os.environ["PDF_PATH"]
sentence = os.environ["SENTENCE"]
if set(post.keys()) != {"id", "title", "spoken"}:
    raise SystemExit("FAIL: speak keys are %r" % (sorted(post.keys()),))
if post.get("spoken") is not True:
    raise SystemExit("FAIL: spoken is %r" % (post.get("spoken"),))
if post.get("title") != "Quarter":
    raise SystemExit("FAIL: title is %r" % (post.get("title"),))
if pdf in json.dumps(post) or sentence in json.dumps(post):
    raise SystemExit("FAIL: create response includes the path or the body")
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
heard = open(spoken_path, "rb").read().decode()
if sentence not in heard or "Quarter" not in heard:
    raise SystemExit("FAIL: speaker did not receive the sentence")
if pdf in heard:
    raise SystemExit("FAIL: speaker received the absolute path")
if heard.count("--run--") != 1:
    raise SystemExit("FAIL: speaker runs are %d" % heard.count("--run--"))
open(id_path, "w").write(post["id"])
PY
note_file="$STATE/knowledge/$(cat "$TH/note.id").json"
fmode="$(mode_of "$note_file")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-pdf-note-speak: local TTS exits 0 and spoken is true"
echo "check-pdf-note-speak: file mode 600"
echo "check-pdf-note-speak: directory mode 700"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; exit 1; }
PDF_PATH="$PDF" SENTENCE="$SENTENCE" python3 - "$TH/list.json" "$TH/note.id" <<'PY'
import json, os, sys
raw = open(sys.argv[1]).read()
pdf = os.environ["PDF_PATH"]
sentence = os.environ["SENTENCE"]
if pdf in raw or sentence in raw or "spoken" in raw:
    raise SystemExit("FAIL: list includes the path, the body, or spoken")
data = json.loads(raw)
if set(data.keys()) != {"notes"}:
    raise SystemExit("FAIL: list keys are %r" % (sorted(data.keys()),))
notes = data["notes"]
if len(notes) != 1:
    raise SystemExit("FAIL: list has %d notes" % (len(notes),))
note = notes[0]
if set(note.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
if note.get("id") != open(sys.argv[2]).read() or note.get("title") != "Quarter":
    raise SystemExit("FAIL: list note is %r" % (note,))
PY
echo "check-pdf-note-speak: list is id and title"

runs_before="$(lines_of "$TH/tts-stdin")"
pdf_before="$(lines_of "$TH/pdf-args")"
code="$(post_pdf "$TH/omit.json" omit "Quiet")"
[ "$code" = "201" ] || { echo "FAIL: speak omitted -> ${code}"; cat "$TH/omit.json"; echo; tail -n 40 "$LOG"; exit 1; }
PDF_PATH="$PDF" SENTENCE="$SENTENCE" python3 - "$TH/omit.json" "$STATE" <<'PY'
import json, os, sys
post = json.load(open(sys.argv[1]))
if set(post.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: omitted keys are %r" % (sorted(post.keys()),))
if post.get("title") != "Quiet":
    raise SystemExit("FAIL: omitted title is %r" % (post.get("title"),))
note = json.load(open(os.path.join(sys.argv[2], "knowledge", post["id"] + ".json")))
if note.get("body") != os.environ["SENTENCE"] or note.get("source") != "quarter.pdf":
    raise SystemExit("FAIL: omitted note is %r" % (note,))
if os.environ["PDF_PATH"] in json.dumps(note):
    raise SystemExit("FAIL: omitted note includes the absolute path")
mode = os.stat(os.path.join(sys.argv[2], "knowledge", post["id"] + ".json")).st_mode & 0o777
if mode != 0o600:
    raise SystemExit("FAIL: omitted note mode is %o" % mode)
PY
runs_after="$(lines_of "$TH/tts-stdin")"
pdf_after="$(lines_of "$TH/pdf-args")"
[ "$runs_before" = "$runs_after" ] || { echo "FAIL: speak omitted started MESH_TTS"; exit 1; }
[ "$pdf_after" = "$((pdf_before + 1))" ] || { echo "FAIL: speak omitted did not run MESH_PDF"; exit 1; }
echo "check-pdf-note-speak: speak omitted wrote the note and did not start MESH_TTS"

code="$(post_pdf "$TH/false.json" false "Silent")"
[ "$code" = "201" ] || { echo "FAIL: speak false -> ${code}"; cat "$TH/false.json"; echo; exit 1; }
python3 - "$TH/false.json" <<'PY'
import json, sys
post = json.load(open(sys.argv[1]))
if set(post.keys()) != {"id", "title"} or post.get("title") != "Silent":
    raise SystemExit("FAIL: speak false response is %r" % (post,))
PY
runs_false="$(lines_of "$TH/tts-stdin")"
[ "$runs_false" = "$runs_after" ] || { echo "FAIL: speak false started MESH_TTS"; exit 1; }
echo "check-pdf-note-speak: speak false keeps id and title"

start_daemon set "$TH/ttsfail"
code="$(post_pdf "$TH/fail.json" true "Retry")"
[ "$code" = "201" ] || { echo "FAIL: failing TTS -> ${code}"; cat "$TH/fail.json"; echo; tail -n 40 "$LOG"; exit 1; }
SENTENCE="$SENTENCE" python3 - "$TH/fail.json" "$STATE" "$TH/tts-fail" <<'PY'
import json, os, sys
post = json.load(open(sys.argv[1]))
if post.get("spoken") is not False or post.get("title") != "Retry":
    raise SystemExit("FAIL: failing TTS response is %r" % (post,))
if set(post.keys()) != {"id", "title", "spoken"}:
    raise SystemExit("FAIL: failing TTS keys are %r" % (sorted(post.keys()),))
note = json.load(open(os.path.join(sys.argv[2], "knowledge", post["id"] + ".json")))
if note.get("body") != os.environ["SENTENCE"] or note.get("source") != "quarter.pdf":
    raise SystemExit("FAIL: failing TTS note is %r" % (note,))
heard = open(sys.argv[3]).read()
if os.environ["SENTENCE"] not in heard or "--fail--" not in heard:
    raise SystemExit("FAIL: failing TTS did not receive the sentence")
PY
echo "check-pdf-note-speak: failing TTS stores the note and spoken is false"

start_daemon set "$TH/missing-tts"
pdf_before="$(lines_of "$TH/pdf-args")"
code="$(post_pdf "$TH/miss.json" true "Gone")"
[ "$code" = "201" ] || { echo "FAIL: missing TTS -> ${code}"; cat "$TH/miss.json"; echo; tail -n 40 "$LOG"; exit 1; }
SENTENCE="$SENTENCE" python3 - "$TH/miss.json" "$STATE" <<'PY'
import json, os, sys
post = json.load(open(sys.argv[1]))
if post.get("spoken") is not False or set(post.keys()) != {"id", "title", "spoken"}:
    raise SystemExit("FAIL: missing TTS response is %r" % (post,))
note = json.load(open(os.path.join(sys.argv[2], "knowledge", post["id"] + ".json")))
if note.get("body") != os.environ["SENTENCE"]:
    raise SystemExit("FAIL: missing TTS note body is %r" % (note.get("body"),))
PY
pdf_after="$(lines_of "$TH/pdf-args")"
[ "$pdf_after" = "$((pdf_before + 1))" ] || { echo "FAIL: missing TTS did not run MESH_PDF"; exit 1; }
echo "check-pdf-note-speak: missing TTS stores the note and spoken is false"

start_daemon unset
code="$(post_pdf "$TH/bare.json" true "Bare")"
[ "$code" = "201" ] || { echo "FAIL: unset TTS -> ${code}"; cat "$TH/bare.json"; echo; tail -n 40 "$LOG"; exit 1; }
python3 - "$TH/bare.json" "$STATE" "$SENTENCE" <<'PY'
import json, os, sys
post = json.load(open(sys.argv[1]))
if post.get("spoken") is not False or post.get("title") != "Bare":
    raise SystemExit("FAIL: unset TTS response is %r" % (post,))
note = json.load(open(os.path.join(sys.argv[2], "knowledge", post["id"] + ".json")))
if note.get("body") != sys.argv[3] or note.get("source") != "quarter.pdf":
    raise SystemExit("FAIL: unset TTS note is %r" % (note,))
PY
runs_final="$(lines_of "$TH/tts-stdin")"
[ "$runs_final" = "$runs_false" ] || { echo "FAIL: unset TTS started the exit-0 speaker"; exit 1; }
echo "check-pdf-note-speak: unset TTS stores the note and spoken is false"

dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
hits_ok
[ ! -d "$HOME_DIR/.mesh" ] || { echo "FAIL: daemon wrote under its home directory"; exit 1; }
if [ "$had_mesh" -eq 0 ] && [ -e "$MESH_MARK" ]; then
  echo "FAIL: wrote ~/.mesh"
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
if env.get("MESHD_TOKEN") != "throwaway":
    sys.exit("FAIL: spare token is not the proof token")
if bad:
    sys.exit("FAIL: daemon has a non-loopback socket: %s" % ", ".join(bad))
state = os.environ["STATE"]
home = os.environ["HOME"]
if state == home or state.startswith(home + os.sep):
    sys.exit("FAIL: daemon state is inside a home directory")
PY
fi

if [ -f "$LOG" ]; then
  cat "$LOG" >> "$ALL" || true
fi
if grep -E -q 'supabase\.co|ai-gateway' "$ALL"; then
  echo "FAIL: daemon log records supabase.co or the AI gateway"
  exit 1
fi
echo "check-pdf-note-speak: OK"

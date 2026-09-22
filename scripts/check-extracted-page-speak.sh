#!/bin/sh
# A spare daemon extracts one local PDF page and a local speech binary speaks
# that page. Each case has its own daemon, so a refused speak cannot reuse a
# live process. A remote MESH_TTS is not started. Omitting speak leaves the
# local binary idle.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
command -v bun >/dev/null 2>&1 || { echo "check-extracted-page-speak: SKIP (bun not installed)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

TH="$(mktemp -d)"
PORT=8898
SRV=

stop_srv() {
  [ -n "${SRV:-}" ] || return 0
  kill -TERM "-${SRV}" 2>/dev/null || true
  n=0
  while kill -0 "$SRV" 2>/dev/null && [ "$n" -lt 30 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -KILL "-${SRV}" 2>/dev/null || true
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

port_busy() {
  lsof -nP -iTCP:8898 -sTCP:LISTEN >/dev/null 2>&1
}

write_pdf() {
  python3 - "$1" <<'PY'
import sys
path = sys.argv[1]
stream = b"BT /F1 12 Tf 72 720 Td (The oak margin names the extracted page.) Tj ET\n"
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"endstream",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    b"<< /Title (Oak page) >>",
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

file_mode() {
  mode="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1")"
  printf '%s\n' "${mode#0}"
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

post_knowledge() {
  token=$1
  body=$2
  out=$3
  curl --connect-timeout 1 --max-time 20 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${token}" \
    -H 'content-type: application/json' \
    --data-binary @"$body" \
    "http://127.0.0.1:$PORT/knowledge" || true
}

one_note() {
  state=$1
  found=0
  note=""
  for f in "$state/knowledge"/*.json; do
    [ -f "$f" ] || continue
    found=$((found + 1))
    note=$f
  done
  [ "$found" -eq 1 ] || { echo "FAIL: expected one note file, found $found" >&2; return 1; }
  printf '%s\n' "$note"
}

# Case 1: a local executable speaks the extracted page.
C1="$TH/local"
mkdir -p "$C1"
PDF1="$C1/paper.pdf"
MARKER1="$C1/spoken.txt"
BIN1="$C1/speak"
STATE1="$C1/state"
LOG1="$C1/meshd.log"
write_pdf "$PDF1"
write_speaker "$BIN1" "$MARKER1"
[ "$(file_mode "$BIN1")" = "700" ] || { echo "FAIL: speech binary mode is not 700"; exit 1; }
TOKEN1="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
python3 - "$PDF1" "$C1/body.json" <<'PY'
import json, sys
json.dump({"path": sys.argv[1], "speak": True}, open(sys.argv[2], "w"))
PY
start_daemon "$C1" "$TOKEN1" "$STATE1" "$BIN1" "$LOG1"
code="$(post_knowledge "$TOKEN1" "$C1/body.json" "$C1/post.json")"
[ "$code" = "201" ] || { echo "FAIL: case 1 POST /knowledge -> ${code}"; cat "$C1/post.json"; echo; cat "$LOG1"; exit 1; }
python3 - "$C1/post.json" "$PDF1" <<'PY' || { echo "FAIL: case 1 response"; cat "$LOG1"; exit 1; }
import json, sys
post = json.load(open(sys.argv[1]))
pdf = sys.argv[2]
if post.get("title") != "Oak page":
    raise SystemExit(f"FAIL: title is {post.get('title')!r}")
if post.get("spoken") is not True:
    raise SystemExit(f"FAIL: spoken is {post.get('spoken')!r}")
if pdf in json.dumps(post):
    raise SystemExit("FAIL: response contains the pdf path")
PY
NOTE1="$(one_note "$STATE1")" || exit 1
python3 - "$NOTE1" "$PDF1" <<'PY' || { echo "FAIL: case 1 note"; exit 1; }
import json, sys
note = json.load(open(sys.argv[1]))
pdf = sys.argv[2]
body = note.get("body")
if not isinstance(body, str) or "The oak margin names the extracted page." not in body:
    raise SystemExit("FAIL: note body missing the extracted sentence")
if pdf in json.dumps(note):
    raise SystemExit("FAIL: note contains the pdf path")
PY
[ "$(file_mode "$NOTE1")" = "600" ] || { echo "FAIL: note file mode is not 600"; exit 1; }
[ "$(file_mode "$STATE1/knowledge")" = "700" ] || { echo "FAIL: knowledge directory mode is not 700"; exit 1; }
grep -F -q "Oak page" "$MARKER1" || { echo "FAIL: marker missing the title"; exit 1; }
grep -F -q "The oak margin names the extracted page." "$MARKER1" || { echo "FAIL: marker missing the extracted sentence"; exit 1; }
list_code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$C1/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN1}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$list_code" = "200" ] || { echo "FAIL: case 1 GET /knowledge -> ${list_code}"; cat "$C1/list.json"; exit 1; }
python3 - "$C1/list.json" "$PDF1" <<'PY' || exit 1
import json, sys
data = json.load(open(sys.argv[1]))
pdf = sys.argv[2]
notes = data.get("notes")
if not isinstance(notes, list) or len(notes) != 1:
    raise SystemExit(f"FAIL: list shape {data!r}")
item = notes[0]
if set(item.keys()) != {"id", "title"}:
    raise SystemExit(f"FAIL: list keys {sorted(item.keys())}")
if item.get("title") != "Oak page":
    raise SystemExit("FAIL: list title")
if pdf in json.dumps(data):
    raise SystemExit("FAIL: list contains the pdf path")
PY
stop_srv
echo "check-extracted-page-speak: local binary spoke the extracted page"

# Case 2: a remote MESH_TTS is not started. The note is already saved.
C2="$TH/remote"
mkdir -p "$C2"
PDF2="$C2/paper.pdf"
MARKER2="$C2/spoken.txt"
STATE2="$C2/state"
LOG2="$C2/meshd.log"
write_pdf "$PDF2"
TOKEN2="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
python3 - "$PDF2" "$C2/body.json" <<'PY'
import json, sys
json.dump({"path": sys.argv[1], "speak": True}, open(sys.argv[2], "w"))
PY
start_daemon "$C2" "$TOKEN2" "$STATE2" "http://127.0.0.1:9/speak" "$LOG2"
code="$(post_knowledge "$TOKEN2" "$C2/body.json" "$C2/post.json")"
[ "$code" = "201" ] || { echo "FAIL: case 2 POST /knowledge -> ${code}"; cat "$C2/post.json"; echo; cat "$LOG2"; exit 1; }
python3 - "$C2/post.json" <<'PY' || { echo "FAIL: case 2 response"; cat "$LOG2"; exit 1; }
import json, sys
post = json.load(open(sys.argv[1]))
if post.get("spoken") is not False:
    raise SystemExit(f"FAIL: remote spoken is {post.get('spoken')!r}")
PY
NOTE2="$(one_note "$STATE2")" || exit 1
python3 - "$NOTE2" "$PDF2" <<'PY' || exit 1
import json, sys
note = json.load(open(sys.argv[1]))
body = note.get("body")
if not isinstance(body, str) or "The oak margin names the extracted page." not in body:
    raise SystemExit("FAIL: remote note missing the extracted sentence")
PY
[ ! -e "$MARKER2" ] || { echo "FAIL: remote speak created a marker file"; exit 1; }
python3 - <<'PY' || { echo "FAIL: something listens for the remote tts url"; exit 1; }
import socket
s = socket.socket()
s.settimeout(0.4)
try:
    s.connect(("127.0.0.1", 9))
except OSError:
    raise SystemExit(0)
raise SystemExit(1)
PY
stop_srv
echo "check-extracted-page-speak: remote tts was not started"

# Case 3: speak omitted. The local binary stays idle.
C3="$TH/quiet"
mkdir -p "$C3"
PDF3="$C3/paper.pdf"
MARKER3="$C3/spoken.txt"
BIN3="$C3/speak"
STATE3="$C3/state"
LOG3="$C3/meshd.log"
write_pdf "$PDF3"
write_speaker "$BIN3" "$MARKER3"
TOKEN3="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
python3 - "$PDF3" "$C3/body.json" <<'PY'
import json, sys
json.dump({"path": sys.argv[1]}, open(sys.argv[2], "w"))
PY
start_daemon "$C3" "$TOKEN3" "$STATE3" "$BIN3" "$LOG3"
code="$(post_knowledge "$TOKEN3" "$C3/body.json" "$C3/post.json")"
[ "$code" = "201" ] || { echo "FAIL: case 3 POST /knowledge -> ${code}"; cat "$C3/post.json"; echo; cat "$LOG3"; exit 1; }
python3 - "$C3/post.json" <<'PY' || { echo "FAIL: case 3 response"; cat "$LOG3"; exit 1; }
import json, sys
post = json.load(open(sys.argv[1]))
if post.get("spoken") is not False:
    raise SystemExit(f"FAIL: omitted speak spoken is {post.get('spoken')!r}")
PY
[ ! -e "$MARKER3" ] || { echo "FAIL: omitted speak started the local binary"; exit 1; }
stop_srv
echo "check-extracted-page-speak: omitted speak left the binary idle"

#!/bin/sh
# A phone ask posts q, ask, and confirm, and omits cwd and model.
# MESH_MODEL points at a local stub. The reply is 200, commandRan is false,
# and one new note is titled with the ask. Its body is the stub sentence.
# Speaking that note with a local MESH_TTS returns spoken true. The TTS
# process receives the stored title and body. The note file stays mode 600
# and its body is unchanged. The same speak with a remote MESH_TTS is
# refused and does not write.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$ROOT/scripts/$(basename "$0")"
cd "$ROOT/install/payload/meshd"
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }
command -v lsof >/dev/null 2>&1 || { echo "FAIL: lsof is required"; exit 1; }

python3 - "$SELF" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
proc = "/" + "proc"
bad_port = "88" + "99"
if text.count(proc) != 0 or text.count(bad_port) != 0:
    raise SystemExit("FAIL: script uses forbidden host paths or ports")
PY

TH="$(mktemp -d /tmp/speak-phone-answer.XXXXXX)"
PORT=8898
SRV=
STUB=
STUB_BODIES="$TH/stub-bodies"
SENTENCE="The oak stays on this machine."
ASK="build a reader"
QUERY="Oak margin"
mkdir -p "$STUB_BODIES"

case "$TH" in
  /tmp/*) ;;
  *) echo "FAIL: temp dir is not under /tmp"; exit 1 ;;
esac
[ "$PORT" = "8898" ] || { echo "FAIL: spare daemon must listen on 8898"; exit 1; }

stop_srv() {
  pid=${SRV:-}
  [ -n "$pid" ] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  n=0
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 30 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  SRV=
}

stop_stub() {
  pid=${STUB:-}
  [ -n "$pid" ] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  n=0
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 30 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  STUB=
}

cleanup() {
  ec=$?
  set +e
  stop_srv
  stop_stub
  rm -rf "$TH"
  exit "$ec"
}
trap cleanup EXIT

port_busy() {
  lsof -nP -iTCP:8898 -sTCP:LISTEN >/dev/null 2>&1
}

wait_port_free() {
  n=0
  while port_busy && [ "$n" -lt 50 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  if port_busy; then
    echo "FAIL: port 8898 stayed in use"
    exit 1
  fi
}

note_count() {
  find "$1/knowledge" -type f -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]'
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

start_daemon() {
  token=$1
  state=$2
  home=$3
  log=$4
  model=$5
  tts=$6
  case "$state" in
    /tmp/*) ;;
    *) echo "FAIL: state is not under /tmp"; exit 1 ;;
  esac
  case "$home" in
    /tmp/*) ;;
    *) echo "FAIL: HOME is not under /tmp"; exit 1 ;;
  esac
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
    MESHD_EVENTS_PATH="$state/events.jsonl" \
    MESHD_TELEMETRY_STATE="$state/telemetry.json" \
    MESHD_KB_PATH="$state/kb.sqlite" \
    HOME="$home" \
    MESH_MODEL="$model" \
    MESH_TTS="$tts" \
    bun server.ts >"$log" 2>&1 &
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

new_token() {
  python3 -c 'import secrets; print(secrets.token_hex(16))'
}

seed_note() {
  token=$1
  dest=$2
  out=$3
  python3 - "$dest" "$QUERY" <<'PY'
import json, sys
json.dump({"title": sys.argv[2], "body": "The page stays on this machine."}, open(sys.argv[1], "w"))
PY
  code="$(post_json "$token" "http://127.0.0.1:$PORT/knowledge" "$dest" "$out")"
  [ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}" >&2; cat "$out" >&2; exit 1; }
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$out"
}

write_phone_body() {
  dest=$1
  query=$2
  ask=$3
  python3 - "$dest" "$query" "$ask" <<'PY'
import json, sys
dest, query, ask = sys.argv[1:4]
body = {"q": query, "ask": ask, "confirm": True}
if set(body) != {"q", "ask", "confirm"}:
    raise SystemExit("phone body keys are wrong")
json.dump(body, open(dest, "w"))
PY
}

# Model stub on loopback. The phone never sends this URL.
python3 -u - "$TH/stub.port" "$STUB_BODIES" "$TH/stub.reply" 2>"$TH/stub.err" <<'PY' &
import sys; sys.stderr.write("stub-start\n"); sys.stderr.flush()
import json, os
port_path, body_dir, reply_path = sys.argv[1:4]
reply = json.dumps({"choices": [{"message": {"content": "The oak stays on this machine."}}]}).encode()
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

sys.stderr.write("stub-bind\n"); sys.stderr.flush()
server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
tmp_port = port_path + ".tmp"
with open(tmp_port, "w", encoding="utf-8") as fh:
    fh.write(str(server.server_address[1]))
    fh.write("\n")
    fh.flush()
os.rename(tmp_port, port_path)
server.serve_forever()
PY
STUB=$!
i=0
while [ ! -s "$TH/stub.port" ] && [ "$i" -lt 300 ]; do
  kill -0 "$STUB" 2>/dev/null || { echo "FAIL: model stub exited"; cat "$TH/stub.err" 2>/dev/null || true; exit 1; }
  sleep 0.1
  i=$((i + 1))
done
[ -s "$TH/stub.port" ] || { echo "FAIL: model stub port never appeared"; cat "$TH/stub.err" 2>/dev/null || true; exit 1; }
STUB_PORT="$(tr -d '[:space:]' < "$TH/stub.port")"
case "$STUB_PORT" in
  ''|*[!0-9]*) echo "FAIL: model stub port is not numeric"; exit 1 ;;
esac
if [ "$STUB_PORT" = "8898" ]; then
  echo "FAIL: model stub took the daemon port"
  exit 1
fi
LOCAL_MODEL="http://127.0.0.1:${STUB_PORT}/v1"

: > "$TH/tts-in"
cat > "$TH/tts" <<EOF
#!/bin/sh
cat >> "$TH/tts-in"
exit 0
EOF
chmod 700 "$TH/tts"

C1="$TH/local"
mkdir -p "$C1/state" "$C1/home"
TOKEN="$(new_token)"
start_daemon "$TOKEN" "$C1/state" "$C1/home" "$C1/meshd.log" "$LOCAL_MODEL" "$TH/tts"
SEED="$(seed_note "$TOKEN" "$C1/seed.json" "$C1/seed.out")"
[ "$(note_count "$C1/state")" = "1" ] || { echo "FAIL: seed note count"; exit 1; }
write_phone_body "$C1/ask.json" "$QUERY" "$ASK"
code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/agent-note" "$C1/ask.json" "$C1/ask.out")"
[ "$code" = "200" ] || { echo "FAIL: phone ask -> ${code}"; cat "$C1/ask.out"; echo; cat "$C1/meshd.log"; exit 1; }
if ! NOTE_ID="$(python3 - "$C1/ask.out" "$C1/state" "$SEED" "$ASK" "$SENTENCE" <<'PY'
import json, os, sys
res, state, seed, ask, sentence = sys.argv[1:6]
data = json.load(open(res))
if data.get("commandRan") is not False:
    raise SystemExit("commandRan is %r" % (data.get("commandRan"),))
names = [name for name in os.listdir(os.path.join(state, "knowledge")) if name.endswith(".json")]
if len(names) != 2:
    raise SystemExit("note files %r" % (names,))
found = ""
for name in names:
    note = json.load(open(os.path.join(state, "knowledge", name), encoding="utf-8"))
    if note.get("id") == seed:
        continue
    if note.get("title") != ask or note.get("body") != sentence:
        raise SystemExit("saved note is %r" % (note,))
    if found:
        raise SystemExit("more than one new note")
    found = note.get("id") or ""
if not found:
    raise SystemExit("ask note was not written")
print(found)
PY
)"
then
  echo "FAIL: phone ask body"
  cat "$C1/ask.out"
  echo
  cat "$C1/meshd.log"
  exit 1
fi
[ -n "$NOTE_ID" ] || { echo "FAIL: new note id missing"; exit 1; }
NOTE_FILE="$C1/state/knowledge/${NOTE_ID}.json"
[ -f "$NOTE_FILE" ] || { echo "FAIL: note file missing"; exit 1; }
echo "check-speak-phone-answer: phone ask saved the stub sentence"

cp "$NOTE_FILE" "$TH/note-before.json"
: > "$TH/tts-in"
python3 - "$TH/speak.json" <<'PY'
import json, sys
json.dump({"speak": True}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/knowledge/${NOTE_ID}" "$TH/speak.json" "$TH/speak.out")"
[ "$code" = "200" ] || { echo "FAIL: speak -> ${code}"; cat "$TH/speak.out"; echo; cat "$C1/meshd.log"; exit 1; }
python3 - "$TH/speak.out" "$SENTENCE" "$ASK" "$NOTE_ID" "$TH/tts-in" <<'PY' || { echo "FAIL: speak body"; cat "$TH/speak.out"; echo; cat "$TH/tts-in"; exit 1; }
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
body, title, note_id, heard_path = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
data = json.loads(raw)
if data.get("spoken") is not True:
    raise SystemExit("spoken is %r" % (data,))
if data.get("id") != note_id or data.get("title") != title:
    raise SystemExit("response is %r" % (data,))
heard = open(heard_path, encoding="utf-8").read()
if heard != title + "\n" + body:
    raise SystemExit("speaker stdin is %r" % (heard,))
PY
cmp -s "$TH/note-before.json" "$NOTE_FILE" || { echo "FAIL: speak changed the note file"; exit 1; }
python3 - "$NOTE_FILE" "$SENTENCE" "$ASK" <<'PY' || { echo "FAIL: speak changed the note body"; exit 1; }
import json, sys
note = json.load(open(sys.argv[1]))
if note.get("body") != sys.argv[2] or note.get("title") != sys.argv[3]:
    raise SystemExit(note)
PY
fmode="$(stat -c '%a' "$NOTE_FILE" 2>/dev/null || stat -f '%OLp' "$NOTE_FILE")"
fmode="${fmode#0}"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
echo "check-speak-phone-answer: local TTS receives the title and body"
cp "$TH/tts-in" "$TH/tts-before"

stop_srv
wait_port_free
start_daemon "$TOKEN" "$C1/state" "$C1/home" "$C1/remote.log" "$LOCAL_MODEL" "https://example.com/speak"
code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/knowledge/${NOTE_ID}" "$TH/speak.json" "$TH/remote.out")"
[ "$code" = "400" ] || { echo "FAIL: remote MESH_TTS -> ${code}"; cat "$TH/remote.out"; echo; cat "$C1/remote.log"; exit 1; }
python3 - "$TH/remote.out" <<'PY' || { echo "FAIL: remote MESH_TTS body"; cat "$TH/remote.out"; exit 1; }
import json, sys
data = json.load(open(sys.argv[1]))
if data != {"error": "tts must be a local binary"}:
    raise SystemExit(data)
PY
cmp -s "$TH/note-before.json" "$NOTE_FILE" || { echo "FAIL: remote TTS wrote the note"; exit 1; }
cmp -s "$TH/tts-before" "$TH/tts-in" || { echo "FAIL: remote TTS wrote to the local binary"; exit 1; }
python3 - "$NOTE_FILE" "$SENTENCE" <<'PY' || { echo "FAIL: remote TTS changed the note body"; exit 1; }
import json, sys
note = json.load(open(sys.argv[1]))
if note.get("body") != sys.argv[2]:
    raise SystemExit(note)
PY
fmode="$(stat -c '%a' "$NOTE_FILE" 2>/dev/null || stat -f '%OLp' "$NOTE_FILE")"
fmode="${fmode#0}"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
echo "check-speak-phone-answer: remote MESH_TTS is 400 and wrote nothing"
stop_srv
wait_port_free

echo "check-speak-phone-answer: ok"

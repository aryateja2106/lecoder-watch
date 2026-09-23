#!/bin/sh
# A confirmed draft returns the text that was written to draft.txt.
# A pairing-code note stays held with a null reply. An empty or remote
# model is refused and writes nothing.
set -eu
unset AI_GATEWAY_API_KEY

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

TH="$(mktemp -d /tmp/show-drafted-reply.XXXXXX)"
PORT=8898
SRV=
STUB=
STUB_BODIES="$TH/stub-bodies"
SENTENCE="The oak stays on this machine."
QUERY="Oak margin"
NOTE_BODY="The page stays on this machine."
PAIR_BODY="The pairing code is 4821."
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

cleanup() {
  ec=$?
  set +e
  stop_srv
  stop_stub
  n=0
  while port_busy && [ "$n" -lt 50 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  rm -rf "$TH"
  exit "$ec"
}
trap cleanup EXIT

stub_hits() {
  find "$STUB_BODIES" -type f -name '*.json' | wc -l | tr -d '[:space:]'
}

note_count() {
  find "$1/knowledge" -type f -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]'
}

draft_count() {
  find "$1/drafts" -type f 2>/dev/null | wc -l | tr -d '[:space:]'
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
  model=${5-}
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
  if [ -n "$model" ]; then
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
      bun server.ts >"$log" 2>&1 &
  else
    env -u AI_GATEWAY_API_KEY -u MESH_MODEL \
      MESHD_PORT="$PORT" \
      MESHD_HOST=127.0.0.1 \
      MESHD_TOKEN="$token" \
      MESHD_STATE="$state" \
      MESHD_TELEMETRY=off \
      MESHD_EVENTS_PATH="$state/events.jsonl" \
      MESHD_TELEMETRY_STATE="$state/telemetry.json" \
      MESHD_KB_PATH="$state/kb.sqlite" \
      HOME="$home" \
      bun server.ts >"$log" 2>&1 &
  fi
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
  title=$4
  body=$5
  python3 - "$dest" "$title" "$body" <<'PY'
import json, sys
json.dump({"title": sys.argv[2], "body": sys.argv[3]}, open(sys.argv[1], "w"))
PY
  code="$(post_json "$token" "http://127.0.0.1:$PORT/knowledge" "$dest" "$out")"
  [ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}" >&2; cat "$out" >&2; exit 1; }
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$out"
}

write_id_body() {
  dest=$1
  id=$2
  python3 - "$dest" "$id" <<'PY'
import json, sys
dest, note_id = sys.argv[1:3]
body = {"id": note_id, "confirm": True}
if set(body) != {"id", "confirm"}:
    raise SystemExit("draft body keys are wrong")
json.dump(body, open(dest, "w"))
PY
}

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

C1="$TH/local"
mkdir -p "$C1/state" "$C1/home"
TOKEN1="$(new_token)"
start_daemon "$TOKEN1" "$C1/state" "$C1/home" "$C1/meshd.log" "$LOCAL_MODEL"
SEED1="$(seed_note "$TOKEN1" "$C1/seed.json" "$C1/seed.out" "$QUERY" "$NOTE_BODY")"
[ "$(note_count "$C1/state")" = "1" ] || { echo "FAIL: seed note count"; exit 1; }
[ "$(draft_count "$C1/state")" = "0" ] || { echo "FAIL: seed wrote a draft"; exit 1; }
hits="$(stub_hits)"
write_id_body "$C1/ask.json" "$SEED1"
code="$(post_json "$TOKEN1" "http://127.0.0.1:$PORT/agent-note" "$C1/ask.json" "$C1/ask.out")"
[ "$code" = "200" ] || { echo "FAIL: local draft -> ${code}"; cat "$C1/ask.out"; echo; cat "$C1/meshd.log"; exit 1; }
if ! python3 - "$C1/ask.out" "$C1/state" "$SEED1" "$SENTENCE" "$NOTE_BODY" <<'PY'
import json, os, stat, sys
res, state, seed, sentence, note_body = sys.argv[1:6]
data = json.load(open(res))
if data.get("commandRan") is not False or data.get("held") is not False:
    raise SystemExit("result is %r" % (data,))
draft = data.get("draft")
if draft != "draft.txt" or os.path.isabs(str(draft)):
    raise SystemExit("draft is %r" % (draft,))
drafts = os.path.realpath(os.path.join(state, "drafts"))
path = os.path.realpath(os.path.join(drafts, "draft.txt"))
if os.path.dirname(path) != drafts:
    raise SystemExit("draft is not inside state drafts: %s" % path)
if not path.startswith(os.path.realpath(state) + os.sep):
    raise SystemExit("draft left state: %s" % path)
mode = stat.S_IMODE(os.stat(path).st_mode)
if mode != 0o600:
    raise SystemExit("draft mode is %o" % mode)
dir_mode = stat.S_IMODE(os.stat(drafts).st_mode)
if dir_mode != 0o700:
    raise SystemExit("drafts mode is %o" % dir_mode)
file_text = open(path, encoding="utf-8").read()
if file_text != sentence:
    raise SystemExit("draft text is %r" % (file_text,))
if data.get("reply") != file_text:
    raise SystemExit("reply is %r" % (data.get("reply"),))
note = json.load(open(os.path.join(state, "knowledge", seed + ".json"), encoding="utf-8"))
if note.get("body") != note_body:
    raise SystemExit("note body changed: %r" % (note,))
names = [name for name in os.listdir(os.path.join(state, "knowledge")) if name.endswith(".json")]
if names != [seed + ".json"]:
    raise SystemExit("note files %r" % (names,))
PY
then
  echo "FAIL: local draft body"
  cat "$C1/ask.out"
  echo
  cat "$C1/meshd.log"
  exit 1
fi
[ "$(note_count "$C1/state")" = "1" ] || { echo "FAIL: draft changed the note count"; exit 1; }
[ "$(stub_hits)" = "$((hits + 1))" ] || { echo "FAIL: local draft called the stub $(stub_hits) times"; exit 1; }
echo "check-show-drafted-reply: local reply matches draft.txt"
stop_srv
wait_port_free

C2="$TH/empty"
mkdir -p "$C2/state" "$C2/home"
TOKEN2="$(new_token)"
start_daemon "$TOKEN2" "$C2/state" "$C2/home" "$C2/meshd.log"
SEED2="$(seed_note "$TOKEN2" "$C2/seed.json" "$C2/seed.out" "$QUERY" "$NOTE_BODY")"
hits="$(stub_hits)"
write_id_body "$C2/ask.json" "$SEED2"
code="$(post_json "$TOKEN2" "http://127.0.0.1:$PORT/agent-note" "$C2/ask.json" "$C2/ask.out")"
[ "$code" = "400" ] || { echo "FAIL: empty model -> ${code}"; cat "$C2/ask.out"; echo; cat "$C2/meshd.log"; exit 1; }
python3 - "$C2/ask.out" <<'PY' || { echo "FAIL: empty model body"; cat "$C2/ask.out"; exit 1; }
import json, sys
data = json.load(open(sys.argv[1]))
if data != {"error": "model must be local"}:
    raise SystemExit(data)
PY
[ "$(draft_count "$C2/state")" = "0" ] || { echo "FAIL: empty model wrote a draft"; exit 1; }
[ "$(stub_hits)" = "$hits" ] || { echo "FAIL: empty model called the stub"; exit 1; }
echo "check-show-drafted-reply: empty model refused"
stop_srv
wait_port_free

C3="$TH/remote"
mkdir -p "$C3/state" "$C3/home"
TOKEN3="$(new_token)"
start_daemon "$TOKEN3" "$C3/state" "$C3/home" "$C3/meshd.log" "https://example.com/v1"
SEED3="$(seed_note "$TOKEN3" "$C3/seed.json" "$C3/seed.out" "$QUERY" "$NOTE_BODY")"
hits="$(stub_hits)"
write_id_body "$C3/ask.json" "$SEED3"
code="$(post_json "$TOKEN3" "http://127.0.0.1:$PORT/agent-note" "$C3/ask.json" "$C3/ask.out")"
[ "$code" = "400" ] || { echo "FAIL: remote model -> ${code}"; cat "$C3/ask.out"; echo; cat "$C3/meshd.log"; exit 1; }
python3 - "$C3/ask.out" <<'PY' || { echo "FAIL: remote model body"; cat "$C3/ask.out"; exit 1; }
import json, sys
data = json.load(open(sys.argv[1]))
if data != {"error": "model must be local"}:
    raise SystemExit(data)
PY
[ "$(draft_count "$C3/state")" = "0" ] || { echo "FAIL: remote model wrote a draft"; exit 1; }
[ "$(stub_hits)" = "$hits" ] || { echo "FAIL: remote model called the stub"; exit 1; }
echo "check-show-drafted-reply: non-local model refused"
stop_srv
wait_port_free

C4="$TH/pair"
mkdir -p "$C4/state" "$C4/home"
TOKEN4="$(new_token)"
start_daemon "$TOKEN4" "$C4/state" "$C4/home" "$C4/meshd.log" "$LOCAL_MODEL"
SEED4="$(seed_note "$TOKEN4" "$C4/seed.json" "$C4/seed.out" "Pairing paper" "$PAIR_BODY")"
[ "$(note_count "$C4/state")" = "1" ] || { echo "FAIL: pairing seed note count"; exit 1; }
hits="$(stub_hits)"
write_id_body "$C4/ask.json" "$SEED4"
code="$(post_json "$TOKEN4" "http://127.0.0.1:$PORT/agent-note" "$C4/ask.json" "$C4/ask.out")"
[ "$code" = "200" ] || { echo "FAIL: pairing note -> ${code}"; cat "$C4/ask.out"; echo; cat "$C4/meshd.log"; exit 1; }
python3 - "$C4/ask.out" <<'PY' || { echo "FAIL: pairing note body"; cat "$C4/ask.out"; exit 1; }
import json, sys
data = json.load(open(sys.argv[1]))
if "reply" not in data or data.get("reply") is not None:
    raise SystemExit(data)
if data.get("modelClass") != "local" or data.get("draft") is not None or data.get("commandRan") is not False or data.get("held") is not True:
    raise SystemExit(data)
PY
[ "$(draft_count "$C4/state")" = "0" ] || { echo "FAIL: pairing note wrote a draft"; exit 1; }
[ ! -d "$C4/state/drafts" ] || { echo "FAIL: pairing note created a drafts directory"; exit 1; }
[ "$(stub_hits)" = "$hits" ] || { echo "FAIL: pairing note called the stub"; exit 1; }
[ "$(note_count "$C4/state")" = "1" ] || { echo "FAIL: pairing note changed the note count"; exit 1; }
echo "check-show-drafted-reply: pairing note held"
stop_srv
wait_port_free

echo "check-show-drafted-reply: ok"

#!/bin/sh
# A spare daemon replaces one saved note's body and leaves the title alone.
# An empty body is refused. A missing id writes nothing.
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

TH="$(mktemp -d /tmp/save-shown-reply.XXXXXX)"
STATE="$TH/state"
PORT=8898
SRV=
TITLE="Shown question"
OLD_BODY="Old page stays here."
NEW_BODY="Saved reply stays here."

case "$TH" in
  /tmp/*) ;;
  *) echo "FAIL: temp dir is not under /tmp"; exit 1 ;;
esac
case "$STATE" in
  /tmp/*) ;;
  *) echo "FAIL: state is not under /tmp"; exit 1 ;;
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
  n=0
  while port_busy && [ "$n" -lt 50 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  rm -rf "$TH"
  exit "$ec"
}
trap cleanup EXIT

note_count() {
  find "$STATE/knowledge" -type f -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]'
}

mode_of() {
  m="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1")"
  echo "${m#0}"
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

if port_busy; then
  echo "FAIL: port 8898 is already in use"
  exit 1
fi

TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
mkdir -p "$STATE"
env -u AI_GATEWAY_API_KEY \
  MESHD_PORT="$PORT" \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$STATE" \
  MESHD_TELEMETRY=off \
  MESHD_EVENTS_PATH="$STATE/events.jsonl" \
  MESHD_TELEMETRY_STATE="$STATE/telemetry.json" \
  MESHD_KB_PATH="$STATE/kb.sqlite" \
  HOME="$TH" \
  bun server.ts >"$TH/meshd.log" 2>&1 &
SRV=$!

up=0
i=0
while [ "$i" -lt 300 ]; do
  if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    up=1
    break
  fi
  kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited before listening"; cat "$TH/meshd.log"; exit 1; }
  sleep 0.1
  i=$((i + 1))
done
[ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on $PORT"; cat "$TH/meshd.log"; exit 1; }

python3 - "$TH/seed.json" "$TITLE" "$OLD_BODY" <<'PY'
import json, sys
json.dump({"title": sys.argv[2], "body": sys.argv[3]}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/knowledge" "$TH/seed.json" "$TH/seed.out")"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/seed.out"; echo; cat "$TH/meshd.log"; exit 1; }
ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/seed.out")"
NOTE_FILE="$STATE/knowledge/${ID}.json"
[ -f "$NOTE_FILE" ] || { echo "FAIL: seeded note file is missing"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: expected one note after seed, found $(note_count)"; exit 1; }

python3 - "$TH/replace.json" "$NEW_BODY" <<'PY'
import json, sys
json.dump({"body": sys.argv[2]}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/knowledge/${ID}" "$TH/replace.json" "$TH/replace.out")"
[ "$code" = "200" ] || { echo "FAIL: POST /knowledge/:id -> ${code}"; cat "$TH/replace.out"; echo; cat "$TH/meshd.log"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: replace changed the note count to $(note_count)"; exit 1; }
python3 - "$NOTE_FILE" "$TH/replace.out" "$ID" "$TITLE" "$NEW_BODY" <<'PY'
import json, sys
note_path, response_path, note_id, title, body = sys.argv[1:6]
stored = json.load(open(note_path))
if stored.get("id") != note_id:
    raise SystemExit("FAIL: stored id is %r" % (stored.get("id"),))
if stored.get("title") != title:
    raise SystemExit("FAIL: replace changed the title to %r" % (stored.get("title"),))
if stored.get("body") != body:
    raise SystemExit("FAIL: stored body is %r" % (stored.get("body"),))
shown = json.load(open(response_path))
if shown.get("title") != title:
    raise SystemExit("FAIL: response title is %r" % (shown.get("title"),))
if shown.get("body") != body:
    raise SystemExit("FAIL: response body is %r" % (shown.get("body"),))
PY
fmode="$(mode_of "$NOTE_FILE")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
cp "$NOTE_FILE" "$TH/before-empty.json"

python3 - "$TH/empty.json" <<'PY'
import json, sys
json.dump({"body": ""}, open(sys.argv[1], "w"))
PY
code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/knowledge/${ID}" "$TH/empty.json" "$TH/empty.out")"
[ "$code" = "400" ] || { echo "FAIL: empty body -> ${code}"; cat "$TH/empty.out"; echo; exit 1; }
cmp -s "$NOTE_FILE" "$TH/before-empty.json" || { echo "FAIL: empty body changed the note file"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: empty body changed the note count"; exit 1; }

MISSING="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
[ "$MISSING" != "$ID" ] || { echo "FAIL: missing id collided with the seeded note"; exit 1; }
python3 - "$TH/missing.json" <<'PY'
import json, sys
json.dump({"body": "should not land"}, open(sys.argv[1], "w"))
PY
before="$(find "$STATE/knowledge" -type f -name '*.json' | sort)"
code="$(post_json "$TOKEN" "http://127.0.0.1:$PORT/knowledge/${MISSING}" "$TH/missing.json" "$TH/missing.out")"
[ "$code" = "404" ] || { echo "FAIL: missing id -> ${code}"; cat "$TH/missing.out"; echo; exit 1; }
after="$(find "$STATE/knowledge" -type f -name '*.json' | sort)"
[ "$before" = "$after" ] || { echo "FAIL: missing id created a file"; exit 1; }
[ ! -e "$STATE/knowledge/${MISSING}.json" ] || { echo "FAIL: missing id created a file"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: missing id changed the note count"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/before-empty.json" || { echo "FAIL: missing id changed the seeded note"; exit 1; }

stop_srv
wait_port_free
echo "check-save-shown-reply: OK"

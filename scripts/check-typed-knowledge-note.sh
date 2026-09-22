#!/bin/sh
# A spare daemon stores one typed note and refuses a whitespace title.
# State and HOME stay under /tmp. Telemetry stays off. No model process.
# The listener is 127.0.0.1:8898, and it is gone when this script exits.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

TH="$(mktemp -d /tmp/typed-knowledge-note.XXXXXX)"
STATE="$TH/state"
HOME_DIR="$TH/home"
LOG="$TH/meshd.log"
PORT=8898
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
NOTE_TITLE="Spare typed note"
NOTE_BODY="The pairing code K7QM-2N4P stays in this note."
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
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn | grep -q ":${PORT} "; then
      echo "FAIL: port ${PORT} is still listening"
      ec=1
    fi
  fi
  rm -rf "$TH"
  exit "$ec"
}
trap cleanup EXIT

mkdir -p "$STATE" "$HOME_DIR"
python3 - "$TH/note.json" "$NOTE_TITLE" "$NOTE_BODY" <<'PY'
import json, sys
json.dump({"title": sys.argv[2], "body": sys.argv[3]}, open(sys.argv[1], "w"))
PY
printf '%s' '{"title":"   ","body":"should not land"}' > "$TH/blank.json"

if command -v ss >/dev/null 2>&1; then
  if ss -ltn | grep -q ":${PORT} "; then
    echo "FAIL: port ${PORT} is already in use"
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
HOME="$HOME_DIR" \
bun server.ts >"$LOG" 2>&1 &
SRV=$!

up=0
i=0
while [ "$i" -lt 50 ]; do
  if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    up=1
    break
  fi
  kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited before listening"; cat "$LOG"; exit 1; }
  sleep 0.1
  i=$((i + 1))
done
[ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on ${PORT}"; cat "$LOG"; exit 1; }

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/post.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data-binary @"$TH/note.json" \
  "http://127.0.0.1:${PORT}/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; echo; cat "$LOG"; exit 1; }

python3 - "$TH/post.json" "$NOTE_BODY" "$NOTE_TITLE" "$TH/id" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
body, title, id_path = sys.argv[2], sys.argv[3], sys.argv[4]
if body in raw:
    raise SystemExit("FAIL: response text contains the body")
data = json.loads(raw)
if set(data) != {"id", "title"}:
    raise SystemExit("FAIL: response keys are %r" % (sorted(data),))
if data.get("title") != title or not data.get("id"):
    raise SystemExit("FAIL: response is %r" % (data,))
open(id_path, "w", encoding="utf-8").write(data["id"])
PY
echo "check-typed-knowledge-note: POST 201 {id, title} and the response omits the body"

NOTE_ID="$(cat "$TH/id")"
found=0
for f in "$STATE/knowledge"/*.json; do
  [ -f "$f" ] || continue
  found=$((found + 1))
  grep -q "$NOTE_BODY" "$f" || { echo "FAIL: note file dropped the body"; exit 1; }
  fmode="$(stat -c '%a' "$f" 2>/dev/null || stat -f '%OLp' "$f")"
  fmode="${fmode#0}"
  [ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
done
[ "$found" -eq 1 ] || { echo "FAIL: expected one note file, found $found"; exit 1; }
echo "check-typed-knowledge-note: note file is mode 600"
echo "check-typed-knowledge-note: pairing code in the body is stored"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:${PORT}/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; cat "$TH/list.json"; echo; exit 1; }
python3 - "$TH/list.json" "$NOTE_BODY" "$NOTE_TITLE" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
body, title = sys.argv[2], sys.argv[3]
if body in raw:
    raise SystemExit("FAIL: list contains the body")
data = json.loads(raw)
titles = [n.get("title") for n in data.get("notes", [])]
if title not in titles:
    raise SystemExit("FAIL: list titles are %r" % (titles,))
PY
echo "check-typed-knowledge-note: GET /knowledge lists the title and not the body"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/one.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:${PORT}/knowledge/${NOTE_ID}" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge/${NOTE_ID} -> ${code}"; cat "$TH/one.json"; echo; exit 1; }
python3 - "$TH/one.json" "$NOTE_BODY" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("body") != sys.argv[2]:
    raise SystemExit("FAIL: read body is %r" % (data.get("body"),))
PY
echo "check-typed-knowledge-note: GET /knowledge/:id returns the body"

before="$found"
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/blank-out.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data-binary @"$TH/blank.json" \
  "http://127.0.0.1:${PORT}/knowledge" || true)"
[ "$code" = "400" ] || { echo "FAIL: whitespace title -> ${code}"; cat "$TH/blank-out.json"; echo; exit 1; }
after=0
for f in "$STATE/knowledge"/*.json; do
  [ -f "$f" ] || continue
  after=$((after + 1))
  grep -q 'should not land' "$f" && { echo "FAIL: whitespace title wrote a file"; exit 1; }
done
[ "$after" -eq "$before" ] || { echo "FAIL: whitespace title changed the note count from $before to $after"; exit 1; }
echo "check-typed-knowledge-note: whitespace title is 400 and wrote no file"
echo "check-typed-knowledge-note: OK"

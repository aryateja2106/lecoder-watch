#!/bin/sh
# A spare daemon replaces the body of one local note. The same file stays
# mode 600 under MESHD_STATE/knowledge, and that directory stays mode 700.
# A second note is a failure. A remote URL, a scheme, or a protocol-relative
# path must not write. This script starts the daemon on 127.0.0.1:8898 and
# stops it before exit. It does not use port 8899 or a real home directory.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH
command -v bun >/dev/null 2>&1 || { echo "check-knowledge-update: SKIP (bun not installed)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

grep -q 'handleKnowledge' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route knowledge"
  exit 1
}
calls="$(grep -c 'handleKnowledge(' "$ROOT/install/payload/meshd/server.ts" || true)"
[ "$calls" = "1" ] || { echo "FAIL: expected one knowledge route, found $calls"; exit 1; }
if grep -E -n 'supabase|fetch\(|ai-gateway' "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: knowledge.ts reaches the network"
  exit 1
fi
grep -q 'MESH_STT' "$ROOT/install/payload/meshd/knowledge.ts" || {
  echo "FAIL: knowledge.ts dropped MESH_STT"
  exit 1
}
grep -q 'MESH_TTS' "$ROOT/install/payload/meshd/knowledge.ts" || {
  echo "FAIL: knowledge.ts dropped speak-out"
  exit 1
}

TH="$(mktemp -d)"
STATE="$TH/state"
PDF="$TH/paper.pdf"
LOG="$TH/meshd.log"
PORT=8898
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
SRV=
NOTE_FILE=

[ "$PORT" = "8898" ] || { echo "FAIL: spare daemon must listen on 8898"; exit 1; }

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

note_count() {
  found=0
  for f in "$STATE/knowledge"/*.json; do
    [ -f "$f" ] || continue
    found=$((found + 1))
  done
  echo "$found"
}

mode_of() {
  m="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1")"
  echo "${m#0}"
}

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/post.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data "{\"path\":\"${PDF}\"}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; echo; cat "$LOG"; exit 1; }
ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/post.json")"
NOTE_FILE="$STATE/knowledge/${ID}.json"
[ -f "$NOTE_FILE" ] || { echo "FAIL: created note file is missing"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: expected one note after create, found $(note_count)"; exit 1; }

python3 - "$TH/update.json" 'Replaced on this machine' <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"body": sys.argv[2]}))
PY
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/updated.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/update.json" \
  "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
[ "$code" = "200" ] || { echo "FAIL: POST /knowledge/:id -> ${code}"; cat "$TH/updated.json"; echo; cat "$LOG"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: update created a second note, found $(note_count)"; exit 1; }
python3 - "$NOTE_FILE" "$ID" <<'PY'
import json, sys
note = json.load(open(sys.argv[1]))
if note.get("id") != sys.argv[2]:
    raise SystemExit("FAIL: updated file id is %r" % (note.get("id"),))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: update changed the title to %r" % (note.get("title"),))
if note.get("body") != "Replaced on this machine":
    raise SystemExit("FAIL: updated body is %r" % (note.get("body"),))
PY
fmode="$(mode_of "$NOTE_FILE")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-knowledge-update: one note replaced in place"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge -> ${code}"; cat "$TH/list.json"; echo; exit 1; }
python3 - "$TH/list.json" "$ID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
notes = data.get("notes")
if not isinstance(notes, list) or len(notes) != 1:
    raise SystemExit("FAIL: list is %r" % (notes,))
note = notes[0]
if set(note.keys()) != {"id", "title"}:
    raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
if note.get("id") != sys.argv[2] or note.get("title") != "Spare note":
    raise SystemExit("FAIL: list note is %r" % (note,))
PY
if grep -q 'Replaced on this machine' "$TH/list.json"; then
  echo "FAIL: GET /knowledge returned the note body"
  exit 1
fi
echo "check-knowledge-update: list is id and title"

code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/one.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge/:id -> ${code}"; cat "$TH/one.json"; echo; exit 1; }
python3 - "$TH/one.json" "$ID" <<'PY'
import json, sys
note = json.load(open(sys.argv[1]))
if note.get("id") != sys.argv[2]:
    raise SystemExit("FAIL: read id is %r" % (note.get("id"),))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: read title is %r" % (note.get("title"),))
if note.get("body") != "Replaced on this machine":
    raise SystemExit("FAIL: read body is %r" % (note.get("body"),))
PY
echo "check-knowledge-update: read returns the new body"

cp "$NOTE_FILE" "$TH/frozen.json"
refuse_remote() {
  label="$1"
  payload="$2"
  python3 - "$TH/remote.json" "$payload" <<'PY'
import json, sys
open(sys.argv[1], "w").write(sys.argv[2])
PY
  code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/remote-out.json" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/remote.json" \
    "http://127.0.0.1:$PORT/knowledge/${ID}" || true)"
  cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: $label wrote the note"; exit 1; }
  [ "$(note_count)" = "1" ] || { echo "FAIL: $label created another note"; exit 1; }
  case "$code" in
    200|201) echo "FAIL: $label was stored ($code)"; cat "$TH/remote-out.json"; echo; exit 1 ;;
  esac
  echo "check-knowledge-update: $label"
}

refuse_remote "remote body did not write" '{"body":"http://127.0.0.1:9/stolen"}'
refuse_remote "https body did not write" '{"body":"https://example.com/stolen"}'
refuse_remote "scheme body did not write" '{"body":"notes://stolen"}'
refuse_remote "protocol-relative body did not write" '{"body":"//127.0.0.1/stolen"}'
refuse_remote "scheme path did not write" "{\"body\":\"${TH}/bin://stolen\"}"
refuse_remote "remote path did not write" '{"path":"http://127.0.0.1:9/stolen"}'
refuse_remote "remote path beside text did not write" '{"body":"should not land","path":"https://example.com/stolen"}'

MISS="$(python3 -c 'import uuid; print(uuid.uuid4())')"
python3 - "$TH/missing.json" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"body": "do not create this note"}))
PY
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/missing-out.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/missing.json" \
  "http://127.0.0.1:$PORT/knowledge/${MISS}" || true)"
[ "$code" = "404" ] || { echo "FAIL: missing id -> ${code}"; cat "$TH/missing-out.json"; echo; exit 1; }
[ ! -e "$STATE/knowledge/${MISS}.json" ] || { echo "FAIL: missing id created a note"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: missing id changed the note count to $(note_count)"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: missing id rewrote the existing note"; exit 1; }
echo "check-knowledge-update: missing id created nothing"

fmode="$(mode_of "$NOTE_FILE")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
echo "check-knowledge-update: OK"

#!/bin/sh
# Proves POST /agent-note does not store the model URL or a key inside it.
# An allowed ask on a spare loopback daemon returns modelClass local, writes
# one relative mode-600 file that is not executed, and saves one knowledge
# note titled with the ask. The note body is the model reply only. A
# pairing-code ask against a user subscription is held before any model
# call. The knowledge list stays {id, title}.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

unset AI_GATEWAY_API_KEY || true
export PATH="${HOME}/.bun/bin:${PATH}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing $1" >&2
    exit 1
  }
}
need bun
need python3
need curl

TMP=$(mktemp -d /tmp/mesh-note-omits-url.XXXXXX)
DAEMON_PID=""
STUB_PID=""

# Start a command as its own session. The pid is the process-group leader,
# so exit can signal bun and the child it spawns without touching any other
# client of the port.
spawn_group() {
  log=$1
  workdir=$2
  shift 2
  python3 - "$log" "$workdir" "$@" << 'PY' &
import os, sys
logfile, workdir = sys.argv[1], sys.argv[2]
cmd = sys.argv[3:]
try:
    os.setsid()
except OSError:
    if os.getpid() != os.getpgrp():
        raise
os.chdir(workdir)
fd = os.open(logfile, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
os.dup2(fd, 1)
os.dup2(fd, 2)
if fd > 2:
    os.close(fd)
os.execvp(cmd[0], cmd)
PY
  SPAWN_PID=$!
}

stop_group() {
  pgid=$1
  [ -n "$pgid" ] || return 0
  kill -TERM "-$pgid" 2>/dev/null || true
  i=0
  while [ "$i" -lt 25 ]; do
    kill -0 "-$pgid" 2>/dev/null || return 0
    i=$((i + 1))
    sleep 0.1
  done
  kill -KILL "-$pgid" 2>/dev/null || true
  wait "$pgid" 2>/dev/null || true
}

cleanup() {
  stop_group "$DAEMON_PID"
  DAEMON_PID=""
  stop_group "$STUB_PID"
  STUB_PID=""
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
  TMP=""
}
trap cleanup EXIT INT TERM

export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/state" "$TMP/work" "$TMP/meta"
export MESHD_STATE="$TMP/state"
export MESHD_PORT=8898
export MESHD_HOST=127.0.0.1
export MESHD_TOKEN=throwaway
export MESHD_TELEMETRY=off

if [ "$MESHD_PORT" = "8899" ]; then
  echo "refusing port 8899" >&2
  exit 1
fi
case "$HOME" in
  /Users/*|/home/*)
    echo "refusing real home: $HOME" >&2
    exit 1
    ;;
esac
case "$MESHD_STATE" in
  /tmp/*) ;;
  *)
    echo "refusing state outside /tmp: $MESHD_STATE" >&2
    exit 1
    ;;
esac

if curl -sf --max-time 1 "http://127.0.0.1:${MESHD_PORT}/health" >/dev/null 2>&1; then
  echo "port ${MESHD_PORT} already has a listener" >&2
  exit 1
fi

STUB_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
if [ "$STUB_PORT" = "8899" ] || [ "$STUB_PORT" = "8898" ]; then
  echo "stub picked a reserved port" >&2
  exit 1
fi

cat > "$TMP/meta/stub.py" << 'PY'
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length)
        host = self.headers.get("Host", "")
        target = self.path
        url = "http://%s%s" % (host, target)
        headers = {k: v for k, v in self.headers.items()}
        rec = {
            "url": url,
            "path": target,
            "requestline": self.requestline,
            "host": host,
            "headers": headers,
            "body": body.decode("utf-8", "replace"),
        }
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec) + "\n")
        payload = json.dumps({
            "id": "stub",
            "choices": [{"message": {"role": "assistant", "content": "Noted."}}],
        }).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self.do_POST()

    def log_message(self, fmt, *args):
        return

if __name__ == "__main__":
    port = int(sys.argv[1])
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY

: > "$TMP/meta/stub.jsonl"
spawn_group "$TMP/meta/stub.log" "$TMP" \
  python3 "$TMP/meta/stub.py" "$STUB_PORT" "$TMP/meta/stub.jsonl"
STUB_PID=$SPAWN_PID

stub_ready=0
i=0
while [ "$i" -lt 50 ]; do
  if curl -sf --max-time 1 "http://127.0.0.1:${STUB_PORT}/v1" >/dev/null 2>&1; then
    stub_ready=1
    break
  fi
  i=$((i + 1))
  sleep 0.1
done
if [ "$stub_ready" -ne 1 ]; then
  echo "model stub did not listen on ${STUB_PORT}" >&2
  cat "$TMP/meta/stub.log" >&2 || true
  exit 1
fi
# The readiness probe is not an agent-note call. Drop it so hit counts start clean.
: > "$TMP/meta/stub.jsonl"

spawn_group "$TMP/meta/daemon.log" "$TMP/work" \
  bun run "$ROOT/install/payload/meshd/server.ts"
DAEMON_PID=$SPAWN_PID

ready=0
i=0
while [ "$i" -lt 75 ]; do
  if curl -sf --max-time 1 "http://127.0.0.1:${MESHD_PORT}/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
    break
  fi
  i=$((i + 1))
  sleep 0.2
done
if [ "$ready" -ne 1 ]; then
  echo "spare daemon did not become healthy on 127.0.0.1:${MESHD_PORT}" >&2
  cat "$TMP/meta/daemon.log" >&2 || true
  exit 1
fi

hit_count() {
  if [ ! -s "$TMP/meta/stub.jsonl" ]; then
    echo 0
    return
  fi
  wc -l < "$TMP/meta/stub.jsonl" | tr -d ' '
}

mode600_list() {
  find "$TMP/work" -type f -perm 600 2>/dev/null | sort
}

post_note() {
  req=$1
  out=$2
  code=$(curl -sS --max-time 20 -o "$out" -w '%{http_code}' \
    -H "Authorization: Bearer ${MESHD_TOKEN}" \
    -H "Content-Type: application/json" \
    -X POST "http://127.0.0.1:${MESHD_PORT}/agent-note" \
    --data-binary "@${req}")
  printf '%s' "$code"
}

# Scan daemon state and held draft files only. Request bodies and the stub
# log live under meta and are allowed to contain the secret.
scan_absent() {
  python3 - "$@" << 'PY'
import os, sys
roots = []
needles = []
for arg in sys.argv[1:]:
    if arg.startswith("needle:"):
        needles.append(arg[len("needle:"):])
    else:
        roots.append(arg)
bad = []
seen = set()

def consider(path):
    if path in seen or not os.path.isfile(path):
        return
    seen.add(path)
    try:
        data = open(path, "rb").read()
    except OSError as exc:
        bad.append("%s: %s" % (path, exc))
        return
    for needle in needles:
        if needle.encode("utf-8") in data:
            bad.append("%s contains %s" % (path, needle))

for root in roots:
    if os.path.isfile(root):
        consider(root)
        continue
    if not os.path.isdir(root):
        continue
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            consider(os.path.join(dirpath, name))
if bad:
    raise SystemExit("stored model url or key:\n" + "\n".join(bad))
PY
}

python3 - "$TMP/meta/source.pdf" << 'PY'
import sys
path = sys.argv[1]
title = "Source note".replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
stream = b"BT /F1 12 Tf 72 720 Td (Local page) Tj ET\n"
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"endstream",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ("<< /Title (%s) >>" % title).encode(),
]
out = bytearray(b"%PDF-1.4\n")
for i, obj in enumerate(objects, start=1):
    out += f"{i} 0 obj\n".encode() + obj + b"\nendobj\n"
out += b"trailer\n<< /Root 1 0 R /Info 6 0 R >>\n%%EOF\n"
open(path, "wb").write(out)
PY
python3 - "$TMP/meta/source.req" "$TMP/meta/source.pdf" << 'PY'
import json, sys
json.dump({"path": sys.argv[2]}, open(sys.argv[1], "w"))
PY
source_code=$(curl -sS --max-time 10 -o "$TMP/meta/source.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST "http://127.0.0.1:${MESHD_PORT}/knowledge" \
  --data-binary "@$TMP/meta/source.req")
if [ "$source_code" != "201" ]; then
  echo "source note -> ${source_code}" >&2
  cat "$TMP/meta/source.json" >&2 || true
  exit 1
fi

list_code=$(curl -sS --max-time 10 -o "$TMP/meta/before.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
if [ "$list_code" != "200" ]; then
  echo "knowledge list before ask -> ${list_code}" >&2
  exit 1
fi

ASK="draft a short thanks"
MODEL_URL="http://user:sk-secret@127.0.0.1:${STUB_PORT}/v1"

echo "1. allowed ask, local model with a key in the url"
python3 - "$TMP/meta/case1.req" "$TMP/work" "$MODEL_URL" "$ASK" << 'PY'
import json, sys
json.dump({
    "q": "Source note",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "ask": sys.argv[4],
}, open(sys.argv[1], "w"))
PY
before=$(mode600_list || true)
hits_before=$(hit_count)
code=$(post_note "$TMP/meta/case1.req" "$TMP/meta/case1.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case1.json" >&2 || true
  exit 1
fi
printf '%s\n' "$before" > "$TMP/meta/before1.txt"
mode600_list > "$TMP/meta/after1.txt" || true
python3 - "$TMP/meta/case1.json" "$TMP/meta/before1.txt" "$TMP/meta/after1.txt" "$TMP/work" "$TMP/meta/before.json" "$ASK" "$hits_before" "$hits_after" << 'PY'
import json, os, sys
body_path, before_path, after_path, work, listed_path, ask, hits_before, hits_after = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
if "sk-secret" in raw or "user:sk-secret" in raw:
    raise SystemExit("case 1 response contains the key")
obj = json.loads(raw)
keys = set(obj.keys())
if keys != {"modelClass", "draft", "commandRan", "held", "reply"}:
    raise SystemExit("case 1 keys %s" % sorted(keys))
if obj["modelClass"] != "local":
    raise SystemExit("case 1 modelClass %r" % obj["modelClass"])
if obj["commandRan"] is not False:
    raise SystemExit("case 1 commandRan %r (file must not be executed)" % obj["commandRan"])
if obj["held"] is not False:
    raise SystemExit("case 1 held %r" % obj["held"])
draft = obj["draft"]
if not isinstance(draft, str) or not draft or os.path.isabs(draft) or draft.startswith("..") or "/" in draft:
    raise SystemExit("case 1 draft is not one relative file: %r" % draft)
before = {ln for ln in open(before_path, encoding="utf-8").read().splitlines() if ln}
after = {ln for ln in open(after_path, encoding="utf-8").read().splitlines() if ln}
new = sorted(after - before)
if new != [os.path.join(work, draft)]:
    raise SystemExit("case 1 expected one new mode-600 file, got %s" % new)
path = new[0]
mode = os.stat(path).st_mode & 0o777
if mode != 0o600 or mode & 0o111:
    raise SystemExit("case 1 mode %o" % mode)
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("case 1 stub hits %s -> %s" % (hits_before, hits_after))
listed = json.loads(open(listed_path, encoding="utf-8").read())
ids = {item["id"] for item in listed["notes"]}
open(os.path.join(os.path.dirname(body_path), "case1.draft"), "w", encoding="utf-8").write(path)
open(os.path.join(os.path.dirname(body_path), "case1.ids"), "w", encoding="utf-8").write("\n".join(sorted(ids)))
print("   file", draft)
PY

echo "2. state and the held draft omit the model url and the key"
DRAFT_FILE=$(cat "$TMP/meta/case1.draft")
scan_absent "$MESHD_STATE" "$DRAFT_FILE" \
  "needle:sk-secret" "needle:user:sk-secret" "needle:${MODEL_URL}"
python3 - "$MESHD_STATE" "$TMP/meta/case1.ids" "$ASK" "$DRAFT_FILE" << 'PY'
import json, os, sys
state, ids_path, ask, draft_path = sys.argv[1:]
previous = {ln for ln in open(ids_path, encoding="utf-8").read().splitlines() if ln}
notes_dir = os.path.join(state, "knowledge")
found = []
for name in os.listdir(notes_dir):
    if not name.endswith(".json"):
        continue
    path = os.path.join(notes_dir, name)
    note = json.loads(open(path, encoding="utf-8").read())
    if note.get("id") in previous:
        continue
    found.append(note)
if len(found) != 1:
    raise SystemExit("expected one new knowledge note, got %s" % len(found))
note = found[0]
if note.get("title") != ask:
    raise SystemExit("note title is %r" % note.get("title"))
if note.get("body") != "Noted.":
    raise SystemExit("note body is not the model reply only")
draft = open(draft_path, encoding="utf-8").read()
if draft != "Noted.":
    raise SystemExit("draft file is not the model reply only")
print("   note", note["title"])
PY

echo "3. pairing-code ask, user-subscription model, no stub call"
python3 - "$TMP/meta/case2.req" "$TMP/work" << 'PY'
import json, sys
json.dump({
    "q": "Source note",
    "cwd": sys.argv[2],
    "model": "https://llm.example/v1",
    "ask": "show the pairing code",
}, open(sys.argv[1], "w"))
PY
hits_before=$(hit_count)
code=$(post_note "$TMP/meta/case2.req" "$TMP/meta/case2.json")
echo "   http ${code}"
hits_after=$(hit_count)
python3 - "$TMP/meta/case2.json" "$hits_before" "$hits_after" << 'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
obj = json.loads(raw)
keys = set(obj.keys())
if keys != {"modelClass", "draft", "commandRan", "held", "reply"}:
    raise SystemExit("case 2 keys %s" % sorted(keys))
if obj["modelClass"] != "user-subscription":
    raise SystemExit("case 2 modelClass %r" % obj["modelClass"])
if obj["held"] is not True:
    raise SystemExit("case 2 held %r" % obj["held"])
if obj["draft"] is not None:
    raise SystemExit("case 2 draft %r" % obj["draft"])
before, after = int(sys.argv[2]), int(sys.argv[3])
if after != before:
    raise SystemExit("case 2 stub hits %s -> %s" % (before, after))
print("   held, stub hits", after)
PY
scan_absent "$MESHD_STATE" "needle:llm.example" "needle:sk-secret"

echo "4. knowledge list stays {id, title}"
kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   http ${kcode}"
python3 - "$TMP/meta/knowledge.json" "$ASK" << 'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
ask = sys.argv[2]
obj = json.loads(raw)
if not isinstance(obj, dict) or set(obj.keys()) != {"notes"} or not isinstance(obj["notes"], list):
    raise SystemExit("knowledge payload keys are wrong")
items = obj["notes"]
if not items:
    raise SystemExit("knowledge list is empty")
titles = []
for item in items:
    if set(item.keys()) != {"id", "title"}:
        raise SystemExit("knowledge item keys %s" % sorted(item.keys()))
    titles.append(item["title"])
if titles.count(ask) != 1:
    raise SystemExit("ask title count %s" % titles.count(ask))
if "body" in raw or "sk-secret" in raw or "llm.example" in raw:
    raise SystemExit("knowledge list includes a body or a model url")
print("   items", len(items))
PY

echo "ok"

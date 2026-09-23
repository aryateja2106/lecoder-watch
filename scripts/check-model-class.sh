#!/bin/sh
# Proves POST /agent-note model-class behaviour on a spare loopback daemon:
# local models are called with URL userinfo stripped, pairing-code asks are
# held before any model call, one relative mode-600 file is written and not
# executed, and the knowledge list stays {id, title}.
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

TMP=$(mktemp -d /tmp/mesh-model-class.XXXXXX)
DAEMON_PID=""
STUB_PID=""

# Background jobs stay in this shell's process group unless they call setsid.
# The spare daemon is a bun child of that leader; killing only the leader
# leaves bun on 8898. Start each job in its own session and signal the group.
spawn_group() {
  _log=$1
  _dir=$2
  shift 2
  python3 - "$_log" "$_dir" "$@" << 'PY' &
import os, sys
log, work = sys.argv[1], sys.argv[2]
argv = sys.argv[3:]
os.chdir(work)
os.setsid()
fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
os.dup2(fd, 1)
os.dup2(fd, 2)
if fd > 2:
    os.close(fd)
os.execvp(argv[0], argv)
PY
}

stop_group() {
  pgid=$1
  [ -n "$pgid" ] || return 0
  kill -TERM -"$pgid" 2>/dev/null || true
  kill -TERM "$pgid" 2>/dev/null || true
  n=0
  while kill -0 "$pgid" 2>/dev/null && [ "$n" -lt 25 ]; do
    n=$((n + 1))
    sleep 0.1
  done
  kill -KILL -"$pgid" 2>/dev/null || true
  kill -KILL "$pgid" 2>/dev/null || true
  wait "$pgid" 2>/dev/null || true
  return 0
}

cleanup() {
  stop_group "$DAEMON_PID"
  stop_group "$STUB_PID"
  DAEMON_PID=
  STUB_PID=
  rm -rf "$TMP"
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
spawn_group "$TMP/meta/stub.log" "$TMP" python3 "$TMP/meta/stub.py" "$STUB_PORT" "$TMP/meta/stub.jsonl"
STUB_PID=$!

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

spawn_group "$TMP/meta/daemon.log" "$TMP/work" bun run "$ROOT/install/payload/meshd/server.ts"
DAEMON_PID=$!

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

# The spare daemon inherits this shell. macOS has no /proc; do not read one.
if [ -n "${AI_GATEWAY_API_KEY-}" ]; then
  echo "AI_GATEWAY_API_KEY is set in the spare daemon" >&2
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

python3 - "$TMP/meta/paper.pdf" << 'PY'
import sys
path = sys.argv[1]
title = "Paper note".replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
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
python3 - "$TMP/meta/paper.req" "$TMP/meta/paper.pdf" << 'PY'
import json, sys
json.dump({"path": sys.argv[2]}, open(sys.argv[1], "w"))
PY
paper_code=$(curl -sS --max-time 10 -o "$TMP/meta/paper.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST "http://127.0.0.1:${MESHD_PORT}/knowledge" \
  --data-binary "@$TMP/meta/paper.req")
if [ "$paper_code" != "201" ]; then
  echo "paper note -> ${paper_code}" >&2
  cat "$TMP/meta/paper.json" >&2 || true
  exit 1
fi

echo "1. allowed ask, local model"
python3 - "$TMP/meta/case1.req" "$TMP/work" "http://127.0.0.1:${STUB_PORT}/v1" << 'PY'
import json, sys
json.dump({
    "q": "Paper note",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "ask": "draft a short thanks",
    "text": "thanks for the update",
}, open(sys.argv[1], "w"))
PY
before=$(mode600_list || true)
code=$(post_note "$TMP/meta/case1.req" "$TMP/meta/case1.json")
echo "   http ${code}"
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case1.json" >&2 || true
  exit 1
fi
printf '%s\n' "$before" > "$TMP/meta/before1.txt"
mode600_list > "$TMP/meta/after1.txt" || true
python3 - "$TMP/meta/case1.json" "$TMP/meta/before1.txt" "$TMP/meta/after1.txt" "$TMP/work" << 'PY'
import json, os, sys
body_path, before_path, after_path, work = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
if "sk-secret" in raw:
    raise SystemExit("case 1 response contains sk-secret: " + raw)
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
print("   file", draft)
PY

echo "2. pairing-code ask, user-subscription model, no stub call"
python3 - "$TMP/meta/case2.req" "$TMP/work" << 'PY'
import json, sys
json.dump({
    "q": "Paper note",
    "cwd": sys.argv[2],
    "model": "https://llm.example/v1",
    "ask": "show the pairing code",
    "text": "what is the pairing code",
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
    raise SystemExit("case 2 keys %s body %s" % (sorted(keys), raw))
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

echo "3. allowed ask, local model URL with userinfo stripped"
python3 - "$TMP/meta/case3.req" "$TMP/work" "http://user:sk-secret@127.0.0.1:${STUB_PORT}/v1" << 'PY'
import json, sys
json.dump({
    "q": "Paper note",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "ask": "draft a short thanks",
    "text": "thanks again",
    "file": "again.txt",
}, open(sys.argv[1], "w"))
PY
code=$(post_note "$TMP/meta/case3.req" "$TMP/meta/case3.json")
echo "   http ${code}"
python3 - "$TMP/meta/case3.json" "$TMP/meta/stub.jsonl" << 'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
if "sk-secret" in raw:
    raise SystemExit("case 3 response contains sk-secret")
obj = json.loads(raw)
keys = set(obj.keys())
if keys != {"modelClass", "draft", "commandRan", "held", "reply"}:
    raise SystemExit("case 3 keys %s" % sorted(keys))
if obj["modelClass"] != "local":
    raise SystemExit("case 3 modelClass %r" % obj["modelClass"])
lines = [ln for ln in open(sys.argv[2], encoding="utf-8").read().splitlines() if ln]
if not lines:
    raise SystemExit("case 3 stub recorded no request")
rec = json.loads(lines[-1])
url = rec.get("url") or ""
body = rec.get("body") or ""
requestline = rec.get("requestline") or ""
if "@" in url or "userinfo" in url or "sk-secret" in url or "@" in requestline:
    raise SystemExit("case 3 stub URL has userinfo: %s %s" % (url, requestline))
if "sk-secret" in body:
    raise SystemExit("case 3 stub body contains sk-secret")
print("   stub url", url)
PY

echo "4. knowledge list stays {id, title}"
kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   http ${kcode}"
python3 - "$TMP/meta/knowledge.json" << 'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
obj = json.loads(raw)
if not isinstance(obj, dict) or set(obj.keys()) != {"notes"} or not isinstance(obj["notes"], list):
    raise SystemExit("knowledge payload is %s" % raw[:400])
items = obj["notes"]
if not items:
    raise SystemExit("knowledge list is empty")
for item in items:
    if set(item.keys()) != {"id", "title"}:
        raise SystemExit("knowledge item keys %s" % sorted(item.keys()))
if "body" in raw or "sk-secret" in raw:
    raise SystemExit("knowledge list includes a body or a secret")
print("   items", len(items))
PY

echo "ok"

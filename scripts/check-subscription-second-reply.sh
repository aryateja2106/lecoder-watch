#!/bin/sh
# Proves two saved replies to a user-subscription model on a spare loopback
# daemon, then a later query that drafts only the second reply. The model
# host is llm.example, mapped to loopback for this check only. The class is
# user-subscription. An allowed ask calls the stub, writes one relative
# mode-600 file, does not execute it, and saves reply A. A later
# POST /agent-note with no id, a q that matches only A, and a new allowed
# local ask sends A, a blank line, and the ask. It calls the stub, writes
# one relative mode-600 file, does not execute it, and saves reply B. The
# stub URL has no userinfo. A later q that matches only B drafts B to one
# relative mode-600 file and does not execute it. That draft is not A and
# not the original source note. A q that matches A and B is 409 and writes
# nothing. A pairing-code ask on the second hop writes nothing and does not
# call the stub. Daemon state and held drafts do not keep the host or the
# key. The knowledge list stays {id, title}. Process environ is not read.
# This script does not open /proc. A missing /proc file does not abort it.
# On exit the daemon process group and the stub are killed so the spare
# port is free.
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

TMP=""
DAEMON_PID=""
STUB_PID=""
HOSTS_ADDED=0
HOSTS_MARK="# mesh-subscription-second-reply"

kill_group() {
  pgid=$1
  [ -n "$pgid" ] || return 0
  mine=$(ps -o pgid= -p $$ 2>/dev/null | tr -d '[:space:]' || true)
  if [ -z "$mine" ] || [ "$pgid" != "$mine" ]; then
    kill -TERM "-$pgid" 2>/dev/null || true
  else
    kids=$(ps -o pid= --ppid "$pgid" 2>/dev/null || true)
    for kid in $kids; do
      kill -TERM "$kid" 2>/dev/null || true
    done
    kill -TERM "$pgid" 2>/dev/null || true
  fi
  i=0
  while [ "$i" -lt 20 ]; do
    kill -0 "$pgid" 2>/dev/null || break
    i=$((i + 1))
    sleep 0.1
  done
  if kill -0 "$pgid" 2>/dev/null; then
    if [ -z "$mine" ] || [ "$pgid" != "$mine" ]; then
      kill -KILL "-$pgid" 2>/dev/null || true
    else
      kill -KILL "$pgid" 2>/dev/null || true
    fi
  fi
  wait "$pgid" 2>/dev/null || true
}

remove_hosts() {
  [ "$HOSTS_ADDED" = 1 ] || return 0
  python3 -c '
import sys
path = "/etc/hosts"
marker = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines(True)
kept = [ln for ln in lines if marker not in ln]
try:
    with open(path, "w", encoding="utf-8") as fh:
        fh.writelines(kept)
except PermissionError:
    sys.exit(13)
' "$HOSTS_MARK" 2>/dev/null || sudo -n python3 -c '
import sys
path = "/etc/hosts"
marker = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines(True)
kept = [ln for ln in lines if marker not in ln]
with open(path, "w", encoding="utf-8") as fh:
    fh.writelines(kept)
' "$HOSTS_MARK" 2>/dev/null || true
  HOSTS_ADDED=0
}

cleanup() {
  set +e
  dpid=$DAEMON_PID
  spid=$STUB_PID
  DAEMON_PID=""
  STUB_PID=""
  kill_group "$dpid"
  kill_group "$spid"
  remove_hosts
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

TMP=$(mktemp -d /tmp/mesh-subscription-second-reply.XXXXXX)
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

if [ -n "${AI_GATEWAY_API_KEY+x}" ]; then
  echo "AI_GATEWAY_API_KEY is set" >&2
  exit 1
fi

if curl -sf --max-time 1 "http://127.0.0.1:${MESHD_PORT}/health" >/dev/null 2>&1; then
  echo "port ${MESHD_PORT} already has a listener" >&2
  exit 1
fi

STUB_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
if [ "$STUB_PORT" = "8899" ] || [ "$STUB_PORT" = "8898" ]; then
  echo "stub picked a reserved port" >&2
  exit 1
fi

cat > "$TMP/meta/group.py" << 'PY'
import os, sys
try:
    os.setsid()
except OSError:
    pass
if len(sys.argv) < 2:
    sys.exit(2)
os.execvp(sys.argv[1], sys.argv[1:])
PY

cat > "$TMP/meta/stub.py" << 'PY'
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = sys.argv[2]
REPLY = sys.argv[3]

def reply_text():
    try:
        text = open(REPLY, encoding="utf-8").read()
    except OSError:
        text = ""
    return text if text else "Noted."

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
            "choices": [{"message": {"role": "assistant", "content": reply_text()}}],
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

printf '%s' 'The first margin stays beside the sentence.' > "$TMP/meta/reply.txt"
: > "$TMP/meta/stub.jsonl"
python3 "$TMP/meta/group.py" python3 "$TMP/meta/stub.py" "$STUB_PORT" "$TMP/meta/stub.jsonl" "$TMP/meta/reply.txt" >"$TMP/meta/stub.log" 2>&1 &
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

python3 -c '
import sys
path = "/etc/hosts"
marker = sys.argv[1]
line = "127.0.0.1 llm.example %s\n" % marker
with open(path, encoding="utf-8") as fh:
    text = fh.read()
if marker not in text:
    if text and not text.endswith("\n"):
        text += "\n"
    text += line
try:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
except PermissionError:
    sys.exit(13)
' "$HOSTS_MARK" || sudo -n python3 -c '
import sys
path = "/etc/hosts"
marker = sys.argv[1]
line = "127.0.0.1 llm.example %s\n" % marker
with open(path, encoding="utf-8") as fh:
    text = fh.read()
if marker not in text:
    if text and not text.endswith("\n"):
        text += "\n"
    text += line
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
' "$HOSTS_MARK" || {
  echo "cannot map llm.example to 127.0.0.1" >&2
  exit 1
}
HOSTS_ADDED=1

if ! python3 -c '
import socket, sys
port = int(sys.argv[1])
infos = socket.getaddrinfo("llm.example", port, type=socket.SOCK_STREAM)
addrs = sorted({item[4][0] for item in infos})
if addrs != ["127.0.0.1"]:
    sys.stderr.write("llm.example resolved to %s\n" % (addrs,))
    sys.exit(1)
' "$STUB_PORT"; then
  echo "llm.example did not resolve to 127.0.0.1" >&2
  exit 1
fi

: > "$TMP/meta/stub.jsonl"
if ! curl -sf --max-time 2 "http://llm.example:${STUB_PORT}/v1" >/dev/null; then
  echo "llm.example did not reach the stub" >&2
  exit 1
fi
python3 - "$TMP/meta/stub.jsonl" "$STUB_PORT" << 'PY'
import json, sys
path, port = sys.argv[1:]
lines = [ln for ln in open(path, encoding="utf-8").read().splitlines() if ln.strip()]
if len(lines) != 1:
    raise SystemExit("name probe did not hit the stub once")
rec = json.loads(lines[0])
host = rec.get("host") or ""
if host != "llm.example:%s" % port:
    raise SystemExit("name probe host %r" % host)
PY
# The name probe is not an agent-note call. Drop it so hit counts start clean.
: > "$TMP/meta/stub.jsonl"

python3 "$TMP/meta/group.py" sh -c 'cd "$1" && bun run "$2"' sh "$TMP/work" "$ROOT/install/payload/meshd/server.ts" >"$TMP/meta/daemon.log" 2>&1 &
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

daemon_pgid=$(ps -o pgid= -p "$DAEMON_PID" 2>/dev/null | tr -d '[:space:]' || true)
if [ -z "$daemon_pgid" ] || [ "$daemon_pgid" != "$DAEMON_PID" ]; then
  echo "spare daemon did not start in its own process group" >&2
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

file_list() {
  find "$1" -type f 2>/dev/null | sort
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
# log live under meta and are allowed to contain the host and the key.
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

ASK="thanks for the source"
NEXT_ASK="add a gloss"
MODEL_URL="http://llm.example:${STUB_PORT}/v1"
REPLY_A="The first margin stays beside the sentence."
REPLY_B="The second margin stays beside the sentence."
case "$MODEL_URL" in
  *127.0.0.1*|*localhost*)
    echo "model host must not be local for user-subscription" >&2
    exit 1
    ;;
esac

echo "1. allowed ask saves reply A"
python3 - "$TMP/meta/case1.req" "$TMP/work" "$MODEL_URL" "$ASK" << 'PY'
import json, sys
json.dump({
    "q": "Source note",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "held.txt",
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
python3 - "$TMP/meta/case1.json" "$TMP/meta/before1.txt" "$TMP/meta/after1.txt" "$TMP/work" "$TMP/meta/before.json" "$ASK" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$REPLY_A" << 'PY'
import json, os, sys
from urllib.parse import urlsplit
body_path, before_path, after_path, work, listed_path, ask, hits_before, hits_after, stub_path, reply = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
if "sk-secret" in raw or "llm.example" in raw:
    raise SystemExit("case 1 response contains the host or the key")
obj = json.loads(raw)
keys = set(obj.keys())
if keys != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("case 1 keys %s" % sorted(keys))
if obj["modelClass"] != "user-subscription":
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
if open(path, encoding="utf-8").read() != reply:
    raise SystemExit("case 1 draft is not reply A")
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("case 1 stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
rec = recs[int(hits_before)]
url = rec.get("url") or ""
parts = urlsplit(url)
if parts.username or parts.password or "@" in url or "@" in (rec.get("requestline") or ""):
    raise SystemExit("case 1 stub url has userinfo: %r" % url)
if not (rec.get("host") or "").startswith("llm.example:"):
    raise SystemExit("case 1 stub host %r" % rec.get("host"))
listed = json.loads(open(listed_path, encoding="utf-8").read())
ids = {item["id"] for item in listed["notes"]}
meta = os.path.dirname(body_path)
open(os.path.join(meta, "case1.draft"), "w", encoding="utf-8").write(path)
open(os.path.join(meta, "case1.ids"), "w", encoding="utf-8").write("\n".join(sorted(ids)))
print("   file", draft)
PY

echo "   state and the held draft omit the model host and the key"
DRAFT_A=$(cat "$TMP/meta/case1.draft")
scan_absent "$MESHD_STATE" "$DRAFT_A" \
  "needle:sk-secret" "needle:llm.example"
python3 - "$MESHD_STATE" "$TMP/meta/case1.ids" "$ASK" "$DRAFT_A" "$REPLY_A" "$TMP/meta/source.id" "$TMP/meta/source.body" << 'PY'
import json, os, sys
state, ids_path, ask, draft_path, reply, source_id_path, source_body_path = sys.argv[1:]
previous = {ln for ln in open(ids_path, encoding="utf-8").read().splitlines() if ln}
notes_dir = os.path.join(state, "knowledge")
found = []
source = None
for name in os.listdir(notes_dir):
    if not name.endswith(".json"):
        continue
    path = os.path.join(notes_dir, name)
    note = json.loads(open(path, encoding="utf-8").read())
    if note.get("id") in previous:
        source = note
        continue
    found.append(note)
if len(found) != 1:
    raise SystemExit("expected one new knowledge note, got %s" % len(found))
note = found[0]
if note.get("title") != ask:
    raise SystemExit("reply A title is %r" % note.get("title"))
if note.get("body") != reply:
    raise SystemExit("reply A body is not the model reply only")
if source is None:
    raise SystemExit("original source note is missing")
draft = open(draft_path, encoding="utf-8").read()
if draft != reply:
    raise SystemExit("draft file is not reply A")
if draft == source.get("body") or draft == source.get("title"):
    raise SystemExit("draft file is the original source note")
open(source_id_path, "w", encoding="utf-8").write(source["id"])
open(source_body_path, "w", encoding="utf-8").write(source.get("body") or "")
open(os.path.join(os.path.dirname(source_id_path), "reply.id"), "w", encoding="utf-8").write(note["id"])
print("   note", note["title"])
PY

echo "2. query matching only A sends A, a blank line, and the ask, and saves reply B"
printf '%s' "$REPLY_B" > "$TMP/meta/reply.txt"
python3 - "$TMP/meta/case2.req" "$TMP/work" "$MODEL_URL" "$NEXT_ASK" << 'PY'
import json, sys
body = {
    "q": "first margin",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "follow.txt",
    "ask": sys.argv[4],
}
if "id" in body:
    raise SystemExit("reply query included an id")
json.dump(body, open(sys.argv[1], "w"))
PY
before=$(mode600_list || true)
hits_before=$(hit_count)
code=$(post_note "$TMP/meta/case2.req" "$TMP/meta/case2.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case2.json" >&2 || true
  exit 1
fi
printf '%s\n' "$before" > "$TMP/meta/before2.txt"
mode600_list > "$TMP/meta/after2.txt" || true
python3 - "$TMP/meta/case2.json" "$TMP/meta/before2.txt" "$TMP/meta/after2.txt" "$TMP/work" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$MESHD_STATE" "$TMP/meta/reply.id" "$TMP/meta/source.id" "$TMP/meta/source.body" "$ASK" "$REPLY_A" "$NEXT_ASK" "$REPLY_B" << 'PY'
import json, os, sys
from urllib.parse import urlsplit
(body_path, before_path, after_path, work, hits_before, hits_after, stub_path,
 state, reply_id_path, source_id_path, source_body_path, ask, reply, next_ask, next_reply) = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
if "llm.example" in raw or "sk-secret" in raw:
    raise SystemExit("case 2 response contains the host or the key")
obj = json.loads(raw)
keys = set(obj.keys())
if keys != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("case 2 keys %s" % sorted(keys))
if obj["modelClass"] != "user-subscription":
    raise SystemExit("case 2 modelClass %r" % obj["modelClass"])
if obj["commandRan"] is not False:
    raise SystemExit("case 2 commandRan %r (file must not be executed)" % obj["commandRan"])
if obj["held"] is not False:
    raise SystemExit("case 2 held %r" % obj["held"])
draft = obj["draft"]
if not isinstance(draft, str) or not draft or os.path.isabs(draft) or draft.startswith("..") or "/" in draft:
    raise SystemExit("case 2 draft is not one relative file: %r" % draft)
before = {ln for ln in open(before_path, encoding="utf-8").read().splitlines() if ln}
after = {ln for ln in open(after_path, encoding="utf-8").read().splitlines() if ln}
new = sorted(after - before)
if new != [os.path.join(work, draft)]:
    raise SystemExit("case 2 expected one new mode-600 file, got %s" % new)
path = new[0]
mode = os.stat(path).st_mode & 0o777
if mode != 0o600 or mode & 0o111:
    raise SystemExit("case 2 mode %o" % mode)
text = open(path, encoding="utf-8").read()
source_body = open(source_body_path, encoding="utf-8").read()
source_id = open(source_id_path, encoding="utf-8").read().strip()
reply_id = open(reply_id_path, encoding="utf-8").read().strip()
first = json.loads(open(os.path.join(state, "knowledge", reply_id + ".json"), encoding="utf-8").read())
source = json.loads(open(os.path.join(state, "knowledge", source_id + ".json"), encoding="utf-8").read())
if first.get("title") != ask or first.get("body") != reply:
    raise SystemExit("saved reply A changed")
if text != next_reply:
    raise SystemExit("drafted file is not reply B")
if text == source.get("body") or text == source.get("title") or text == source_body or text == "Source note":
    raise SystemExit("drafted file is the original source note")
if text == first.get("body") or text == first.get("title"):
    raise SystemExit("drafted file is reply A")
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("case 2 stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
rec = recs[int(hits_before)]
url = rec.get("url") or ""
parts = urlsplit(url)
if parts.username or parts.password or "@" in url or "@" in (rec.get("requestline") or ""):
    raise SystemExit("case 2 stub url has userinfo: %r" % url)
if not (rec.get("host") or "").startswith("llm.example:"):
    raise SystemExit("case 2 stub host %r" % rec.get("host"))
sent = json.loads(rec.get("body") or "{}")
if sent.get("model") != "user-subscription":
    raise SystemExit("case 2 stub model is %r" % sent.get("model"))
messages = sent.get("messages")
if not isinstance(messages, list) or len(messages) != 1:
    raise SystemExit("case 2 stub messages are %r" % messages)
content = messages[0].get("content")
want = "%s\n\n%s\n\n%s" % (ask, reply, next_ask)
if content != want or not str(content).endswith("%s\n\n%s" % (reply, next_ask)):
    raise SystemExit("case 2 prompt is %r" % content)
if source_body and source_body in str(content):
    raise SystemExit("case 2 stub was given the original source note")
notes_dir = os.path.join(state, "knowledge")
found = []
for name in os.listdir(notes_dir):
    if not name.endswith(".json"):
        continue
    note = json.loads(open(os.path.join(notes_dir, name), encoding="utf-8").read())
    if note.get("id") in (source_id, reply_id):
        continue
    found.append(note)
if len(found) != 1:
    raise SystemExit("expected one new reply note, got %s" % len(found))
note = found[0]
if note.get("id") in (source_id, reply_id):
    raise SystemExit("new note is an existing note")
if note.get("title") != next_ask:
    raise SystemExit("reply B title is %r" % note.get("title"))
if note.get("body") != next_reply:
    raise SystemExit("reply B body is not the new model reply only")
open(os.path.join(os.path.dirname(body_path), "case2.draft"), "w", encoding="utf-8").write(path)
open(os.path.join(os.path.dirname(body_path), "next.id"), "w", encoding="utf-8").write(note["id"])
print("   file", draft)
PY
DRAFT_B=$(cat "$TMP/meta/case2.draft")
scan_absent "$MESHD_STATE" "$DRAFT_A" "$DRAFT_B" \
  "needle:llm.example" "needle:sk-secret"

echo "3. query matching only B drafts B"
python3 - "$TMP/meta/case3.req" "$TMP/work" "$MODEL_URL" << 'PY'
import json, sys
body = {
    "q": "second margin",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "second.txt",
}
if "id" in body or "ask" in body:
    raise SystemExit("second reply query included an id or an ask")
json.dump(body, open(sys.argv[1], "w"))
PY
before=$(mode600_list || true)
hits_before=$(hit_count)
code=$(post_note "$TMP/meta/case3.req" "$TMP/meta/case3.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case3.json" >&2 || true
  exit 1
fi
printf '%s\n' "$before" > "$TMP/meta/before3.txt"
mode600_list > "$TMP/meta/after3.txt" || true
python3 - "$TMP/meta/case3.json" "$TMP/meta/before3.txt" "$TMP/meta/after3.txt" "$TMP/work" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$MESHD_STATE" "$TMP/meta/next.id" "$TMP/meta/reply.id" "$TMP/meta/source.id" "$TMP/meta/source.body" "$REPLY_A" "$REPLY_B" "$NEXT_ASK" << 'PY'
import json, os, sys
from urllib.parse import urlsplit
(body_path, before_path, after_path, work, hits_before, hits_after, stub_path,
 state, next_id_path, reply_id_path, source_id_path, source_body_path, reply_a, reply_b, next_ask) = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
if "llm.example" in raw or "sk-secret" in raw:
    raise SystemExit("case 3 response contains the host or the key")
obj = json.loads(raw)
keys = set(obj.keys())
if keys != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("case 3 keys %s" % sorted(keys))
if obj["modelClass"] != "user-subscription":
    raise SystemExit("case 3 modelClass %r" % obj["modelClass"])
if obj["commandRan"] is not False:
    raise SystemExit("case 3 commandRan %r (file must not be executed)" % obj["commandRan"])
if obj["held"] is not False:
    raise SystemExit("case 3 held %r" % obj["held"])
draft = obj["draft"]
if not isinstance(draft, str) or not draft or os.path.isabs(draft) or draft.startswith("..") or "/" in draft:
    raise SystemExit("case 3 draft is not one relative file: %r" % draft)
before = {ln for ln in open(before_path, encoding="utf-8").read().splitlines() if ln}
after = {ln for ln in open(after_path, encoding="utf-8").read().splitlines() if ln}
new = sorted(after - before)
if new != [os.path.join(work, draft)]:
    raise SystemExit("case 3 expected one new mode-600 file, got %s" % new)
path = new[0]
mode = os.stat(path).st_mode & 0o777
if mode != 0o600 or mode & 0o111:
    raise SystemExit("case 3 mode %o" % mode)
text = open(path, encoding="utf-8").read()
source_body = open(source_body_path, encoding="utf-8").read()
source_id = open(source_id_path, encoding="utf-8").read().strip()
reply_id = open(reply_id_path, encoding="utf-8").read().strip()
next_id = open(next_id_path, encoding="utf-8").read().strip()
note_b = json.loads(open(os.path.join(state, "knowledge", next_id + ".json"), encoding="utf-8").read())
note_a = json.loads(open(os.path.join(state, "knowledge", reply_id + ".json"), encoding="utf-8").read())
source = json.loads(open(os.path.join(state, "knowledge", source_id + ".json"), encoding="utf-8").read())
if note_b.get("title") != next_ask or note_b.get("body") != reply_b:
    raise SystemExit("saved reply B changed")
if note_a.get("body") != reply_a:
    raise SystemExit("saved reply A changed")
if text != reply_b or text != note_b.get("body"):
    raise SystemExit("drafted file is not reply B")
if text == reply_a or text == note_a.get("body") or text == note_a.get("title"):
    raise SystemExit("drafted file is reply A")
if text == source.get("body") or text == source.get("title") or text == source_body or text == "Source note":
    raise SystemExit("drafted file is the original source note")
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("case 3 stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
rec = recs[int(hits_before)]
url = rec.get("url") or ""
parts = urlsplit(url)
if parts.username or parts.password or "@" in url or "@" in (rec.get("requestline") or ""):
    raise SystemExit("case 3 stub url has userinfo: %r" % url)
sent = json.loads(rec.get("body") or "{}")
messages = sent.get("messages")
if not isinstance(messages, list) or len(messages) != 1:
    raise SystemExit("case 3 stub messages are %r" % messages)
content = messages[0].get("content") or ""
if reply_b not in content:
    raise SystemExit("case 3 prompt did not include reply B")
if reply_a in content:
    raise SystemExit("case 3 prompt included reply A")
if source_body and source_body in content:
    raise SystemExit("case 3 prompt included the original source note")
names = [name for name in os.listdir(os.path.join(state, "knowledge")) if name.endswith(".json")]
if len(names) != 3:
    raise SystemExit("case 3 added a note: %s" % names)
open(os.path.join(os.path.dirname(body_path), "case3.draft"), "w", encoding="utf-8").write(path)
print("   file", draft)
PY
DRAFT_C=$(cat "$TMP/meta/case3.draft")
scan_absent "$MESHD_STATE" "$DRAFT_A" "$DRAFT_B" "$DRAFT_C" \
  "needle:llm.example" "needle:sk-secret"

echo "4. query matching A and B is 409"
file_list "$TMP/work" > "$TMP/meta/work-before-both.txt"
file_list "$MESHD_STATE" > "$TMP/meta/state-before-both.txt"
hits_before=$(hit_count)
python3 - "$TMP/meta/case4.req" "$TMP/work" "$MODEL_URL" << 'PY'
import json, sys
body = {
    "q": "margin stays beside",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "both.txt",
}
if "id" in body:
    raise SystemExit("shared query included an id")
json.dump(body, open(sys.argv[1], "w"))
PY
code=$(post_note "$TMP/meta/case4.req" "$TMP/meta/case4.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "409" ]; then
  cat "$TMP/meta/case4.json" >&2 || true
  exit 1
fi
file_list "$TMP/work" > "$TMP/meta/work-after-both.txt"
file_list "$MESHD_STATE" > "$TMP/meta/state-after-both.txt"
python3 - "$TMP/meta/case4.json" "$TMP/meta/work-before-both.txt" "$TMP/meta/work-after-both.txt" "$TMP/meta/state-before-both.txt" "$TMP/meta/state-after-both.txt" "$TMP/work/both.txt" "$hits_before" "$hits_after" << 'PY'
import json, os, sys
body_path, work_before, work_after, state_before, state_after, both, hits_before, hits_after = sys.argv[1:]
obj = json.loads(open(body_path, encoding="utf-8").read())
if obj.get("error") != "more than one note":
    raise SystemExit("case 4 body %r" % obj)
if "draft" in obj:
    raise SystemExit("case 4 wrote a draft field")

def lines(path):
    return [ln for ln in open(path, encoding="utf-8").read().splitlines() if ln]

if lines(work_before) != lines(work_after):
    raise SystemExit("case 4 wrote a work file")
if lines(state_before) != lines(state_after):
    raise SystemExit("case 4 wrote a state file")
if os.path.exists(both):
    raise SystemExit("case 4 wrote both.txt")
if int(hits_after) != int(hits_before):
    raise SystemExit("case 4 called the stub")
print("   wrote nothing")
PY

echo "5. pairing-code ask on the second hop writes nothing"
file_list "$TMP/work" > "$TMP/meta/work-before-pair.txt"
file_list "$MESHD_STATE" > "$TMP/meta/state-before-pair.txt"
hits_before=$(hit_count)
python3 - "$TMP/meta/case5.req" "$TMP/work" "$MODEL_URL" << 'PY'
import json, sys
body = {
    "q": "first margin",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "pairing.txt",
    "ask": "send a pairing code",
}
if "id" in body:
    raise SystemExit("pairing ask included an id")
json.dump(body, open(sys.argv[1], "w"))
PY
code=$(post_note "$TMP/meta/case5.req" "$TMP/meta/case5.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case5.json" >&2 || true
  exit 1
fi
file_list "$TMP/work" > "$TMP/meta/work-after-pair.txt"
file_list "$MESHD_STATE" > "$TMP/meta/state-after-pair.txt"
python3 - "$TMP/meta/case5.json" "$TMP/meta/work-before-pair.txt" "$TMP/meta/work-after-pair.txt" "$TMP/meta/state-before-pair.txt" "$TMP/meta/state-after-pair.txt" "$TMP/work/pairing.txt" "$hits_before" "$hits_after" << 'PY'
import json, os, sys
body_path, work_before, work_after, state_before, state_after, pairing, hits_before, hits_after = sys.argv[1:]
obj = json.loads(open(body_path, encoding="utf-8").read())
if obj.get("modelClass") != "user-subscription" or obj.get("draft") is not None or obj.get("commandRan") is not False or obj.get("held") is not True:
    raise SystemExit("case 5 was not held: %r" % obj)

def lines(path):
    return [ln for ln in open(path, encoding="utf-8").read().splitlines() if ln]

if lines(work_before) != lines(work_after):
    raise SystemExit("case 5 wrote a work file")
if lines(state_before) != lines(state_after):
    raise SystemExit("case 5 added a note")
if os.path.exists(pairing):
    raise SystemExit("case 5 wrote pairing.txt")
if int(hits_after) != int(hits_before):
    raise SystemExit("case 5 called the stub")
print("   wrote nothing")
PY

echo "6. knowledge list stays {id, title}"
kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   http ${kcode}"
python3 - "$TMP/meta/knowledge.json" "$ASK" "$NEXT_ASK" "$REPLY_A" "$REPLY_B" << 'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
ask, next_ask, reply_a, reply_b = sys.argv[2:]
obj = json.loads(raw)
if not isinstance(obj, dict) or set(obj.keys()) != {"notes"} or not isinstance(obj["notes"], list):
    raise SystemExit("knowledge payload keys are wrong")
items = obj["notes"]
if len(items) != 3:
    raise SystemExit("knowledge list has %s notes" % len(items))
titles = []
for item in items:
    if set(item.keys()) != {"id", "title"}:
        raise SystemExit("knowledge item keys %s" % sorted(item.keys()))
    titles.append(item["title"])
if titles.count(ask) != 1 or titles.count(next_ask) != 1 or titles.count("Source note") != 1:
    raise SystemExit("note titles %s" % titles)
if "body" in raw or reply_a in raw or reply_b in raw or "sk-secret" in raw or "llm.example" in raw or "Local page" in raw:
    raise SystemExit("knowledge list includes a body or a model url")
print("   items", len(items))
PY
scan_absent "$MESHD_STATE" "$DRAFT_A" "$DRAFT_B" "$DRAFT_C" \
  "needle:llm.example" "needle:sk-secret"

echo "ok"

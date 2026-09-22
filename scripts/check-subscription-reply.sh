#!/bin/sh
# Proves an allowed ask to a user-subscription model on a spare loopback
# daemon, then a later query that drafts only that saved reply. The model
# host is llm.example, mapped to loopback for this check only. The class is
# user-subscription, the stub is called, one relative mode-600 file is
# written and not executed, and one knowledge note stores the ask as its
# title and the model reply as its body. A later POST /agent-note with no
# id and a q that matches only that reply drafts the reply to one relative
# mode-600 file and does not execute it. That draft is not the original
# source note. A q that matches the original note and the saved reply is
# 409 and writes nothing. Daemon state and held drafts do not keep the
# host or the key. The knowledge list stays {id, title}. Process environ
# is not read. This script does not open /proc. On exit the daemon process
# group and the stub are killed so the spare port is free.
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
HOSTS_MARK="# mesh-subscription-reply"

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

TMP=$(mktemp -d /tmp/mesh-subscription-reply.XXXXXX)
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
python3 "$TMP/meta/group.py" python3 "$TMP/meta/stub.py" "$STUB_PORT" "$TMP/meta/stub.jsonl" >"$TMP/meta/stub.log" 2>&1 &
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
MODEL_URL="http://llm.example:${STUB_PORT}/v1"
REPLY_ONLY="Noted."

echo "1. allowed ask, user-subscription model"
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
python3 - "$TMP/meta/case1.json" "$TMP/meta/before1.txt" "$TMP/meta/after1.txt" "$TMP/work" "$TMP/meta/before.json" "$ASK" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$REPLY_ONLY" << 'PY'
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
    raise SystemExit("case 1 draft is not the model reply only")
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

echo "2. state and the held draft omit the model host and the key"
DRAFT_FILE=$(cat "$TMP/meta/case1.draft")
scan_absent "$MESHD_STATE" "$DRAFT_FILE" \
  "needle:sk-secret" "needle:llm.example"
python3 - "$MESHD_STATE" "$TMP/meta/case1.ids" "$ASK" "$DRAFT_FILE" "$REPLY_ONLY" "$TMP/meta/source.id" "$TMP/meta/source.body" << 'PY'
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
    raise SystemExit("note title is %r" % note.get("title"))
if note.get("body") != reply:
    raise SystemExit("note body is not the model reply only")
if source is None:
    raise SystemExit("original source note is missing")
draft = open(draft_path, encoding="utf-8").read()
if draft != reply:
    raise SystemExit("draft file is not the model reply only")
if draft == source.get("body") or draft == source.get("title"):
    raise SystemExit("draft file is the original source note")
open(source_id_path, "w", encoding="utf-8").write(source["id"])
open(source_body_path, "w", encoding="utf-8").write(source.get("body") or "")
open(os.path.join(os.path.dirname(source_id_path), "reply.id"), "w", encoding="utf-8").write(note["id"])
print("   note", note["title"])
PY

echo "3. query matching only the saved reply drafts that reply"
python3 - "$TMP/meta/case2.req" "$TMP/work" "$MODEL_URL" << 'PY'
import json, sys
body = {
    "q": "Noted",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "reply.txt",
}
if "id" in body or "ask" in body:
    raise SystemExit("reply query included an id or an ask")
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
python3 - "$TMP/meta/case2.json" "$TMP/meta/before2.txt" "$TMP/meta/after2.txt" "$TMP/work" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$MESHD_STATE" "$TMP/meta/reply.id" "$TMP/meta/source.body" "$ASK" "$REPLY_ONLY" << 'PY'
import json, os, sys
body_path, before_path, after_path, work, hits_before, hits_after, stub_path, state, reply_id_path, source_body_path, ask, reply = sys.argv[1:]
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
reply_id = open(reply_id_path, encoding="utf-8").read().strip()
note = json.loads(open(os.path.join(state, "knowledge", reply_id + ".json"), encoding="utf-8").read())
if note.get("title") != ask or note.get("body") != reply:
    raise SystemExit("saved reply note changed")
if text != note.get("body") or text != reply:
    raise SystemExit("drafted file is not the saved reply")
if text == source_body or source_body in text or text == "Source note":
    raise SystemExit("drafted file is the original source note")
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("case 2 stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
rec = recs[int(hits_before)]
sent = rec.get("body") or ""
if reply not in sent or ask not in sent:
    raise SystemExit("case 2 stub was not given the saved reply")
if source_body and source_body in sent:
    raise SystemExit("case 2 stub was given the original source note")
if not (rec.get("host") or "").startswith("llm.example:"):
    raise SystemExit("case 2 stub host %r" % rec.get("host"))
open(os.path.join(os.path.dirname(body_path), "case2.draft"), "w", encoding="utf-8").write(path)
print("   file", draft)
PY
DRAFT2=$(cat "$TMP/meta/case2.draft")
scan_absent "$MESHD_STATE" "$DRAFT_FILE" "$DRAFT2" \
  "needle:llm.example" "needle:sk-secret"

echo "4. query matching the original note and the saved reply is 409"
file_list "$TMP/work" > "$TMP/meta/work-before.txt"
file_list "$MESHD_STATE" > "$TMP/meta/state-before.txt"
hits_before=$(hit_count)
python3 - "$TMP/meta/case3.req" "$TMP/work" "$MODEL_URL" << 'PY'
import json, sys
body = {
    "q": "source",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "both.txt",
}
if "id" in body:
    raise SystemExit("shared query included an id")
json.dump(body, open(sys.argv[1], "w"))
PY
code=$(post_note "$TMP/meta/case3.req" "$TMP/meta/case3.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "409" ]; then
  cat "$TMP/meta/case3.json" >&2 || true
  exit 1
fi
file_list "$TMP/work" > "$TMP/meta/work-after.txt"
file_list "$MESHD_STATE" > "$TMP/meta/state-after.txt"
python3 - "$TMP/meta/case3.json" "$TMP/meta/work-before.txt" "$TMP/meta/work-after.txt" "$TMP/meta/state-before.txt" "$TMP/meta/state-after.txt" "$TMP/work/both.txt" "$hits_before" "$hits_after" << 'PY'
import json, os, sys
body_path, work_before, work_after, state_before, state_after, both, hits_before, hits_after = sys.argv[1:]
obj = json.loads(open(body_path, encoding="utf-8").read())
if obj.get("error") != "more than one note":
    raise SystemExit("case 3 body %r" % obj)
if "draft" in obj:
    raise SystemExit("case 3 wrote a draft field")

def lines(path):
    return [ln for ln in open(path, encoding="utf-8").read().splitlines() if ln]

if lines(work_before) != lines(work_after):
    raise SystemExit("case 3 wrote a work file")
if lines(state_before) != lines(state_after):
    raise SystemExit("case 3 wrote a state file")
if os.path.exists(both):
    raise SystemExit("case 3 wrote both.txt")
if int(hits_after) != int(hits_before):
    raise SystemExit("case 3 called the stub")
print("   wrote nothing")
PY

echo "5. knowledge list stays {id, title}"
kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   http ${kcode}"
python3 - "$TMP/meta/knowledge.json" "$ASK" "$REPLY_ONLY" << 'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
ask, reply = sys.argv[2:]
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
if titles.count(ask) != 1 or titles.count("Source note") != 1:
    raise SystemExit("note titles %s" % titles)
if "body" in raw or reply in raw or "sk-secret" in raw or "llm.example" in raw or "Local page" in raw:
    raise SystemExit("knowledge list includes a body or a model url")
print("   items", len(items))
PY

echo "ok"

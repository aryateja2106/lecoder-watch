#!/bin/sh
# Proves a shell command on a user-subscription reply runs only when confirm
# is true. The model host is llm.example, mapped to loopback for this check
# only. An allowed ask with confirm omitted or false returns modelClass
# user-subscription, calls the stub, writes one relative mode-600 file, does
# not execute that file, and does not run the command. The same ask with
# confirm true runs the command and still returns modelClass user-subscription.
# A pairing-code ask with confirm true writes nothing, does not call the stub,
# and does not run the command. The knowledge list stays {id, title}. Daemon
# state and held drafts do not keep the host or the key. The stub URL has no
# userinfo. This script does not open /proc. A missing /proc file does not
# abort it. On exit the daemon process group and the stub are killed so the
# spare port is free.
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
HOSTS_MARK="# mesh-subscription-reply-confirm"

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

TMP=$(mktemp -d /tmp/mesh-subscription-reply-confirm.XXXXXX)
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

printf '%s' 'The margin stays beside the sentence.' > "$TMP/meta/reply.txt"
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

ASK="thanks for the source"
MODEL_URL="http://llm.example:${STUB_PORT}/v1"
REPLY="The margin stays beside the sentence."
COMMAND="touch ${TMP}/work/held-ran"
case "$MODEL_URL" in
  *127.0.0.1*|*localhost*)
    echo "model host must not be local for user-subscription" >&2
    exit 1
    ;;
esac

echo "1. allowed ask with confirm omitted does not run the command"
python3 - "$TMP/meta/case1.req" "$TMP/work" "$MODEL_URL" "$ASK" "$COMMAND" << 'PY'
import json, sys
body = {
    "q": "Source note",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "held.txt",
    "ask": sys.argv[4],
    "command": sys.argv[5],
}
if "confirm" in body:
    raise SystemExit("confirm was set on the omitted ask")
json.dump(body, open(sys.argv[1], "w"))
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
if [ -e "$TMP/work/held-ran" ]; then
  echo "confirm ran without being set" >&2
  exit 1
fi
printf '%s\n' "$before" > "$TMP/meta/before1.txt"
mode600_list > "$TMP/meta/after1.txt" || true
python3 - "$TMP/meta/case1.json" "$TMP/meta/before1.txt" "$TMP/meta/after1.txt" "$TMP/work" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$REPLY" "$TMP/meta/case1.draft" << 'PY'
import json, os, sys
from urllib.parse import urlsplit
body_path, before_path, after_path, work, hits_before, hits_after, stub_path, reply, draft_out = sys.argv[1:]
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
    raise SystemExit("confirm ran without being set")
if obj["held"] is not True:
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
    raise SystemExit("case 1 draft is not the stub reply")
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
open(draft_out, "w", encoding="utf-8").write(path)
print("   file", draft)
PY
DRAFT1=$(cat "$TMP/meta/case1.draft")
echo "   state and the held draft omit the model host and the key"
scan_absent "$MESHD_STATE" "$DRAFT1" \
  "needle:sk-secret" "needle:llm.example"

echo "2. allowed ask with confirm false does not run the command"
python3 - "$TMP/meta/case2.req" "$TMP/work" "$MODEL_URL" "$ASK" "$COMMAND" << 'PY'
import json, sys
body = {
    "q": "Source note",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "held-false.txt",
    "ask": sys.argv[4],
    "command": sys.argv[5],
    "confirm": False,
}
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
if [ -e "$TMP/work/held-ran" ]; then
  echo "confirm ran without being set" >&2
  exit 1
fi
printf '%s\n' "$before" > "$TMP/meta/before2.txt"
mode600_list > "$TMP/meta/after2.txt" || true
python3 - "$TMP/meta/case2.json" "$TMP/meta/before2.txt" "$TMP/meta/after2.txt" "$TMP/work" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$REPLY" "$TMP/meta/case2.draft" << 'PY'
import json, os, sys
from urllib.parse import urlsplit
body_path, before_path, after_path, work, hits_before, hits_after, stub_path, reply, draft_out = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
if "sk-secret" in raw or "llm.example" in raw:
    raise SystemExit("case 2 response contains the host or the key")
obj = json.loads(raw)
keys = set(obj.keys())
if keys != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("case 2 keys %s" % sorted(keys))
if obj["modelClass"] != "user-subscription":
    raise SystemExit("case 2 modelClass %r" % obj["modelClass"])
if obj["commandRan"] is not False:
    raise SystemExit("confirm false ran the command")
if obj["held"] is not True:
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
if open(path, encoding="utf-8").read() != reply:
    raise SystemExit("case 2 draft is not the stub reply")
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("case 2 stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
rec = recs[int(hits_before)]
url = rec.get("url") or ""
parts = urlsplit(url)
if parts.username or parts.password or "@" in url or "@" in (rec.get("requestline") or ""):
    raise SystemExit("case 2 stub url has userinfo: %r" % url)
open(draft_out, "w", encoding="utf-8").write(path)
print("   file", draft)
PY
DRAFT2=$(cat "$TMP/meta/case2.draft")
scan_absent "$MESHD_STATE" "$DRAFT1" "$DRAFT2" \
  "needle:sk-secret" "needle:llm.example"

echo "3. the same allowed ask with confirm true runs the command"
python3 - "$TMP/meta/case3.req" "$TMP/work" "$MODEL_URL" "margin-token-only" "$COMMAND" << 'PY'
import json, sys
body = {
    "q": "Source note",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "held-true.txt",
    "ask": sys.argv[4],
    "command": sys.argv[5],
    "confirm": True,
}
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
if [ ! -e "$TMP/work/held-ran" ]; then
  echo "held command did not run when confirm is true" >&2
  exit 1
fi
printf '%s\n' "$before" > "$TMP/meta/before3.txt"
mode600_list > "$TMP/meta/after3.txt" || true
python3 - "$TMP/meta/case3.json" "$TMP/meta/before3.txt" "$TMP/meta/after3.txt" "$TMP/work" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$REPLY" "$TMP/meta/case3.draft" << 'PY'
import json, os, sys
from urllib.parse import urlsplit
body_path, before_path, after_path, work, hits_before, hits_after, stub_path, reply, draft_out = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
if "sk-secret" in raw or "llm.example" in raw:
    raise SystemExit("case 3 response contains the host or the key")
obj = json.loads(raw)
keys = set(obj.keys())
if keys != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("case 3 keys %s" % sorted(keys))
if obj["modelClass"] != "user-subscription":
    raise SystemExit("case 3 modelClass %r" % obj["modelClass"])
if obj["commandRan"] is not True:
    raise SystemExit("held command did not run when confirm is true")
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
if open(path, encoding="utf-8").read() != reply:
    raise SystemExit("case 3 draft is not the stub reply")
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("case 3 stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
rec = recs[int(hits_before)]
url = rec.get("url") or ""
parts = urlsplit(url)
if parts.username or parts.password or "@" in url or "@" in (rec.get("requestline") or ""):
    raise SystemExit("case 3 stub url has userinfo: %r" % url)
open(draft_out, "w", encoding="utf-8").write(path)
print("   file", draft)
PY
DRAFT3=$(cat "$TMP/meta/case3.draft")
scan_absent "$MESHD_STATE" "$DRAFT1" "$DRAFT2" "$DRAFT3" \
  "needle:sk-secret" "needle:llm.example"

echo "6. later query of the saved reply does not run a second command"
python3 - "$TMP/meta/case6.req" "$TMP/work" "$MODEL_URL" << 'PY'
import json, sys
body = {
    "q": "margin-token-only",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "held-later.txt",
    "command": "touch " + sys.argv[2] + "/held-again",
}
json.dump(body, open(sys.argv[1], "w"))
PY
before=$(mode600_list || true)
hits_before=$(hit_count)
code=$(post_note "$TMP/meta/case6.req" "$TMP/meta/case6.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case6.json" >&2 || true
  exit 1
fi
if [ -e "$TMP/work/held-again" ]; then
  echo "later query ran the command without confirm" >&2
  exit 1
fi
printf '%s\n' "$before" > "$TMP/meta/before6.txt"
mode600_list > "$TMP/meta/after6.txt" || true
python3 - "$TMP/meta/case6.json" "$TMP/meta/before6.txt" "$TMP/meta/after6.txt" "$TMP/work" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$REPLY" "$TMP/meta/case6.draft" << 'PY'
import json, os, sys
from urllib.parse import urlsplit
body_path, before_path, after_path, work, hits_before, hits_after, stub_path, reply, draft_out = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
if "sk-secret" in raw or "llm.example" in raw:
    raise SystemExit("case 6 response contains the host or the key")
obj = json.loads(raw)
if set(obj.keys()) != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("case 6 keys %s" % sorted(obj.keys()))
if obj["modelClass"] != "user-subscription" or obj["commandRan"] is not False or obj["held"] is not True:
    raise SystemExit("case 6 ran or was not held: %r" % obj)
draft = obj["draft"]
if not isinstance(draft, str) or not draft or os.path.isabs(draft) or draft.startswith("..") or "/" in draft:
    raise SystemExit("case 6 draft is not one relative file: %r" % draft)
before = {ln for ln in open(before_path, encoding="utf-8").read().splitlines() if ln}
after = {ln for ln in open(after_path, encoding="utf-8").read().splitlines() if ln}
new = sorted(after - before)
if new != [os.path.join(work, draft)]:
    raise SystemExit("case 6 expected one new mode-600 file, got %s" % new)
path = new[0]
mode = os.stat(path).st_mode & 0o777
if mode != 0o600 or mode & 0o111:
    raise SystemExit("case 6 mode %o" % mode)
if open(path, encoding="utf-8").read() != reply:
    raise SystemExit("case 6 draft is not the stub reply")
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("case 6 stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
rec = recs[int(hits_before)]
url = rec.get("url") or ""
parts = urlsplit(url)
if parts.username or parts.password or "@" in url:
    raise SystemExit("case 6 stub url has userinfo")
if "The margin stays beside the sentence." not in (rec.get("body") or ""):
    raise SystemExit("case 6 did not send the saved reply")
open(draft_out, "w", encoding="utf-8").write(path)
print("   file", draft)
PY
DRAFT6=$(cat "$TMP/meta/case6.draft")
scan_absent "$MESHD_STATE" "$DRAFT6" "needle:sk-secret" "needle:llm.example"

echo "7. the same later query with confirm true runs the second command"
python3 - "$TMP/meta/case7.req" "$TMP/work" "$MODEL_URL" << 'PY'
import json, sys
body = {
    "q": "margin-token-only",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "held-later-true.txt",
    "command": "touch " + sys.argv[2] + "/held-again",
    "confirm": True,
}
json.dump(body, open(sys.argv[1], "w"))
PY
before=$(mode600_list || true)
hits_before=$(hit_count)
code=$(post_note "$TMP/meta/case7.req" "$TMP/meta/case7.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case7.json" >&2 || true
  exit 1
fi
if [ ! -e "$TMP/work/held-again" ]; then
  echo "later query did not run the command when confirm is true" >&2
  exit 1
fi
printf '%s\n' "$before" > "$TMP/meta/before7.txt"
mode600_list > "$TMP/meta/after7.txt" || true
python3 - "$TMP/meta/case7.json" "$TMP/meta/before7.txt" "$TMP/meta/after7.txt" "$TMP/work" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$REPLY" "$TMP/meta/case7.draft" << 'PY'
import json, os, sys
from urllib.parse import urlsplit
body_path, before_path, after_path, work, hits_before, hits_after, stub_path, reply, draft_out = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
if "sk-secret" in raw or "llm.example" in raw:
    raise SystemExit("case 7 response contains the host or the key")
obj = json.loads(raw)
if set(obj.keys()) != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("case 7 keys %s" % sorted(obj.keys()))
if obj["modelClass"] != "user-subscription" or obj["commandRan"] is not True or obj["held"] is not False:
    raise SystemExit("case 7 did not run: %r" % obj)
draft = obj["draft"]
if not isinstance(draft, str) or not draft or os.path.isabs(draft) or "/" in draft:
    raise SystemExit("case 7 draft is not one relative file: %r" % draft)
before = {ln for ln in open(before_path, encoding="utf-8").read().splitlines() if ln}
after = {ln for ln in open(after_path, encoding="utf-8").read().splitlines() if ln}
new = sorted(after - before)
if new != [os.path.join(work, draft)]:
    raise SystemExit("case 7 expected one new mode-600 file, got %s" % new)
path = new[0]
mode = os.stat(path).st_mode & 0o777
if mode != 0o600 or mode & 0o111:
    raise SystemExit("case 7 mode %o" % mode)
if open(path, encoding="utf-8").read() != reply:
    raise SystemExit("case 7 draft is not the stub reply")
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("case 7 stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
rec = recs[int(hits_before)]
url = rec.get("url") or ""
parts = urlsplit(url)
if parts.username or parts.password or "@" in url:
    raise SystemExit("case 7 stub url has userinfo")
open(draft_out, "w", encoding="utf-8").write(path)
print("   file", draft)
PY
DRAFT7=$(cat "$TMP/meta/case7.draft")
scan_absent "$MESHD_STATE" "$DRAFT6" "$DRAFT7" "needle:sk-secret" "needle:llm.example"

echo "4. pairing-code ask with confirm true writes nothing"
file_list "$TMP/work" > "$TMP/meta/work-before-pair.txt"
file_list "$MESHD_STATE" > "$TMP/meta/state-before-pair.txt"
hits_before=$(hit_count)
python3 - "$TMP/meta/case4.req" "$TMP/work" "$MODEL_URL" << 'PY'
import json, sys
body = {
    "q": "Source note",
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "pairing.txt",
    "ask": "send a pairing code",
    "command": "touch " + sys.argv[2] + "/pairing-ran",
    "confirm": True,
}
json.dump(body, open(sys.argv[1], "w"))
PY
code=$(post_note "$TMP/meta/case4.req" "$TMP/meta/case4.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case4.json" >&2 || true
  exit 1
fi
file_list "$TMP/work" > "$TMP/meta/work-after-pair.txt"
file_list "$MESHD_STATE" > "$TMP/meta/state-after-pair.txt"
python3 - "$TMP/meta/case4.json" "$TMP/meta/work-before-pair.txt" "$TMP/meta/work-after-pair.txt" "$TMP/meta/state-before-pair.txt" "$TMP/meta/state-after-pair.txt" "$TMP/work/pairing.txt" "$TMP/work/pairing-ran" "$hits_before" "$hits_after" << 'PY'
import json, os, sys
body_path, work_before, work_after, state_before, state_after, pairing, ran, hits_before, hits_after = sys.argv[1:]
obj = json.loads(open(body_path, encoding="utf-8").read())
if obj.get("modelClass") != "user-subscription" or obj.get("draft") is not None or obj.get("commandRan") is not False or obj.get("held") is not True:
    raise SystemExit("case 4 was not held: %r" % obj)

def lines(path):
    return [ln for ln in open(path, encoding="utf-8").read().splitlines() if ln]

if lines(work_before) != lines(work_after):
    raise SystemExit("case 4 wrote a work file")
if lines(state_before) != lines(state_after):
    raise SystemExit("case 4 wrote a state file")
if os.path.exists(pairing):
    raise SystemExit("case 4 wrote pairing.txt")
if os.path.exists(ran):
    raise SystemExit("case 4 ran the command")
if int(hits_after) != int(hits_before):
    raise SystemExit("case 4 called the stub")
print("   wrote nothing")
PY
scan_absent "$MESHD_STATE" "$DRAFT1" "$DRAFT2" "$DRAFT3" \
  "needle:sk-secret" "needle:llm.example"

echo "5. knowledge list stays {id, title}"
kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   http ${kcode}"
if [ "$kcode" != "200" ]; then
  echo "knowledge list -> ${kcode}" >&2
  exit 1
fi
python3 - "$TMP/meta/knowledge.json" "$ASK" "$REPLY" << 'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
ask, reply = sys.argv[2:]
obj = json.loads(raw)
if not isinstance(obj, dict) or set(obj.keys()) != {"notes"} or not isinstance(obj["notes"], list):
    raise SystemExit("knowledge payload keys are wrong")
items = obj["notes"]
if len(items) < 1:
    raise SystemExit("knowledge list is empty")
titles = []
for item in items:
    if set(item.keys()) != {"id", "title"}:
        raise SystemExit("knowledge item keys %s" % sorted(item.keys()))
    titles.append(item["title"])
if titles.count("Source note") != 1:
    raise SystemExit("note titles %s" % titles)
if "body" in raw or reply in raw or "sk-secret" in raw or "llm.example" in raw or "Local page" in raw:
    raise SystemExit("knowledge list includes a body or a model url")
print("   items", len(items))
PY
scan_absent "$MESHD_STATE" "$DRAFT1" "$DRAFT2" "$DRAFT3" \
  "needle:sk-secret" "needle:llm.example"

echo "ok"

#!/bin/sh
# Proves a spoken note can be asked through a user subscription.
# A local MESH_PDF binary prints one sentence and a local MESH_TTS binary
# exits 0. That path writes one knowledge note. It does not prove a speaker
# played audio and it does not prove a paper was read.
# The ask then goes to llm.example, mapped to loopback for this check only,
# so modelClass stays user-subscription. The model host string is llm.example.
# Confirm omitted does not run the shell command. Confirm true runs it once.
# A spoken transcript or an ask that names a pairing code is held before the
# model: the stub is not given that secret, no note is titled with the secret
# ask, and confirm true still does not run the command or save the reply.
# Drafts and responses do not keep the host or the key. The stub URL has no
# userinfo. This script does not read the process table. On exit the daemon
# process group and the stub are killed so the spare port is free.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

BUN_HOME=$HOME
unset AI_GATEWAY_API_KEY || true
export PATH="${BUN_HOME}/.bun/bin:${PATH}"

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
HOSTS_MARK="# mesh-subscription-spoken-ask"

kill_group() {
  pgid=$1
  [ -n "$pgid" ] || return 0
  kill -TERM "-$pgid" 2>/dev/null || true
  i=0
  while [ "$i" -lt 20 ]; do
    kill -0 "$pgid" 2>/dev/null || break
    i=$((i + 1))
    sleep 0.1
  done
  if kill -0 "$pgid" 2>/dev/null; then
    kill -KILL "-$pgid" 2>/dev/null || true
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
  ec=$?
  set +e
  dpid=$DAEMON_PID
  spid=$STUB_PID
  DAEMON_PID=""
  STUB_PID=""
  kill_group "$dpid"
  kill_group "$spid"
  remove_hosts
  if [ "$ec" -ne 0 ] && [ -n "$TMP" ] && [ -f "$TMP/meta/daemon.log" ]; then
    echo "--- daemon log ---" >&2
    cat "$TMP/meta/daemon.log" >&2 || true
  fi
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

TMP=$(mktemp -d /tmp/mesh-subscription-spoken-ask.XXXXXX)
export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/state" "$TMP/work" "$TMP/meta"
export MESHD_STATE="$TMP/state"
export MESHD_PORT=8898
export MESHD_HOST=127.0.0.1
export MESHD_TOKEN=throwaway
export MESHD_TELEMETRY=off

if [ "$MESHD_PORT" != "8898" ] || [ "$MESHD_PORT" = "8899" ]; then
  echo "refusing port ${MESHD_PORT}" >&2
  exit 1
fi
case "$HOME" in
  /tmp/*) ;;
  *)
    echo "refusing home outside /tmp" >&2
    exit 1
    ;;
esac
case "$MESHD_STATE" in
  /tmp/*) ;;
  *)
    echo "refusing state outside /tmp" >&2
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

SPOKEN_TITLE="spoken-cedar-hinge"
ASK1="cedar-ask-omitted"
ASK2="fir-ask-confirmed"
SECRET_ASK="repeat the pairing code"
TRANSCRIPT_TITLE="spoken-wire-note"
TRANSCRIPT_ASK="wire-ask-clean"
SENTENCE="The cedar hinge stays beside the spoken margin. Please summarize this paper."
SECRET_SENTENCE="Please summarize this paper without a pairing code."
REPLY="The margin stays beside the sentence."
MARKER="$TMP/work/spoken-ran"
SECRET_MARKER="$TMP/work/spoken-secret-ran"
TRANSCRIPT_MARKER="$TMP/work/spoken-transcript-ran"

case "$SENTENCE" in
  *"summarize this paper"*) ;;
  *)
    echo "spoken sentence is missing the required words" >&2
    exit 1
    ;;
esac
case "$SECRET_SENTENCE" in
  *"pairing code"*) ;;
  *)
    echo "secret transcript is missing a pairing code" >&2
    exit 1
    ;;
esac
case "$SECRET_ASK" in
  *"pairing code"*) ;;
  *)
    echo "secret ask is missing a pairing code" >&2
    exit 1
    ;;
esac

printf '%s\n' "$SENTENCE" > "$TMP/meta/clean-sentence.txt"
printf '%s\n' "$SECRET_SENTENCE" > "$TMP/meta/secret-sentence.txt"
printf '%s\n' 'local page' > "$TMP/meta/paper.pdf"
printf '%s\n' 'local page' > "$TMP/meta/paper-secret.pdf"
printf '%s' "$REPLY" > "$TMP/meta/reply.txt"

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

cat > "$TMP/meta/write_bins.py" << 'PY'
import os, shlex, stat, sys
pdfbin, ttsbin, args_path, tts_path, clean_path, secret_path = sys.argv[1:]
pdf = "\n".join([
    "#!/bin/sh",
    "set -eu",
    'if [ "$#" -ne 1 ]; then',
    "  exit 2",
    "fi",
    "printf '%s\\n' \"$1\" >> " + shlex.quote(args_path),
    'base=$(basename "$1")',
    "if [ \"$base\" = " + shlex.quote("paper-secret.pdf") + " ]; then",
    "  cat " + shlex.quote(secret_path),
    "else",
    "  cat " + shlex.quote(clean_path),
    "fi",
    "exit 0",
    "",
])
tts = "\n".join([
    "#!/bin/sh",
    "set -eu",
    "cat >> " + shlex.quote(tts_path),
    "printf '%s\\n' '--run--' >> " + shlex.quote(tts_path),
    "exit 0",
    "",
])
open(pdfbin, "w", encoding="utf-8").write(pdf)
open(ttsbin, "w", encoding="utf-8").write(tts)
os.chmod(pdfbin, stat.S_IRWXU)
os.chmod(ttsbin, stat.S_IRWXU)
PY

cat > "$TMP/meta/assert_allowed.py" << 'PY'
import json, os, sys
from urllib.parse import urlsplit

(
    label,
    body_path,
    before_path,
    after_path,
    work,
    hits_before,
    hits_after,
    stub_path,
    reply,
    draft_out,
    title,
    sentence,
    ask,
    want_ran,
    want_held,
    marker,
    model_url,
) = sys.argv[1:]
want_ran = want_ran == "true"
want_held = want_held == "true"
raw = open(body_path, encoding="utf-8").read()
forbidden = ["sk-secret", "user:sk-secret", "llm.example", model_url]
for needle in forbidden:
    if needle and needle in raw:
        raise SystemExit("%s response contains %s" % (label, needle))
obj = json.loads(raw)
if set(obj.keys()) != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("%s keys %s" % (label, sorted(obj.keys())))
if obj["modelClass"] != "user-subscription":
    raise SystemExit("%s modelClass %r" % (label, obj["modelClass"]))
if obj["commandRan"] is not want_ran or obj["held"] is not want_held:
    raise SystemExit("%s result %r" % (label, obj))
draft = obj["draft"]
if not isinstance(draft, str) or not draft or os.path.isabs(draft) or draft.startswith("..") or "/" in draft:
    raise SystemExit("%s draft is not one relative file: %r" % (label, draft))
before = {ln for ln in open(before_path, encoding="utf-8").read().splitlines() if ln}
after = {ln for ln in open(after_path, encoding="utf-8").read().splitlines() if ln}
new = sorted(after - before)
path = os.path.join(work, draft)
if new != [path]:
    raise SystemExit("%s expected one new mode-600 file, got %s" % (label, new))
mode = os.stat(path).st_mode & 0o777
if mode != 0o600 or mode & 0o111:
    raise SystemExit("%s mode %o" % (label, mode))
draft_text = open(path, encoding="utf-8").read()
if draft_text != reply:
    raise SystemExit("%s draft is not the stub reply" % label)
for needle in forbidden:
    if needle and needle in draft_text:
        raise SystemExit("%s draft contains %s" % (label, needle))
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("%s stub hits %s -> %s" % (label, hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
rec = recs[int(hits_before)]
url = rec.get("url") or ""
parts = urlsplit(url)
if parts.username or parts.password or "@" in url or "@" in (rec.get("requestline") or ""):
    raise SystemExit("%s stub url has userinfo: %r" % (label, url))
host = rec.get("host") or ""
if not host.startswith("llm.example:"):
    raise SystemExit("%s stub host %r" % (label, host))
if "127.0.0.1" in host or host.startswith("localhost"):
    raise SystemExit("%s model host must stay llm.example" % label)
payload = json.loads(rec.get("body") or "")
content = payload["messages"][0]["content"]
expect = "%s\n\n%s\n\n%s" % (title, sentence, ask)
if content != expect:
    raise SystemExit("%s prompt is %r" % (label, content))
if payload.get("model") != "user-subscription":
    raise SystemExit("%s stub model field %r" % (label, payload.get("model")))
for needle in ("sk-secret", "user:sk-secret", "llm.example", model_url):
    if needle and needle in content:
        raise SystemExit("%s prompt contains %s" % (label, needle))
if title not in content or sentence not in content or ask not in content:
    raise SystemExit("%s prompt missed the note or the ask" % label)
if want_ran:
    lines = open(marker, encoding="utf-8").read().splitlines()
    if lines != ["ran"]:
        raise SystemExit("%s marker %r" % (label, lines))
elif os.path.exists(marker):
    raise SystemExit("%s marker exists" % label)
open(draft_out, "w", encoding="utf-8").write(path)
print("   file", draft)
PY

cat > "$TMP/meta/assert_held.py" << 'PY'
import json, os, sys

(
    label,
    body_path,
    hits_before,
    hits_after,
    stub_path,
    marker,
    draft_file,
    work_before,
    work_after,
    model_url,
    secret_ask,
) = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
for needle in ("sk-secret", "user:sk-secret", "llm.example", model_url, "pairing code"):
    if needle and needle in raw:
        raise SystemExit("%s response contains %s" % (label, needle))
obj = json.loads(raw)
if set(obj.keys()) != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("%s keys %s" % (label, sorted(obj.keys())))
if obj["modelClass"] != "user-subscription" or obj["draft"] is not None or obj["commandRan"] is not False or obj["held"] is not True:
    raise SystemExit("%s was not held: %r" % (label, obj))
if int(hits_after) != int(hits_before):
    raise SystemExit("%s called the stub" % label)
stub = open(stub_path, encoding="utf-8").read()
if "pairing code" in stub:
    raise SystemExit("%s stub was given the secret" % label)
if os.path.exists(marker):
    raise SystemExit("%s ran the command" % label)
if os.path.exists(draft_file):
    raise SystemExit("%s wrote the secret draft" % label)

def lines(path):
    return [ln for ln in open(path, encoding="utf-8").read().splitlines() if ln]

if lines(work_before) != lines(work_after):
    raise SystemExit("%s wrote a work file" % label)
print("   held")
PY

cat > "$TMP/meta/assert_list.py" << 'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
need = json.loads(sys.argv[2])
forbid = json.loads(sys.argv[3])
absent = json.loads(sys.argv[4])
obj = json.loads(raw)
if set(obj.keys()) != {"notes"} or not isinstance(obj["notes"], list):
    raise SystemExit("knowledge payload keys are wrong")
titles = []
ids = []
for item in obj["notes"]:
    if set(item.keys()) != {"id", "title"}:
        raise SystemExit("knowledge item keys %s" % sorted(item.keys()))
    titles.append(item["title"])
    ids.append(item["id"])
if len(ids) != len(set(ids)):
    raise SystemExit("knowledge ids are not unique")
for title in need:
    if titles.count(title) != 1:
        raise SystemExit("missing title %s in %s" % (title, titles))
for title in forbid:
    if title in titles:
        raise SystemExit("saved forbidden title %s" % title)
for needle in absent:
    if needle and needle in raw:
        raise SystemExit("knowledge list contains %s" % needle)
print("   titles", len(titles))
PY

python3 "$TMP/meta/write_bins.py" \
  "$TMP/meta/pdfbin" "$TMP/meta/ttsbin" \
  "$TMP/meta/pdf-args" "$TMP/meta/tts-stdin" \
  "$TMP/meta/clean-sentence.txt" "$TMP/meta/secret-sentence.txt"
export MESH_PDF="$TMP/meta/pdfbin"
export MESH_TTS="$TMP/meta/ttsbin"

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
: > "$TMP/meta/stub.jsonl"

python3 "$TMP/meta/group.py" sh -c 'cd "$1" && bun run "$2"' sh "$TMP/work" "$ROOT/install/payload/meshd/server.ts" >"$TMP/meta/daemon.log" 2>&1 &
DAEMON_PID=$!

ready=0
i=0
while [ "$i" -lt 100 ]; do
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
  exit 1
fi

MODEL_URL="http://user:sk-secret@llm.example:${STUB_PORT}/v1"
case "$MODEL_URL" in
  *127.0.0.1*|*localhost*)
    echo "model host must not be local for user-subscription" >&2
    exit 1
    ;;
esac

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

echo "spoken note from local binaries"
python3 - "$TMP/meta/spoken.req" "$TMP/meta/paper.pdf" "$SPOKEN_TITLE" << 'PY'
import json, sys
json.dump({"pdf": sys.argv[2], "title": sys.argv[3], "speak": True}, open(sys.argv[1], "w"))
PY
spoken_code=$(curl -sS --max-time 20 -o "$TMP/meta/spoken.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST "http://127.0.0.1:${MESHD_PORT}/knowledge" \
  --data-binary "@$TMP/meta/spoken.req")
echo "   http ${spoken_code}"
if [ "$spoken_code" != "201" ]; then
  cat "$TMP/meta/spoken.json" >&2 || true
  exit 1
fi
python3 - "$TMP/meta/spoken.json" "$MESHD_STATE" "$TMP/meta/pdf-args" "$TMP/meta/tts-stdin" "$TMP/meta/paper.pdf" "$SENTENCE" "$SPOKEN_TITLE" "$TMP/meta/spoken.id" << 'PY'
import json, os, sys
post_path, state, args_path, spoken_path, pdf, sentence, title, id_path = sys.argv[1:]
raw = open(post_path, encoding="utf-8").read()
if pdf in raw or sentence in raw:
    raise SystemExit("spoken response includes the path or the body")
post = json.loads(raw)
if set(post.keys()) != {"id", "title", "spoken"}:
    raise SystemExit("spoken keys %s" % sorted(post.keys()))
if post.get("spoken") is not True or post.get("title") != title:
    raise SystemExit("spoken response %r" % post)
note_path = os.path.join(state, "knowledge", post["id"] + ".json")
names = [name for name in os.listdir(os.path.join(state, "knowledge")) if name.endswith(".json")]
if names != [post["id"] + ".json"]:
    raise SystemExit("knowledge files %r" % names)
note = json.load(open(note_path, encoding="utf-8"))
if note.get("title") != title or note.get("body") != sentence:
    raise SystemExit("stored spoken note %r" % note)
if note.get("source") != "paper.pdf" or pdf in json.dumps(note) or "local page" in note.get("body", ""):
    raise SystemExit("stored source %r" % note.get("source"))
if "summarize this paper" not in note.get("body", ""):
    raise SystemExit("stored sentence lost the required words")
args = open(args_path, encoding="utf-8").read().splitlines()
if args != [pdf]:
    raise SystemExit("extractor args %r" % args)
heard = open(spoken_path, encoding="utf-8").read()
if sentence not in heard or title not in heard or heard.count("--run--") != 1:
    raise SystemExit("local speaker stub did not exit after one run")
if pdf in heard:
    raise SystemExit("local speaker stub received the file path")
open(id_path, "w", encoding="utf-8").write(post["id"])
print("   note", post["id"])
PY

kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge-spoken.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   knowledge ${kcode}"
if [ "$kcode" != "200" ]; then
  echo "knowledge list -> ${kcode}" >&2
  exit 1
fi
python3 "$TMP/meta/assert_list.py" "$TMP/meta/knowledge-spoken.json" \
  "$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$SPOKEN_TITLE")" \
  "$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1], sys.argv[2]]))' "$ASK1" "$ASK2")" \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$SENTENCE" "local page" "sk-secret" "llm.example" "pairing code")"

echo "1. spoken note ask with confirm omitted does not run the command"
python3 - "$TMP/meta/case1.req" "$TMP/work" "$MODEL_URL" "$SPOKEN_TITLE" "$ASK1" "$MARKER" << 'PY'
import json, sys
body = {
    "q": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "spoken-held.txt",
    "ask": sys.argv[5],
    "command": "printf 'ran\\n' >> " + sys.argv[6],
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
printf '%s\n' "$before" > "$TMP/meta/before1.txt"
mode600_list > "$TMP/meta/after1.txt" || true
python3 "$TMP/meta/assert_allowed.py" \
  "case 1" "$TMP/meta/case1.json" "$TMP/meta/before1.txt" "$TMP/meta/after1.txt" \
  "$TMP/work" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$REPLY" \
  "$TMP/meta/case1.draft" "$SPOKEN_TITLE" "$SENTENCE" "$ASK1" \
  false true "$MARKER" "$MODEL_URL"
DRAFT1=$(cat "$TMP/meta/case1.draft")
scan_absent "$MESHD_STATE" "$DRAFT1" \
  "needle:sk-secret" "needle:user:sk-secret" "needle:llm.example"

echo "2. the same spoken note with confirm true runs the command once"
python3 - "$TMP/meta/case2.req" "$TMP/work" "$MODEL_URL" "$SPOKEN_TITLE" "$ASK2" "$MARKER" << 'PY'
import json, sys
body = {
    "q": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "spoken-confirmed.txt",
    "ask": sys.argv[5],
    "command": "printf 'ran\\n' >> " + sys.argv[6],
    "confirm": True,
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
printf '%s\n' "$before" > "$TMP/meta/before2.txt"
mode600_list > "$TMP/meta/after2.txt" || true
python3 "$TMP/meta/assert_allowed.py" \
  "case 2" "$TMP/meta/case2.json" "$TMP/meta/before2.txt" "$TMP/meta/after2.txt" \
  "$TMP/work" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$REPLY" \
  "$TMP/meta/case2.draft" "$SPOKEN_TITLE" "$SENTENCE" "$ASK2" \
  true false "$MARKER" "$MODEL_URL"
DRAFT2=$(cat "$TMP/meta/case2.draft")
scan_absent "$MESHD_STATE" "$DRAFT1" "$DRAFT2" \
  "needle:sk-secret" "needle:user:sk-secret" "needle:llm.example"

echo "3. a pairing-code ask or transcript is held"
file_list "$TMP/work" > "$TMP/meta/work-before-secret.txt"
hits_before=$(hit_count)
python3 - "$TMP/meta/case3.req" "$TMP/work" "$MODEL_URL" "$SPOKEN_TITLE" "$SECRET_ASK" "$SECRET_MARKER" << 'PY'
import json, sys
body = {
    "q": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "spoken-secret-ask.txt",
    "ask": sys.argv[5],
    "command": "printf 'ran\\n' >> " + sys.argv[6],
    "confirm": True,
}
json.dump(body, open(sys.argv[1], "w"))
PY
code=$(post_note "$TMP/meta/case3.req" "$TMP/meta/case3.json")
echo "   ask http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case3.json" >&2 || true
  exit 1
fi
file_list "$TMP/work" > "$TMP/meta/work-after-secret.txt"
python3 "$TMP/meta/assert_held.py" \
  "case 3 ask" "$TMP/meta/case3.json" "$hits_before" "$hits_after" \
  "$TMP/meta/stub.jsonl" "$SECRET_MARKER" "$TMP/work/spoken-secret-ask.txt" \
  "$TMP/meta/work-before-secret.txt" "$TMP/meta/work-after-secret.txt" \
  "$MODEL_URL" "$SECRET_ASK"

kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge-ask.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   knowledge ${kcode}"
if [ "$kcode" != "200" ]; then
  echo "knowledge list -> ${kcode}" >&2
  exit 1
fi
python3 "$TMP/meta/assert_list.py" "$TMP/meta/knowledge-ask.json" \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$SPOKEN_TITLE" "$ASK1" "$ASK2")" \
  "$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$SECRET_ASK")" \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "pairing code" "sk-secret" "user:sk-secret" "llm.example" "$REPLY" "$SENTENCE")"

python3 - "$TMP/meta/secret-spoken.req" "$TMP/meta/paper-secret.pdf" "$TRANSCRIPT_TITLE" << 'PY'
import json, sys
json.dump({"pdf": sys.argv[2], "title": sys.argv[3], "speak": True}, open(sys.argv[1], "w"))
PY
secret_spoken_code=$(curl -sS --max-time 20 -o "$TMP/meta/secret-spoken.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST "http://127.0.0.1:${MESHD_PORT}/knowledge" \
  --data-binary "@$TMP/meta/secret-spoken.req")
echo "   transcript http ${secret_spoken_code}"
if [ "$secret_spoken_code" != "201" ]; then
  cat "$TMP/meta/secret-spoken.json" >&2 || true
  exit 1
fi
python3 - "$TMP/meta/secret-spoken.json" "$MESHD_STATE" "$SECRET_SENTENCE" "$TRANSCRIPT_TITLE" << 'PY'
import json, os, sys
post = json.load(open(sys.argv[1], encoding="utf-8"))
state, sentence, title = sys.argv[2:]
if post.get("spoken") is not True or post.get("title") != title:
    raise SystemExit("secret transcript response %r" % post)
if set(post.keys()) != {"id", "title", "spoken"}:
    raise SystemExit("secret transcript keys %s" % sorted(post.keys()))
note = json.load(open(os.path.join(state, "knowledge", post["id"] + ".json"), encoding="utf-8"))
if note.get("body") != sentence or note.get("title") != title:
    raise SystemExit("stored secret transcript %r" % note)
print("   transcript stored")
PY

file_list "$TMP/work" > "$TMP/meta/work-before-transcript.txt"
hits_before=$(hit_count)
python3 - "$TMP/meta/case3b.req" "$TMP/work" "$MODEL_URL" "$TRANSCRIPT_TITLE" "$TRANSCRIPT_ASK" "$TRANSCRIPT_MARKER" << 'PY'
import json, sys
body = {
    "q": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "spoken-secret-transcript.txt",
    "ask": sys.argv[5],
    "command": "printf 'ran\\n' >> " + sys.argv[6],
    "confirm": True,
}
json.dump(body, open(sys.argv[1], "w"))
PY
code=$(post_note "$TMP/meta/case3b.req" "$TMP/meta/case3b.json")
echo "   transcript ask http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case3b.json" >&2 || true
  exit 1
fi
file_list "$TMP/work" > "$TMP/meta/work-after-transcript.txt"
python3 "$TMP/meta/assert_held.py" \
  "case 3 transcript" "$TMP/meta/case3b.json" "$hits_before" "$hits_after" \
  "$TMP/meta/stub.jsonl" "$TRANSCRIPT_MARKER" "$TMP/work/spoken-secret-transcript.txt" \
  "$TMP/meta/work-before-transcript.txt" "$TMP/meta/work-after-transcript.txt" \
  "$MODEL_URL" "$TRANSCRIPT_ASK"

kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge-final.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   knowledge ${kcode}"
if [ "$kcode" != "200" ]; then
  echo "knowledge list -> ${kcode}" >&2
  exit 1
fi
python3 "$TMP/meta/assert_list.py" "$TMP/meta/knowledge-final.json" \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$SPOKEN_TITLE" "$ASK1" "$ASK2" "$TRANSCRIPT_TITLE")" \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$SECRET_ASK" "$TRANSCRIPT_ASK")" \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "pairing code" "sk-secret" "user:sk-secret" "llm.example" "$MODEL_URL" "$REPLY" "$SENTENCE" "$SECRET_SENTENCE")"
scan_absent "$MESHD_STATE" "$DRAFT1" "$DRAFT2" \
  "needle:sk-secret" "needle:user:sk-secret" "needle:llm.example"


echo "4. a secret reply to the spoken note stays held"
cp "$TMP/meta/reply.txt" "$TMP/meta/reply-safe.txt"
printf '%s' 'The pairing code stays on this machine.' > "$TMP/meta/reply.txt"
REPLY_MARKER="$TMP/work/spoken-reply-held"
SAFE_ASK="hinge-margin-check"
case "$SAFE_ASK" in
  *"pairing code"*|*"hosts.json"*|*"sk-secret"*)
    echo "ask names a secret" >&2
    exit 1
    ;;
esac
file_list "$TMP/work" > "$TMP/meta/work-before-reply.txt"
hits_before=$(hit_count)
python3 - "$TMP/meta/case4.req" "$TMP/work" "$MODEL_URL" "$SPOKEN_TITLE" "$SAFE_ASK" "$REPLY_MARKER" << 'PY'
import json, sys
ask = sys.argv[5]
for needle in ("pairing code", "hosts.json", "sk-secret", "user:sk-secret"):
    if needle in ask:
        raise SystemExit("ask names a secret")
body = {
    "q": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "spoken-reply-held.txt",
    "ask": ask,
    "command": "printf 'ran\\n' >> " + sys.argv[6],
    "confirm": True,
}
json.dump(body, open(sys.argv[1], "w"))
PY
code=$(post_note "$TMP/meta/case4.req" "$TMP/meta/case4.json")
cp "$TMP/meta/reply-safe.txt" "$TMP/meta/reply.txt"
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case4.json" >&2 || true
  exit 1
fi
if [ -e "$REPLY_MARKER" ] || [ -e "$TMP/work/spoken-reply-held.txt" ]; then
  echo "secret reply wrote a file or ran the command" >&2
  exit 1
fi
file_list "$TMP/work" > "$TMP/meta/work-after-reply.txt"
python3 - "$TMP/meta/case4.json" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$REPLY_MARKER" "$TMP/work/spoken-reply-held.txt" "$TMP/meta/work-before-reply.txt" "$TMP/meta/work-after-reply.txt" "$SPOKEN_TITLE" "$SAFE_ASK" << 'PY'
import json, os, sys
(
    body_path,
    hits_before,
    hits_after,
    stub_path,
    marker,
    draft_file,
    work_before,
    work_after,
    title,
    ask,
) = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
for needle in ("sk-secret", "user:sk-secret", "llm.example"):
    if needle in raw:
        raise SystemExit("secret reply response contains %s" % needle)
obj = json.loads(raw)
if set(obj.keys()) != {"modelClass", "draft", "commandRan", "held"}:
    raise SystemExit("secret reply keys %s" % sorted(obj.keys()))
if obj["modelClass"] != "user-subscription" or obj["held"] is not True or obj["commandRan"] is not False or obj["draft"] is not None:
    raise SystemExit("secret reply was not held: %r" % obj)
if os.path.exists(marker) or os.path.exists(draft_file):
    raise SystemExit("secret reply created a marker or a draft")
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("secret reply stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
sent = recs[int(hits_before)].get("body") or ""
if title not in sent or ask not in sent:
    raise SystemExit("secret reply did not ask the spoken note")
if "pairing code" in sent or "hosts.json" in sent:
    raise SystemExit("secret reply sent a secret to the stub")

def lines(path):
    return [ln for ln in open(path, encoding="utf-8").read().splitlines() if ln]

if lines(work_before) != lines(work_after):
    raise SystemExit("secret reply wrote a work file")
print("   held")
PY
kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge-reply.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   knowledge ${kcode}"
if [ "$kcode" != "200" ]; then
  echo "knowledge list -> ${kcode}" >&2
  exit 1
fi
python3 - "$TMP/meta/knowledge-reply.json" "$SPOKEN_TITLE" << 'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
title = sys.argv[2]
secret = "The pairing code stays on this machine."
obj = json.loads(raw)
titles = []
for item in obj["notes"]:
    name = item["title"]
    titles.append(name)
    if "pairing code" in name or name == secret:
        raise SystemExit("knowledge saved a secret title: %s" % name)
if title not in titles:
    raise SystemExit("spoken note missing after the secret reply")
print("   no secret title")
PY

echo "5. ask the saved spoken note after the held secret reply"
printf '%s' 'The margin stays beside the sentence.' > "$TMP/meta/reply.txt"
SAVED_ASK_OMITTED="saved-margin-omitted"
SAVED_ASK_CONFIRMED="saved-margin-confirmed"
SAVED_OMITTED_MARKER="$TMP/work/spoken-saved-omitted"
SAVED_CONFIRMED_MARKER="$TMP/work/spoken-saved-confirmed"
for saved_ask in "$SAVED_ASK_OMITTED" "$SAVED_ASK_CONFIRMED"; do
  case "$saved_ask" in
    *"pairing code"*|*"hosts.json"*|*"sk-secret"*|*"user:sk-secret"*)
      echo "saved ask names a secret" >&2
      exit 1
      ;;
  esac
done

python3 - "$TMP/meta/case5.req" "$TMP/work" "$MODEL_URL" "$SPOKEN_TITLE" "$SAVED_ASK_OMITTED" "$SAVED_OMITTED_MARKER" << 'PY'
import json, sys
ask = sys.argv[5]
for needle in ("pairing code", "hosts.json", "sk-secret", "user:sk-secret"):
    if needle in ask:
        raise SystemExit("ask names a secret")
body = {
    "q": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "spoken-saved-omitted.txt",
    "ask": ask,
    "command": "printf 'ran\\n' >> " + sys.argv[6],
}
if "confirm" in body:
    raise SystemExit("confirm was set on the omitted ask")
if body["q"] != "spoken-cedar-hinge":
    raise SystemExit("query is not the saved title")
json.dump(body, open(sys.argv[1], "w"))
PY
hits_before=$(hit_count)
code=$(post_note "$TMP/meta/case5.req" "$TMP/meta/case5.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case5.json" >&2 || true
  exit 1
fi
if [ -e "$SAVED_OMITTED_MARKER" ]; then
  echo "omitted ask ran the command" >&2
  exit 1
fi
python3 - "$TMP/meta/case5.json" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$SAVED_OMITTED_MARKER" "$SPOKEN_TITLE" "$SENTENCE" "$SAVED_ASK_OMITTED" << 'PY'
import json, os, sys
body_path, hits_before, hits_after, stub_path, marker, title, sentence, ask = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
for needle in ("sk-secret", "user:sk-secret", "llm.example"):
    if needle in raw:
        raise SystemExit("omitted response contains %s" % needle)
obj = json.loads(raw)
if obj.get("modelClass") != "user-subscription" or obj.get("commandRan") is not False:
    raise SystemExit("omitted ask result %r" % obj)
if os.path.exists(marker):
    raise SystemExit("omitted ask ran the command")
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("omitted ask stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
sent = recs[int(hits_before)].get("body") or ""
if title not in sent or sentence not in sent or ask not in sent:
    raise SystemExit("omitted ask did not send the saved note")
secret = "The pairing code stays on this machine."
if secret in sent or "pairing code" in sent or "hosts.json" in sent:
    raise SystemExit("omitted ask sent a secret to the stub")
print("   omitted")
PY
kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge-saved-omitted.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   knowledge ${kcode}"
if [ "$kcode" != "200" ]; then
  echo "knowledge list -> ${kcode}" >&2
  exit 1
fi
python3 - "$TMP/meta/knowledge-saved-omitted.json" << 'PY'
import json, sys
obj = json.loads(open(sys.argv[1], encoding="utf-8").read())
for item in obj["notes"]:
    name = item["title"]
    if "pairing code" in name:
        raise SystemExit("knowledge saved a secret title: %s" % name)
print("   no secret title")
PY

echo "6. confirm true asks the same saved title and runs the command once"
python3 - "$TMP/meta/case6.req" "$TMP/work" "$MODEL_URL" "$SPOKEN_TITLE" "$SAVED_ASK_CONFIRMED" "$SAVED_CONFIRMED_MARKER" << 'PY'
import json, sys
ask = sys.argv[5]
for needle in ("pairing code", "hosts.json", "sk-secret", "user:sk-secret"):
    if needle in ask:
        raise SystemExit("ask names a secret")
body = {
    "q": sys.argv[4],
    "cwd": sys.argv[2],
    "model": sys.argv[3],
    "file": "spoken-saved-confirmed.txt",
    "ask": ask,
    "command": "printf 'ran\\n' >> " + sys.argv[6],
    "confirm": True,
}
if body["q"] != "spoken-cedar-hinge":
    raise SystemExit("query is not the saved title")
json.dump(body, open(sys.argv[1], "w"))
PY
hits_before=$(hit_count)
code=$(post_note "$TMP/meta/case6.req" "$TMP/meta/case6.json")
echo "   http ${code}"
hits_after=$(hit_count)
if [ "$code" != "200" ]; then
  cat "$TMP/meta/case6.json" >&2 || true
  exit 1
fi
python3 - "$TMP/meta/case6.json" "$hits_before" "$hits_after" "$TMP/meta/stub.jsonl" "$SAVED_CONFIRMED_MARKER" "$SAVED_OMITTED_MARKER" "$TMP/work" "$SPOKEN_TITLE" "$SENTENCE" "$SAVED_ASK_CONFIRMED" << 'PY'
import json, os, sys
(
    body_path,
    hits_before,
    hits_after,
    stub_path,
    marker,
    omitted_marker,
    work,
    title,
    sentence,
    ask,
) = sys.argv[1:]
raw = open(body_path, encoding="utf-8").read()
for needle in ("sk-secret", "user:sk-secret", "llm.example"):
    if needle in raw:
        raise SystemExit("confirmed response contains %s" % needle)
obj = json.loads(raw)
if obj.get("modelClass") != "user-subscription" or obj.get("commandRan") is not True:
    raise SystemExit("confirmed ask result %r" % obj)
if os.path.exists(omitted_marker):
    raise SystemExit("omitted marker appeared")
lines = open(marker, encoding="utf-8").read().splitlines()
if lines != ["ran"]:
    raise SystemExit("confirmed marker %r" % lines)
if int(hits_after) != int(hits_before) + 1:
    raise SystemExit("confirmed ask stub hits %s -> %s" % (hits_before, hits_after))
recs = [json.loads(ln) for ln in open(stub_path, encoding="utf-8").read().splitlines() if ln.strip()]
sent = recs[int(hits_before)].get("body") or ""
secret = "The pairing code stays on this machine."
if title not in sent or sentence not in sent or ask not in sent:
    raise SystemExit("confirmed ask did not send the saved note")
if secret in sent or "pairing code" in sent or "hosts.json" in sent:
    raise SystemExit("confirmed ask sent a secret to the stub")
draft = obj.get("draft")
if not isinstance(draft, str) or not draft or draft.startswith("/") or draft.startswith("..") or "/" in draft:
    raise SystemExit("confirmed draft %r" % draft)
draft_text = open(os.path.join(work, draft), encoding="utf-8").read()
for needle in ("sk-secret", "user:sk-secret", "llm.example", secret):
    if needle in draft_text:
        raise SystemExit("confirmed draft contains %s" % needle)
print("   ran once")
PY
kcode=$(curl -sS --max-time 10 -o "$TMP/meta/knowledge-saved-confirmed.json" -w '%{http_code}' \
  -H "Authorization: Bearer ${MESHD_TOKEN}" \
  "http://127.0.0.1:${MESHD_PORT}/knowledge")
echo "   knowledge ${kcode}"
if [ "$kcode" != "200" ]; then
  echo "knowledge list -> ${kcode}" >&2
  exit 1
fi
python3 - "$TMP/meta/knowledge-saved-confirmed.json" << 'PY'
import json, sys
obj = json.loads(open(sys.argv[1], encoding="utf-8").read())
for item in obj["notes"]:
    name = item["title"]
    if "pairing code" in name:
        raise SystemExit("knowledge saved a secret title: %s" % name)
print("   no secret title")
PY

echo "ok"

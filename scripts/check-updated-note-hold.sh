#!/bin/sh
# A replaced note whose text would move a pairing code, or hosts.json, is
# held by the existing route(). The loopback model is not called, no held
# file is written, and no command runs. A second note replaced with a clean
# paper summary is drafted to one relative file. The spare daemon is
# 127.0.0.1:8898. This script does not use port 8899, a real home directory,
# or the AI gateway.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
unset AI_GATEWAY_API_KEY
if [ -x "$HOME/.bun/bin/bun" ]; then
  PATH="$HOME/.bun/bin:$PATH"
fi
export PATH
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl is required"; exit 1; }

if grep -E -n 'supabase|ai-gateway' \
  "$ROOT/install/payload/meshd/agent-note.ts" \
  "$ROOT/install/payload/meshd/knowledge.ts"; then
  echo "FAIL: note path names supabase or the AI gateway"
  exit 1
fi
grep -q 'handleKnowledge' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route knowledge"
  exit 1
}
calls="$(grep -c 'handleKnowledge(' "$ROOT/install/payload/meshd/server.ts" || true)"
[ "$calls" = "1" ] || { echo "FAIL: expected one knowledge route, found $calls"; exit 1; }
grep -q '../jev-routing/route.ts' "$ROOT/experiments/note-route-draft/draft.ts" || {
  echo "FAIL: draft does not use the existing route"
  exit 1
}
if grep -E -q 'child_process|Bun\.spawn|execFile\(' "$ROOT/experiments/note-route-draft/draft.ts"; then
  echo "FAIL: draft module can run a file"
  exit 1
fi
if grep -q 'ai-gateway.vercel.sh' "$ROOT/experiments/note-route-draft/draft.ts"; then
  echo "FAIL: draft module names the gateway"
  exit 1
fi

# Classify in process. This does not open a socket.
bun -e '
import { modelClassOf, completionsEndpoint } from "./install/payload/meshd/agent-note.ts";
const allowed = new Set(["local", "user-subscription"]);
const samples = [
  ["http://127.0.0.1:9/v1", "local"],
  ["https://models.example/v1", "user-subscription"],
  ["local", "local"],
  ["user-subscription", "user-subscription"],
  ["ftp://files.example/v1", "user-subscription"],
];
for (const [sample, want] of samples) {
  const got = modelClassOf(sample);
  if (!allowed.has(got)) {
    console.error("FAIL: model class is " + got);
    process.exit(1);
  }
  if (got !== want) {
    console.error("FAIL: " + sample + " class is " + got);
    process.exit(1);
  }
}
if (completionsEndpoint("https://models.example/v1") === null) {
  console.error("FAIL: subscription class has no endpoint shape");
  process.exit(1);
}
if (completionsEndpoint("ftp://files.example/v1") !== null) {
  console.error("FAIL: remote scheme has an endpoint");
  process.exit(1);
}
if (completionsEndpoint("local") !== null || completionsEndpoint("user-subscription") !== null) {
  console.error("FAIL: class label has an endpoint");
  process.exit(1);
}
' || { echo "FAIL: model classification"; exit 1; }
echo "check-updated-note-hold: model class is local or user-subscription"

fixture_text() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["text"], end="")' \
    "$ROOT/experiments/jev-routing/fixtures.json" "$1"
}
PAIRING="$(fixture_text sendPairingCode)"
HOSTS="$(fixture_text copyHosts)"
PAPER="$(fixture_text summarizePaper)"
[ -n "$PAIRING" ] && [ -n "$HOSTS" ] && [ -n "$PAPER" ] || {
  echo "FAIL: route fixtures are empty"
  exit 1
}

TH="$(mktemp -d)"
HOME_DIR="$TH/home"
STATE="$TH/state"
WORK="$TH/session"
LOG="$TH/meshd.log"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
PORT=8898
OLD1='Old body stays until replaced'
OLD2='Earlier paper text stays out'
SRV=
MESH_MARK="$HOME/.mesh"
had_mesh=0
[ -e "$MESH_MARK" ] && had_mesh=1

case "$PORT" in
  8899) echo "FAIL: refusing port 8899"; exit 1 ;;
esac
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

python3 - "$PORT" <<'PY'
import socket, sys
port = int(sys.argv[1])
sock = socket.socket()
try:
    sock.bind(("127.0.0.1", port))
except OSError:
    sys.exit("FAIL: port %s is already in use" % port)
finally:
    sock.close()
PY

mkdir -p "$HOME_DIR" "$STATE" "$WORK"
chmod 700 "$HOME_DIR" "$STATE" "$WORK"

make_pdf() {
  title="$1"
  body="$2"
  dest="$3"
  TITLE="$title" BODY="$body" python3 - "$dest" <<'PY'
import os, sys
path = sys.argv[1]
title = os.environ["TITLE"]
body = os.environ["BODY"]
stream = ("BT /F1 12 Tf 72 720 Td (%s) Tj ET\n" % body).encode()
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
}
make_pdf "Spare note" "$OLD1" "$TH/spare.pdf"
make_pdf "Paper note" "$OLD2" "$TH/paper.pdf"

env -u AI_GATEWAY_API_KEY \
  MESHD_PORT=$PORT \
  MESHD_HOST=127.0.0.1 \
  MESHD_TOKEN="$TOKEN" \
  MESHD_STATE="$STATE" \
  MESHD_TELEMETRY=off \
  MESHD_EVENTS_PATH="$TH/agent-events.jsonl" \
  MESHD_TELEMETRY_STATE="$TH/telemetry.json" \
  MESHD_KB_PATH="$TH/kb.sqlite" \
  HOME="$HOME_DIR" \
  bun install/payload/meshd/server.ts >"$LOG" 2>&1 &
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
echo "check-updated-note-hold: spare daemon is on 127.0.0.1:${PORT}"

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

post_pdf() {
  pdf="$1"
  out="$2"
  curl --connect-timeout 1 --max-time 5 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data "{\"path\":\"${pdf}\"}" \
    "http://127.0.0.1:$PORT/knowledge" || true
}

replace_body() {
  id="$1"
  text="$2"
  out="$3"
  python3 - "$TH/body.json" "$text" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"body": sys.argv[2]}))
PY
  curl --connect-timeout 1 --max-time 5 -sS -o "$out" -w '%{http_code}' \
    -H "authorization: Bearer ${TOKEN}" \
    -H 'content-type: application/json' \
    --data @"$TH/body.json" \
    "http://127.0.0.1:$PORT/knowledge/${id}" || true
}

code="$(post_pdf "$TH/spare.pdf" "$TH/post.json")"
[ "$code" = "201" ] || { echo "FAIL: POST /knowledge -> ${code}"; cat "$TH/post.json"; echo; cat "$LOG"; exit 1; }
ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/post.json")"
NOTE_FILE="$STATE/knowledge/${ID}.json"
[ -f "$NOTE_FILE" ] || { echo "FAIL: created note file is missing"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: expected one note after create, found $(note_count)"; exit 1; }
OLD1="$OLD1" python3 - "$NOTE_FILE" "$ID" <<'PY'
import json, os, sys
note = json.load(open(sys.argv[1]))
old = os.environ["OLD1"]
if note.get("id") != sys.argv[2]:
    raise SystemExit("FAIL: created id is %r" % (note.get("id"),))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: created title is %r" % (note.get("title"),))
if note.get("body") != old:
    raise SystemExit("FAIL: created body is %r" % (note.get("body"),))
PY
echo "check-updated-note-hold: one note stored the old body"

code="$(replace_body "$ID" "$PAIRING" "$TH/pairing-res.json")"
[ "$code" = "200" ] || { echo "FAIL: POST /knowledge/:id -> ${code}"; cat "$TH/pairing-res.json"; echo; cat "$LOG"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: pairing replace created a second note, found $(note_count)"; exit 1; }
PAIRING="$PAIRING" OLD1="$OLD1" python3 - "$NOTE_FILE" "$ID" <<'PY'
import json, os, sys
note = json.load(open(sys.argv[1]))
if note.get("id") != sys.argv[2]:
    raise SystemExit("FAIL: pairing file id is %r" % (note.get("id"),))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: pairing replace changed the title to %r" % (note.get("title"),))
if note.get("body") != os.environ["PAIRING"]:
    raise SystemExit("FAIL: pairing body was not stored")
if os.environ["OLD1"] in note.get("body", ""):
    raise SystemExit("FAIL: pairing body still contains the old text")
PY
fmode="$(mode_of "$NOTE_FILE")"
[ "$fmode" = "600" ] || { echo "FAIL: note file mode is $fmode, want 600"; exit 1; }
dmode="$(mode_of "$STATE/knowledge")"
[ "$dmode" = "700" ] || { echo "FAIL: knowledge directory mode is $dmode, want 700"; exit 1; }
cp "$NOTE_FILE" "$TH/pairing.json"
echo "check-updated-note-hold: pairing ask replaced the same file"

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
if grep -q "$PAIRING" "$TH/list.json" || grep -q "$OLD1" "$TH/list.json"; then
  echo "FAIL: GET /knowledge returned the note body"
  exit 1
fi
echo "check-updated-note-hold: list is id and title"

MISS="$(python3 -c 'import uuid; print(uuid.uuid4())')"
[ "$MISS" != "$ID" ] || { echo "FAIL: missing id collided with the note"; exit 1; }
python3 - "$TH/missing.json" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"body": "do not create this note"}))
PY
cp "$NOTE_FILE" "$TH/frozen.json"
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/missing-out.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  -H 'content-type: application/json' \
  --data @"$TH/missing.json" \
  "http://127.0.0.1:$PORT/knowledge/${MISS}" || true)"
[ "$code" = "404" ] || { echo "FAIL: missing id -> ${code}"; cat "$TH/missing-out.json"; echo; exit 1; }
[ ! -e "$STATE/knowledge/${MISS}.json" ] || { echo "FAIL: missing id created a note"; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: missing id changed the note count to $(note_count)"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/frozen.json" || { echo "FAIL: missing id rewrote the existing note"; exit 1; }
echo "check-updated-note-hold: missing id created nothing"

code="$(replace_body "$ID" "$HOSTS" "$TH/hosts-res.json")"
[ "$code" = "200" ] || { echo "FAIL: hosts replace -> ${code}"; cat "$TH/hosts-res.json"; echo; exit 1; }
[ "$(note_count)" = "1" ] || { echo "FAIL: hosts replace created a note, found $(note_count)"; exit 1; }
[ "$STATE/knowledge/${ID}.json" = "$NOTE_FILE" ]
HOSTS="$HOSTS" PAIRING="$PAIRING" python3 - "$NOTE_FILE" "$ID" <<'PY'
import json, os, sys
note = json.load(open(sys.argv[1]))
if note.get("id") != sys.argv[2]:
    raise SystemExit("FAIL: hosts file id is %r" % (note.get("id"),))
if note.get("title") != "Spare note":
    raise SystemExit("FAIL: hosts replace changed the title")
if note.get("body") != os.environ["HOSTS"]:
    raise SystemExit("FAIL: hosts body was not stored")
if os.environ["PAIRING"] in note.get("body", ""):
    raise SystemExit("FAIL: hosts body still contains the pairing ask")
PY
cp "$NOTE_FILE" "$TH/hosts.json"
echo "check-updated-note-hold: hosts.json ask replaced the same file"

code="$(post_pdf "$TH/paper.pdf" "$TH/paper-post.json")"
[ "$code" = "201" ] || { echo "FAIL: second POST /knowledge -> ${code}"; cat "$TH/paper-post.json"; echo; cat "$LOG"; exit 1; }
ID2="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TH/paper-post.json")"
[ "$ID2" != "$ID" ] || { echo "FAIL: second note reused the first id"; exit 1; }
NOTE2="$STATE/knowledge/${ID2}.json"
[ -f "$NOTE2" ] || { echo "FAIL: second note file is missing"; exit 1; }
[ "$(note_count)" = "2" ] || { echo "FAIL: expected two notes, found $(note_count)"; exit 1; }
OLD2="$OLD2" python3 - "$NOTE2" "$ID2" <<'PY'
import json, os, sys
note = json.load(open(sys.argv[1]))
if note.get("id") != sys.argv[2] or note.get("title") != "Paper note":
    raise SystemExit("FAIL: second note is %r" % (note,))
if note.get("body") != os.environ["OLD2"]:
    raise SystemExit("FAIL: second note did not store its old body")
PY
code="$(replace_body "$ID2" "$PAPER" "$TH/paper-res.json")"
[ "$code" = "200" ] || { echo "FAIL: paper replace -> ${code}"; cat "$TH/paper-res.json"; echo; exit 1; }
[ "$(note_count)" = "2" ] || { echo "FAIL: paper replace changed the note count to $(note_count)"; exit 1; }
PAPER="$PAPER" OLD2="$OLD2" python3 - "$NOTE2" "$ID2" <<'PY'
import json, os, sys
note = json.load(open(sys.argv[1]))
if note.get("id") != sys.argv[2]:
    raise SystemExit("FAIL: paper file id is %r" % (note.get("id"),))
if note.get("title") != "Paper note":
    raise SystemExit("FAIL: paper replace changed the title")
if note.get("body") != os.environ["PAPER"]:
    raise SystemExit("FAIL: paper body was not stored")
if os.environ["OLD2"] in note.get("body", ""):
    raise SystemExit("FAIL: paper body still contains the old text")
PY
cp "$NOTE2" "$TH/paper.json"
code="$(curl --connect-timeout 1 --max-time 5 -sS -o "$TH/list2.json" -w '%{http_code}' \
  -H "authorization: Bearer ${TOKEN}" \
  "http://127.0.0.1:$PORT/knowledge" || true)"
[ "$code" = "200" ] || { echo "FAIL: GET /knowledge after paper -> ${code}"; exit 1; }
python3 - "$TH/list2.json" "$ID" "$ID2" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
notes = data.get("notes")
if not isinstance(notes, list) or len(notes) != 2:
    raise SystemExit("FAIL: list after paper is %r" % (notes,))
want = {sys.argv[2]: "Spare note", sys.argv[3]: "Paper note"}
got = {}
for note in notes:
    if set(note.keys()) != {"id", "title"}:
        raise SystemExit("FAIL: list note keys are %r" % (sorted(note.keys()),))
    got[note.get("id")] = note.get("title")
if got != want:
    raise SystemExit("FAIL: list notes are %r" % (got,))
PY
if grep -q "$PAPER" "$TH/list2.json" || grep -q "$HOSTS" "$TH/list2.json" || grep -q "$OLD2" "$TH/list2.json"; then
  echo "FAIL: GET /knowledge returned a replaced body"
  exit 1
fi
echo "check-updated-note-hold: second note replaced with the paper summary"

cat > "$TH/prove.ts" <<'TS'
import { spawn } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const root = process.argv[2];
const pairingPath = process.argv[3];
const hostsPath = process.argv[4];
const paperPath = process.argv[5];
const work = process.argv[6];
const old1 = process.argv[7];
const old2 = process.argv[8];

function fail(message: string): never {
  console.error("FAIL: " + message);
  process.exit(1);
}

const draftMod = await import(pathToFileURL(join(root, "experiments/note-route-draft/draft.ts")).href);
const routeMod = await import(pathToFileURL(join(root, "experiments/jev-routing/route.ts")).href);
const filterMod = await import(pathToFileURL(join(root, "experiments/jev-routing/filter.ts")).href);
const { draftNote, modelClassOf } = draftMod;
const { route } = routeMod;
const { filter } = filterMod;

const allow = {
  surface: "terminal-text",
  choice: "allow-local-tool",
  score: 0.2,
  boolean: true,
  confidence: 0.6,
};

const fixtures = JSON.parse(readFileSync(join(root, "experiments/jev-routing/fixtures.json"), "utf8")) as {
  sendPairingCode: { text: string };
  copyHosts: { text: string };
  readMeshToken: { text: string };
  sendMeshBearer: { text: string };
  summarizePaper: { text: string };
  sendMessage: { text: string };
};

function noteOf(path: string): Record<string, unknown> {
  const note = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
  if (typeof note.body !== "string" || typeof note.id !== "string") fail("stored note has no body");
  return note;
}

const allowedClass = new Set(["local", "user-subscription"]);
function assertClass(value: string, label: string): void {
  if (!allowedClass.has(value)) fail(label + " model class is " + value);
}

const samples: [string, string][] = [
  ["local", "local"],
  ["user-subscription", "user-subscription"],
  ["http://127.0.0.1:9/v1/chat/completions", "local"],
  ["https://models.example/v1", "user-subscription"],
];
for (const [sample, want] of samples) {
  const got = modelClassOf(sample);
  assertClass(got, sample);
  if (got !== want) fail(sample + " class is " + got);
}

const realFetch = globalThis.fetch;
let fetches = 0;
globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = input instanceof Request ? input.url : String(input);
  let host = "";
  try {
    host = new URL(url).hostname;
  } catch {
    host = "";
  }
  if (host !== "127.0.0.1") fail("fetch left 127.0.0.1");
  fetches += 1;
  return realFetch(input, init);
};

type Hit = { raw: string; authorization: string | undefined };
const hits: Hit[] = [];
const marker = join(work, "command-ran");
const reply = "touch " + marker + "\n";
const fileName = "held-note.txt";

function runIfConfirmed(command: string, confirm: boolean): void {
  if (confirm !== true) return;
  const child = spawn("/bin/sh", ["-c", command], { cwd: work, stdio: "ignore" });
  child.unref();
}

const server = createServer((req: IncomingMessage, res: ServerResponse) => {
  const chunks: Buffer[] = [];
  req.on("data", (chunk) => {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  });
  req.on("end", () => {
    hits.push({
      raw: Buffer.concat(chunks).toString("utf8"),
      authorization: typeof req.headers.authorization === "string" ? req.headers.authorization : undefined,
    });
    const payload = {
      choices: [{ message: { role: "assistant", content: reply } }],
    };
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(payload));
  });
});

const port = await new Promise<number>((resolve, reject) => {
  server.once("error", reject);
  server.listen(0, "127.0.0.1", () => {
    const address = server.address();
    if (!address || typeof address === "string") {
      reject(new Error("stub address"));
      return;
    }
    resolve(address.port);
  });
});
if (port === 8898 || port === 8899) fail("model stub used the daemon port");
const endpoint = `http://127.0.0.1:${port}/v1/chat/completions`;
const scratch = await mkdtemp(join(tmpdir(), "updated-note-hold-"));

try {
  async function held(label: string, state: Record<string, unknown>): Promise<void> {
    const beforeHits = hits.length;
    const beforeFetch = fetches;
    const decision = route(filter(state), allow);
    if (decision !== "hold-for-review") fail(label + " route allowed");
    const result = await draftNote({
      state,
      evaluation: allow,
      endpoint,
      model: endpoint,
      cwd: scratch,
      file: fileName,
    });
    if (result.decision !== "hold-for-review") fail(label + " was drafted");
    assertClass(result.modelClass, label);
    if (result.drafted || result.file !== null) fail(label + " wrote a draft");
    if (hits.length !== beforeHits || fetches !== beforeFetch) fail(label + " called the model");
    if (existsSync(join(scratch, fileName)) || existsSync(marker)) fail(label + " created a file");
    runIfConfirmed(reply, false);
    if (existsSync(marker)) fail(label + " ran a command");
    console.log("check-updated-note-hold: " + label + " held and the model was not called");
  }

  const pairing = noteOf(pairingPath);
  if (pairing.body !== fixtures.sendPairingCode.text) fail("stored pairing body is not the fixture ask");
  if (String(pairing.body).includes(old1)) fail("stored pairing body still has the old text");
  await held("pairing code", pairing);

  const hosts = noteOf(hostsPath);
  if (hosts.body !== fixtures.copyHosts.text) fail("stored hosts body is not the fixture ask");
  await held("hosts.json", hosts);

  const meshToken = filter({ text: fixtures.readMeshToken.text });
  if (route(meshToken, allow) !== "hold-for-review") fail("mesh token path was allowed");
  const meshBearer = filter({ text: fixtures.sendMeshBearer.text });
  if (route(meshBearer, allow) !== "hold-for-review") fail("mesh bearer was allowed");
  const plainSend = filter({ text: fixtures.sendMessage.text });
  if (plainSend.text !== "send a message") fail("plain send was altered");
  if (route(plainSend, allow) !== "allow-local-tool") fail("plain send was held");
  const clean = filter({ text: fixtures.summarizePaper.text });
  if (clean.text !== "summarize this paper") fail("clean paper was altered");
  if (route(clean, allow) !== "allow-local-tool") fail("clean paper was held");
  if (hits.length !== 0 || fetches !== 0) fail("an allow check called the model");
  console.log("check-updated-note-hold: plain send would allow a local tool");
  console.log("check-updated-note-hold: clean paper would allow a local tool");

  const paper = noteOf(paperPath);
  if (paper.body !== fixtures.summarizePaper.text) fail("stored paper body is not the fixture ask");
  if (String(paper.body).includes(old1) || String(paper.body).includes(old2)) {
    fail("stored paper body still has an old text");
  }
  if (route(filter(paper), allow) !== "allow-local-tool") fail("replaced paper was held");
  const drafted = await draftNote({
    state: paper,
    evaluation: allow,
    endpoint,
    model: "http://127.0.0.1:" + port + "/v1",
    cwd: work,
    file: fileName,
  });
  if (drafted.decision !== "allow-local-tool" || !drafted.drafted || drafted.file !== fileName) {
    fail("clean paper was not drafted");
  }
  assertClass(drafted.modelClass, "paper");
  if (drafted.modelClass !== "local") fail("loopback model was not class local");
  if (hits.length !== 1 || fetches !== 1) fail("clean paper did not call the model once");
  if (hits[0].authorization) fail("stub saw an authorization header");
  const posted = JSON.parse(hits[0].raw) as { model?: string; messages?: { content?: string }[] };
  if (!allowedClass.has(String(posted.model))) fail("stub saw model " + String(posted.model));
  if (posted.model !== "local") fail("stub model class is " + String(posted.model));
  const messages = JSON.stringify(posted.messages ?? []);
  if (!messages.includes(fixtures.summarizePaper.text)) fail("stub did not receive the new body");
  if (messages.includes(old1) || messages.includes(old2)) fail("stub received an old body");
  const draftPath = join(work, fileName);
  const info = statSync(draftPath);
  if (!info.isFile() || (info.mode & 0o777) !== 0o600) fail("draft mode is " + (info.mode & 0o777).toString(8));
  if (info.mode & 0o111) fail("draft file is executable");
  const body = readFileSync(draftPath, "utf8");
  if (body !== reply) fail("draft file is not the assistant text");
  const names = (await readdir(work)).filter((name) => name !== "command-ran").sort();
  if (names.length !== 1 || names[0] !== fileName) fail("session files are " + names.join(","));
  runIfConfirmed(body, false);
  if (existsSync(marker)) fail("unconfirmed command ran");
  if (existsSync(join(work, "command-ran"))) fail("held file was executed");
  const dumped = JSON.stringify(drafted);
  if (dumped.includes(endpoint) || dumped.includes("ai-gateway")) fail("draft result recorded an endpoint");
  console.log("check-updated-note-hold: stub received the new body");
  console.log("check-updated-note-hold: held file is one relative path mode 600");
  console.log("check-updated-note-hold: held file was not executed");
  console.log("check-updated-note-hold: command without confirm did not run");
} finally {
  globalThis.fetch = realFetch;
  await new Promise<void>((resolve, reject) => {
    server.close((err) => (err ? reject(err) : resolve()));
  });
  await rm(scratch, { recursive: true, force: true });
}
TS

env -u AI_GATEWAY_API_KEY \
  node --experimental-strip-types "$TH/prove.ts" \
  "$ROOT" "$TH/pairing.json" "$TH/hosts.json" "$TH/paper.json" "$WORK" "$OLD1" "$OLD2"

[ ! -e "$WORK/command-ran" ] || { echo "FAIL: unconfirmed command ran"; exit 1; }
[ -f "$WORK/held-note.txt" ] || { echo "FAIL: clean paper did not write the held file"; exit 1; }
held_mode="$(mode_of "$WORK/held-note.txt")"
[ "$held_mode" = "600" ] || { echo "FAIL: held file mode is $held_mode, want 600"; exit 1; }
[ "$(note_count)" = "2" ] || { echo "FAIL: draft changed the note count"; exit 1; }
cmp -s "$NOTE_FILE" "$TH/hosts.json" || { echo "FAIL: draft rewrote the hosts note"; exit 1; }
cmp -s "$NOTE2" "$TH/paper.json" || { echo "FAIL: draft rewrote the paper note"; exit 1; }
[ ! -d "$HOME_DIR/.mesh" ] || { echo "FAIL: daemon wrote under its home directory"; exit 1; }
if [ "$had_mesh" -eq 0 ] && [ -e "$MESH_MARK" ]; then
  echo "FAIL: wrote ~/.mesh"
  exit 1
fi

if grep -E -q 'supabase\.co|ai-gateway' "$LOG"; then
  echo "FAIL: daemon log records supabase.co or the AI gateway"
  exit 1
fi

if [ "$(uname -s)" = "Darwin" ]; then
  command -v lsof >/dev/null 2>&1 || { echo "FAIL: lsof is required on Darwin"; exit 1; }
  SRV_PID="$SRV" HOME_DIR="$HOME_DIR" STATE="$STATE" python3 - <<'PY'
import os, re, subprocess, sys
root = int(os.environ["SRV_PID"])

def run(args):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)

listed = run(["ps", "-ax", "-o", "pid=,ppid="])
if listed.returncode != 0 or not listed.stdout.strip():
    sys.exit("FAIL: could not list processes to check sockets")
by_ppid = {}
for line in listed.stdout.splitlines():
    parts = line.split()
    if len(parts) != 2:
        continue
    pid, ppid = int(parts[0]), int(parts[1])
    by_ppid.setdefault(ppid, []).append(pid)
pids, seen, stack = [], set(), [root]
while stack:
    cur = stack.pop()
    if cur in seen:
        continue
    seen.add(cur)
    pids.append(cur)
    stack.extend(by_ppid.get(cur, []))

env_text = run(["ps", "-wwE", "-p", str(root), "-o", "command="]).stdout
need = [
    "MESHD_TELEMETRY=off",
    "MESHD_HOST=127.0.0.1",
    "MESHD_PORT=8898",
    "HOME=" + os.environ["HOME_DIR"],
    "MESHD_STATE=" + os.environ["STATE"],
]
for item in need:
    if item not in env_text.split():
        sys.exit("FAIL: daemon env is missing " + item.split("=", 1)[0])

lsof = run(["lsof", "-nP", "-a", "-p", ",".join(str(p) for p in pids), "-iTCP"])
rows = []
for line in lsof.stdout.splitlines():
    match = re.search(r"\bTCP\s+(\S+)(?:\s+\(([^)]+)\))?\s*$", line)
    if match:
        rows.append(match.group(1))
if not rows:
    sys.exit("FAIL: could not see the daemon's TCP sockets")

def loopback(host):
    h = host.strip("[]").lower()
    if h.startswith("::ffff:"):
        h = h.split("::ffff:", 1)[1]
    return h in ("127.0.0.1", "::1", "localhost")

def remote_host(name):
    if "->" not in name:
        return None
    remote = name.split("->", 1)[1]
    if remote.startswith("["):
        end = remote.find("]")
        return remote[1:end] if end >= 0 else remote
    return remote.rsplit(":", 1)[0]

bad = []
for name in rows:
    host = remote_host(name)
    if host is None or loopback(host):
        continue
    bad.append(name)
if bad:
    sys.exit("FAIL: daemon has a non-loopback socket: %s" % ", ".join(bad))
PY
else
  SRV_PID="$SRV" HOME_DIR="$HOME_DIR" STATE="$STATE" python3 - <<'PY'
import os, sys
root = int(os.environ["SRV_PID"])

def descendants(pid):
    by_ppid = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            data = open(f"/proc/{name}/stat", "rb").read().decode(errors="replace")
        except OSError:
            continue
        r = data.rfind(")")
        parts = data[r + 2:].split()
        if len(parts) < 2:
            continue
        by_ppid.setdefault(int(parts[1]), []).append(int(name))
    out, stack = [], [pid]
    while stack:
        cur = stack.pop()
        out.append(cur)
        stack.extend(by_ppid.get(cur, []))
    return out

def inodes(pid):
    found = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fd_dir)
    except OSError:
        return found
    for name in names:
        try:
            target = os.readlink(f"{fd_dir}/{name}")
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            found.add(target[len("socket:["):-1])
    return found

def loopback(ip):
    if ip in ("00000000", "0100007F", "00000000000000000000000001000000"):
        return True
    if ip.endswith("0100007F") and "FFFF" in ip:
        return True
    return False

socks = set()
for pid in descendants(root):
    socks |= inodes(pid)

bad = []
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        parts = line.split()
        if len(parts) < 10 or parts[9] not in socks:
            continue
        remote_ip = parts[2].split(":")[0]
        if loopback(remote_ip):
            continue
        bad.append(parts[2])

env = {}
try:
    raw = open(f"/proc/{root}/environ", "rb").read().split(b"\0")
except OSError:
    raw = []
for item in raw:
    if b"=" not in item:
        continue
    key, value = item.split(b"=", 1)
    env[key.decode()] = value.decode()
need = {
    "MESHD_TELEMETRY": "off",
    "MESHD_HOST": "127.0.0.1",
    "MESHD_PORT": "8898",
    "HOME": os.environ["HOME_DIR"],
    "MESHD_STATE": os.environ["STATE"],
}
for key, value in need.items():
    if env.get(key) != value:
        sys.exit("FAIL: daemon env %s is not the spare value" % key)
if bad:
    sys.exit("FAIL: daemon has a non-loopback socket: %s" % ", ".join(bad))
PY
fi
echo "check-updated-note-hold: no supabase.co call"
echo "check-updated-note-hold: OK"

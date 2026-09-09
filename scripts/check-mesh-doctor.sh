#!/bin/sh
# doctor.ts self-check: the report's shape and the parts that don't depend on this
# machine's actual TCC state. (Whether input/screen are ok HERE varies by box; what
# must hold everywhere: all five checks present, token follows tokenSet, push never
# fails the machine, ok is the AND of the checks, and the routes answer correctly.)
# Runs against a throwaway HOME so it never touches ~/.mesh.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-doctor: SKIP (bun not installed)"; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$ROOT/install/payload/meshd"
HOME="$TMP" bun -e '
import { doctorReport, handleDoctor } from "./doctor.ts";

const info = { tokenSet: false, bind: "0.0.0.0", port: 8899, version: "test", mux: "rmux" };
const r = await doctorReport(false, info);

const want = ["token", "input", "screen", "mux", "push"];
for (const k of want) if (!r.checks[k]) throw new Error(`missing check: ${k}`);
if (r.checks.token.ok) throw new Error("tokenSet:false must fail the token check");
if (!r.checks.token.fix) throw new Error("a failing check must carry its fix");
if (!r.checks.push.ok) throw new Error("push is optional and must never fail the machine");
const and = Object.values(r.checks).every((c) => c.ok);
if (r.ok !== and) throw new Error("ok must be the AND of the checks");

const r2 = await doctorReport(false, { ...info, tokenSet: true });
if (!r2.checks.token.ok) throw new Error("tokenSet:true must pass the token check");

// Every failing check must tell the user what to do, not just that it is broken.
for (const [k, c] of Object.entries(r.checks)) {
  if (!c.ok && !c.fix) throw new Error(`failing check ${k} has no fix line`);
}

// Routes: GET /doctor answers, POST /doctor does not, /doctor/fix is POST-only.
const u = (p) => new URL("http://x" + p);
if (!(await handleDoctor(new Request("http://x/doctor"), u("/doctor"), info))) throw new Error("GET /doctor must answer");
if (await handleDoctor(new Request("http://x/doctor", { method: "POST" }), u("/doctor"), info)) throw new Error("POST /doctor must not answer");
if (await handleDoctor(new Request("http://x/doctor/fix"), u("/doctor/fix"), info)) throw new Error("GET /doctor/fix must not answer");
if (await handleDoctor(new Request("http://x/other"), u("/other"), info)) throw new Error("/other is not ours");
console.log("check-mesh-doctor: OK");
'

# Wiring: the route only exists if server.ts patched it in, and the capability list
# only tells the truth if it advertises it.
grep -q 'handleDoctor(req, url' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route /doctor"
  exit 1
}
grep -q '"doctor"' "$ROOT/install/payload/meshd/capabilities.ts" || {
  echo "FAIL: capabilities do not advertise doctor"
  exit 1
}
grep -q 'advertisedCapabilities' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: /health does not call advertisedCapabilities()"
  exit 1
}
echo "check-mesh-doctor: server.ts wired"

# The CLI side, which nothing tested and which was broken. `mesh doctor --fix` is the
# only thing that makes macOS raise the real Accessibility and Screen Recording dialogs
# — TCC only ever prompts from the process that wants the grant — so a --fix that
# quietly does a GET tells a new user to approve a permission nothing has asked for.
#
# It read the flag out of `flags`, but parse() only writes there for flags that TAKE a
# value; a bare --fix lands in `bools`. So `"fix" in flags` was always false from the
# command line, while the setup wizard's direct call with { fix: "" } worked — which is
# why it looked fine in the one place anybody exercised it.
#
# Asserted by watching which method actually arrives, not by reading the source.
CLI="$ROOT/install/payload/bin/mesh"
LOG="$TMP/methods.log"

# The stub needs a python. Hardcoding /usr/bin/python3 fails on any box that does not have
# one there — a minimal ubuntu image has no python at all — and a check that cannot run
# must say so, not fail as though the thing it tests were broken.
PY3=""
for c in python3 /usr/bin/python3; do command -v "$c" >/dev/null 2>&1 && { PY3="$c"; break; }; done
if [ -z "$PY3" ]; then
  echo "check-mesh-doctor: NOTE — CLI --fix case skipped, no python3 for the stub server"
  exit 0
fi

"$PY3" - "$TMP" <<'PY' 2>"$LOG" &
import http.server, socketserver, sys
class H(http.server.BaseHTTPRequestHandler):
    def _r(self):
        sys.stderr.write("%s %s\n" % (self.command, self.path)); sys.stderr.flush()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(b'{"ok":true,"checks":[],"total":0}')
    do_GET = do_POST = _r
    def log_message(self, *a): pass
socketserver.TCPServer(("127.0.0.1", 8893), H).serve_forever()
PY
STUB=$!
# A spin with no delay is not a wait. This burned all 40 attempts in milliseconds on a
# cold CI runner, long before python had bound the port — and then measured an empty log
# and reported the CLI as broken. Sleep between tries, and say so if it never comes up,
# rather than blaming the thing under test for the harness not being ready.
i=0
stub_up=0
while [ "$i" -lt 60 ]; do
  if curl -sf -m 1 "http://127.0.0.1:8893/doctor" >/dev/null 2>&1; then stub_up=1; break; fi
  sleep 0.2
  i=$((i + 1))
done
if [ "$stub_up" -ne 1 ]; then
  kill "$STUB" 2>/dev/null || true
  echo "FAIL: check-mesh-doctor: the stub server never came up on 127.0.0.1:8893 — harness problem, not a CLI problem"
  exit 1
fi

printf '{"default":"probe","hosts":{"probe":{"ip":"127.0.0.1","port":8893,"token":"t"}}}\n' \
  > "$TMP/hosts.json"
MESH_HOME="$TMP" bun "$CLI" doctor       >/dev/null 2>&1 || true
MESH_HOME="$TMP" bun "$CLI" doctor --fix >/dev/null 2>&1 || true
kill "$STUB" 2>/dev/null || true
wait "$STUB" 2>/dev/null || true

grep -q '^GET /doctor$' "$LOG" \
  || { echo "FAIL: check-mesh-doctor: plain \`mesh doctor\` did not GET /doctor (saw: $(tr '\n' ';' < "$LOG"))"; exit 1; }
grep -q '^POST /doctor/fix$' "$LOG" \
  || { echo "FAIL: check-mesh-doctor: \`mesh doctor --fix\` never reached POST /doctor/fix, so no permission dialog can appear (saw: $(tr '\n' ';' < "$LOG"))"; exit 1; }
echo "check-mesh-doctor: CLI --fix reaches POST /doctor/fix"

#!/bin/sh
# doctor.ts self-check: the report's shape and the parts that don't depend on this
# machine's actual TCC state. (Whether input/screen are ok HERE varies by box; what
# must hold everywhere: all five checks present, token follows tokenSet, push never
# fails the machine, ok is the AND of the checks, and the routes answer correctly.)
# Runs against a throwaway HOME so it never touches ~/.mesh.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
grep -q '"doctor"' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: capabilities do not advertise doctor"
  exit 1
}
echo "check-mesh-doctor: server.ts wired"

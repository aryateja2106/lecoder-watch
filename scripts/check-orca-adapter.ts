// Self-check for install/payload/meshd/orca.ts.
// Run: bun scripts/check-orca-adapter.ts
//
// Hermetic: ORCA_BIN points at a stub that replays real `orca --json` envelopes
// captured from Orca 1.4.180, so this passes on machines with no Orca installed.
// Then, if a real Orca runtime is reachable, it repeats the list against it.

import { mkdtempSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const dir = mkdtempSync(join(tmpdir(), "orca-stub-"));
const stub = join(dir, "orca");

// Captured verbatim from `orca terminal list --json` / `terminal read --json`.
writeFileSync(stub, `#!/bin/sh
case "$1 $2" in
"status --json"|"status "*)
  echo '{"id":"s","ok":true,"result":{"runtime":{"state":"ready","reachable":true}}}' ;;
"terminal list")
  echo '{"id":"l","ok":true,"result":{"terminals":[
    {"handle":"term_aaa","worktreePath":"","branch":"","title":"\\u2733 Claude Code","connected":true,"writable":true,"orphaned":false,"preview":"waiting"},
    {"handle":"term_bbb","worktreePath":"/Users/x/clients/abhishek/aqua-paisa","branch":"refs/heads/main","title":"..ek/aqua-paisa","connected":true,"writable":true,"orphaned":false,"preview":"$ codex"},
    {"handle":"term_ccc","worktreePath":"/tmp/dead","branch":"","title":"dead","connected":false,"writable":false,"orphaned":true,"preview":""}
  ],"totalCount":3}}' ;;
"terminal read")
  echo '{"id":"r","ok":true,"result":{"terminal":{"handle":"term_bbb","status":"running","tail":["line one","line two"],"nextCursor":"2"}}}' ;;
"terminal send")
  echo '{"id":"w","ok":true,"result":{"sent":true}}' ;;
*)
  echo '{"ok":false,"error":"unexpected"}' ; exit 1 ;;
esac
`);
chmodSync(stub, 0o755);
process.env.ORCA_BIN = stub;

const { isOrcaAgent, orcaAvailable, orcaSessions, orcaOutput, orcaSend } =
  await import("../install/payload/meshd/orca.ts");

function assert(cond: unknown, msg: string) {
  if (!cond) { console.error("FAIL:", msg); process.exit(1); }
}

assert(isOrcaAgent("orca:term_aaa"), "orca: prefix recognised");
assert(!isOrcaAgent("cmux:foo") && !isOrcaAgent("my-session"), "other sources untouched");
assert(await orcaAvailable(), "runtime reachable via stub");

const agents = await orcaSessions();
assert(agents.length === 2, `orphaned terminal dropped, got ${agents.length}`);

const [claude, codex] = agents;
assert(claude.name === "orca:term_aaa", `name: ${claude.name}`);
// No worktree → fall back to the title, with Orca's status glyph stripped.
assert(claude.title === "Claude Code", `title: ${JSON.stringify(claude.title)}`);
assert(claude.agentType === "claude", `agentType: ${claude.agentType}`);
assert(claude.attached === true, "connected maps to attached");
// A worktree path beats Orca's truncated "..ek/aqua-paisa" title on a 42mm screen.
assert(codex.title === "aqua-paisa", `title: ${JSON.stringify(codex.title)}`);
assert(codex.agentType === "codex", `agentType: ${codex.agentType}`);
assert(codex.orcaBranch === "main", `branch stripped of refs/heads/: ${codex.orcaBranch}`);
assert(codex.memMB === undefined && codex.cpuPct === undefined, "no fabricated process stats");

const out = await orcaOutput("orca:term_bbb", 2);
assert(out?.lines.length === 2 && out.lines[0] === "line one", `output: ${JSON.stringify(out)}`);
assert(out?.name === "orca:term_bbb", "output keeps the prefixed name");

assert((await orcaSend("orca:term_bbb", "continue\n")).ok, "send with trailing newline");
assert((await orcaSend("orca:term_bbb", undefined, "C-c")).ok, "interrupt maps to --interrupt");
const badKey = await orcaSend("orca:term_bbb", undefined, "F5");
assert(!badKey.ok && /does not support/.test(badKey.error ?? ""), "unsupported key rejected, not silently dropped");

// Absent binary must degrade to empty, never throw — a machine without Orca
// still has to serve /agents.
process.env.ORCA_BIN = join(dir, "definitely-not-here");
const cold = await import(`../install/payload/meshd/orca.ts?nocache=${Date.now()}`);
assert((await cold.orcaSessions()).length === 0, "missing orca yields no sessions");
assert((await cold.orcaAvailable()) === false, "missing orca is not available");
assert((await cold.orcaOutput("orca:x", 5)) === null, "missing orca yields null output");

console.log("check-orca-adapter: OK");

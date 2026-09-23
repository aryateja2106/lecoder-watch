#!/bin/sh
# Lossless session history (meshd sessions.ts) keeps every version of an agent transcript
# after the runtime compacts or deletes it, and gives any version back byte-for-byte.
# Runs the real module against a throwaway HOME — no daemon, no real transcripts touched:
#   - first snapshot is a full base; a grown file is stored as an append of only the new
#     bytes; an unchanged file stores nothing; a rewritten (compacted) file is a new base
#   - every version rebuilds byte-exact, and a tampered chunk is refused, not served
#   - the store is 0700, every file in it 0600 (transcripts carry pasted secrets)
#   - subagent transcripts (agent-*.jsonl) are not sessions; Codex rollouts are
#   - a second sweep over unchanged files records nothing; concurrent snapshots of one
#     file never share a version number
#   - restore writes a NEW session file next to the original with every sessionId
#     rewritten, leaves the original alone, and is refused for Codex
# Plus the wiring in server.ts: route, capability, boot sweep, Stop-event trigger.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/install/payload/meshd/server.ts"
MESH="$ROOT/install/payload/bin/mesh"
fail=0
bad() { echo "FAIL: $1"; fail=1; }

grep -q 'from "./sessions"' "$SERVER" || bad "server.ts does not import sessions.ts"
grep -q 'await handleSessions(req, url)' "$SERVER" || bad "/sessions routes are not dispatched"
grep -q '^startSessionSweep();' "$SERVER" || bad "the background sweep never starts"
grep -q '"pty", "sessions"\]' "$SERVER" || bad "capability sessions is not advertised"
grep -q 'snapshotTranscript(p!)' "$SERVER" || bad "a finished turn no longer snapshots its session"
grep -q 'case "sessions": return cmdSessions' "$MESH" || bad "mesh sessions is not wired"

command -v bun >/dev/null 2>&1 || { echo "check-session-snapshots: SKIP (no bun)"; [ "$fail" = 0 ] && exit 0 || exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/sess-check.XXXXXX")"
trap 'rm -rf "$T"' EXIT
cat > "$T/run.ts" <<'TS'
import { mkdirSync, writeFileSync, appendFileSync, readFileSync, statSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
const HOME = process.env.HOME!;
const { snapshot, reconstruct, sweep, handleSessions } = await import(process.env.MODULE!);
let bad = 0;
const ok = (c: boolean, msg: string) => { if (!c) { console.log("FAIL: " + msg); bad = 1; } };
const eq = (a: Uint8Array | null, b: Buffer) => !!a && Buffer.compare(Buffer.from(a), b) === 0;

const id = "11111111-2222-4333-8444-555555555555";
const proj = join(HOME, ".claude/projects/-tmp-demo");
mkdirSync(proj, { recursive: true });
const file = join(proj, `${id}.jsonl`);
const line = (o: object) => JSON.stringify(o) + "\n";
writeFileSync(file, line({ type: "user", sessionId: id, cwd: "/tmp/demo", message: { content: "fix the flaky test" } }));
const v1 = readFileSync(file);
ok(await snapshot(file) === "base", "first snapshot is not a base");
ok(await snapshot(file) === "unchanged", "an unchanged file was stored again");
appendFileSync(file, line({ type: "assistant", sessionId: id, message: { content: "x".repeat(50_000) } }));
const v2 = readFileSync(file);
ok(await snapshot(file) === "append", "a grown file was not stored as an append");
const gz2 = statSync(join(HOME, ".mesh/sessions/claude", id, "v2.gz")).size;
ok(gz2 < v2.length / 4, `the append stored ${gz2} bytes for a ${v2.length}-byte file — it copied, not appended`);
// Compaction: the runtime rewrites the file shorter.
writeFileSync(file, line({ type: "summary", sessionId: id, summary: "compacted" }));
const v3 = readFileSync(file);
ok(await snapshot(file) === "base", "a rewritten (compacted) file was not a new base");
ok(eq(await reconstruct("claude", id, 1), v1), "v1 does not rebuild byte-exact");
ok(eq(await reconstruct("claude", id, 2), v2), "v2 (base + append) does not rebuild byte-exact");
ok(eq(await reconstruct("claude", id), v3), "latest does not rebuild byte-exact");

// Concurrent writers (Stop-event trigger + sweep) must not share a version number.
const race = join(proj, "22222222-2222-4333-8444-555555555555.jsonl");
writeFileSync(race, line({ type: "user", message: { content: "race" } }));
const pending = [];
for (let i = 0; i < 80; i++) { pending.push(snapshot(race)); await Bun.sleep(1); appendFileSync(race, line({ i, pad: "z".repeat(200_000) })); }
await Promise.all(pending);
await snapshot(race);
const raceVersions = JSON.parse(readFileSync(join(HOME, ".mesh/sessions/claude/22222222-2222-4333-8444-555555555555/index.json"), "utf8")).versions;
ok(new Set(raceVersions.map((v: any) => v.n)).size === raceVersions.length, "two concurrent snapshots recorded the same version number");
for (const v of raceVersions) ok(!!(await reconstruct("claude", "22222222-2222-4333-8444-555555555555", v.n)), `concurrent snapshots left v${v.n} unreadable`);

const dir = join(HOME, ".mesh/sessions/claude", id);
ok((statSync(join(HOME, ".mesh/sessions")).mode & 0o777) === 0o700, "the store is not 0700");
ok((statSync(dir).mode & 0o777) === 0o700, "a session folder is not 0700");
for (const f of readdirSync(dir)) ok((statSync(join(dir, f)).mode & 0o777) === 0o600, `${f} is not 0600`);

writeFileSync(join(proj, "agent-abc.jsonl"), line({ type: "user", message: { content: "sub" } }));
ok(await snapshot(join(proj, "agent-abc.jsonl")) === "skipped", "a subagent transcript was recorded as a session");
const cx = join(HOME, ".codex/sessions/2026/09/23");
mkdirSync(cx, { recursive: true });
writeFileSync(join(cx, "rollout-2026-09-23T10-00-00-abc.jsonl"), line({ type: "session_meta", payload: { cwd: "/tmp/cx" } }));

const first = await sweep();
ok(first.recorded === 1, `first sweep recorded ${first.recorded}, expected only the new Codex rollout`);
const again = await sweep();
ok(again.recorded === 0, `a sweep over unchanged files recorded ${again.recorded}`);

const req = (m: string, p: string) => handleSessions(new Request("http://x" + p, { method: m }), new URL("http://x" + p));
const list = await (await req("GET", "/sessions"))!.json();
ok(list.sessions.length === 3, `GET /sessions listed ${list.sessions.length}, expected 3`);
const claudeRow = list.sessions.find((s: any) => s.id === id);
ok(claudeRow?.title === "fix the flaky test" && claudeRow?.cwd === "/tmp/demo", "title/cwd not read from the transcript head");
ok(eq(new Uint8Array(await (await req("GET", `/sessions/claude/${id}/raw?v=2`))!.arrayBuffer()), v2), "GET raw?v=2 is not byte-exact");

const r = await req("POST", `/sessions/claude/${id}/restore?v=2`);
ok(r!.status === 201, `restore answered ${r!.status}`);
const restored = await r!.json();
const text = readFileSync(restored.path, "utf8");
ok(restored.path.startsWith(proj + "/") && existsSync(restored.path), "restore did not land next to the original");
ok(!text.includes(id) && text.includes(`"sessionId":"${restored.id}"`), "restored file still carries the old sessionId");
ok(restored.resume === `claude --resume ${restored.id}`, "restore did not say how to resume");
ok(Buffer.compare(readFileSync(file), v3) === 0, "restore touched the original transcript");
const cxId = list.sessions.find((s: any) => s.runtime === "codex").id;
ok((await req("POST", `/sessions/codex/${cxId}/restore`))!.status === 400, "Codex restore was not refused");

// Tamper: flip a byte inside the stored append — reconstruct must refuse, not serve it.
const p2 = join(dir, "v2.gz");
const { gzipSync, gunzipSync } = await import("node:zlib");
const raw = gunzipSync(readFileSync(p2)); raw[10] ^= 1; writeFileSync(p2, gzipSync(raw));
ok(await reconstruct("claude", id, 2) === null, "a tampered version was served");
ok((await req("GET", `/sessions/claude/${id}/raw?v=2`))!.status === 404, "GET raw served a tampered version");
process.exit(bad);
TS
HOME="$T/home" MODULE="$ROOT/install/payload/meshd/sessions.ts" MESH_SESSIONS_DIR="$T/home/.mesh/sessions" bun "$T/run.ts" || fail=1

[ "$fail" = 0 ] && echo "check-session-snapshots: OK" || exit 1

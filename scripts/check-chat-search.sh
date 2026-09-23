#!/bin/sh
# Chat search (meshd chats.ts) finds a past conversation by what was said in it, on this
# machine and every peer, and plans how to start it again.
# Runs the real modules against a throwaway HOME — no daemon, no real transcripts touched:
#   - only what the person typed and the agent answered is indexed: no isMeta, sidechain,
#     wrapper (<system-reminder>, <command-name>…), thinking, tool_use or tool_result text;
#     Codex drops developer messages, commentary, <environment>/AGENTS.md/Files-mentioned
#     parts and keeps only the ask after "## My request for Codex:"
#   - title: a custom-title / ai-title record, else the first kept user text
#   - a Codex subagent rollout (even a fork that repeats its parent's meta) is hidden
#     unless all=1
#   - secrets are masked in excerpts and titles, including one learned after indexing
#   - an append indexes only its new messages; a line cut by a version boundary is carried
#     and indexed once it is complete, exactly once; a compaction base replaces the rows
#   - resume plans a validated `claude --resume` / `codex resume`, falls back to HOME when
#     the folder is gone, refuses a malformed id, and restores a deleted Claude transcript
#     first (planning its new id)
#   - federation asks every hosts.json peer with its own token and federate=0, tags rows
#     with the peer's name and names the peer that did not answer
#   - the index is 0600, and MESH_SESSIONS=off indexes nothing
# Plus the wiring in server.ts and sessions.ts: capability, routes, hooks, mirror allowlist.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/install/payload/meshd/server.ts"
SESS="$ROOT/install/payload/meshd/sessions.ts"
fail=0
bad() { echo "FAIL: $1"; fail=1; }

grep -q '^const CAPABILITIES = .*"chatSearch"' "$SERVER" || bad "capability chatSearch is not advertised"
grep -q 'from "./chats"' "$SESS" || bad "sessions.ts does not import chats.ts"
grep -q '"/sessions/search" && req.method === "GET") return Response.json(await searchRoute(url.searchParams))' "$SESS" || bad "GET /sessions/search is not routed"
grep -q '/resume\$/);' "$SESS" && grep -q 'return resumePlan(' "$SESS" || bad "POST /sessions/:runtime/:id/resume is not routed"
grep -q 'indexSession(index.runtime, index.id).catch' "$SESS" || bad "a recorded version is no longer indexed"
grep -q 'sweep().then(() => catchUp())' "$SESS" || bad "the first sweep no longer catches the index up"
grep -A1 'const readable = ' "$SESS" | grep -qE '/sessions/search|resume' && bad "the mirror token's allowlist grew to search or resume"

command -v bun >/dev/null 2>&1 || { echo "check-chat-search: SKIP (no bun)"; [ "$fail" = 0 ] && exit 0 || exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/chat-check.XXXXXX")"
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
cat > "$T/run.ts" <<'TS'
import { mkdirSync, writeFileSync, appendFileSync, readFileSync, statSync, existsSync, rmSync, unlinkSync, readdirSync, chmodSync } from "node:fs";
import { join } from "node:path";
import { hostname } from "node:os";
import { gzipSync } from "node:zlib";
import { Database } from "bun:sqlite";
const HOME = process.env.HOME!;
const M = process.env.MESHD!;
const { snapshot, sweep, handleSessions } = await import(`${M}/sessions.ts`);
const { indexSession, catchUp, search } = await import(`${M}/chats.ts`);
const { addKnownSecrets } = await import(`${M}/redact.ts`);
let bad = 0;
const ok = (c: boolean, msg: string) => { if (!c) { console.log("FAIL: " + msg); bad = 1; } };
const line = (o: object) => JSON.stringify(o) + "\n";
const DB = join(HOME, ".mesh/chats.sqlite");
const req = (m: string, p: string) => handleSessions(new Request("http://x" + p, { method: m }), new URL("http://x" + p));
const find = (q: string, all = false) => search({ q, all }) as any[];
let rodb: Database | null = null;
const rows = (id: string) => ((rodb ??= new Database(DB, { readonly: true })).query("SELECT count(*) AS c FROM chat_messages WHERE id=?").get(id) as any).c as number;
const drain = () => indexSession("claude", "nothing");  // the index queue is one chain: this waits for it

// ---- MESH_SESSIONS=off: a session already in the store (written by hand, as an older meshd would) is not indexed.
const OLD = "99999999-2222-4333-8444-555555555555";
const oldDir = join(HOME, ".mesh/sessions/claude", OLD);
mkdirSync(oldDir, { recursive: true });
const oldBody = Buffer.from(line({ type: "user", cwd: "/nowhere", timestamp: "2026-01-01T00:00:00Z", message: { content: "an old conversation about marmalade" } }));
writeFileSync(join(oldDir, "v1.gz"), gzipSync(oldBody));
writeFileSync(join(oldDir, "index.json"), JSON.stringify({ runtime: "claude", id: OLD, source: "/nowhere/x.jsonl", cwd: "/nowhere", title: null,
  versions: [{ n: 1, kind: "base", size: oldBody.length, sha256: "x", mtimeMs: 0, ts: "2026-01-01T00:00:00Z" }] }));
process.env.MESH_SESSIONS = "off";
ok(await catchUp() === 0 && await indexSession("claude", OLD) === 0, "MESH_SESSIONS=off still indexed a session");
ok(!existsSync(DB), "MESH_SESSIONS=off still created the chat index");
delete process.env.MESH_SESSIONS;
ok(await catchUp() === 1, "catchUp did not index a session stored before the index existed");
ok(find("marmalade")[0]?.id === OLD, "catchUp's session is not searchable");
ok(await catchUp() === 0, "catchUp re-indexed a current index");

// ---- fixtures
const A = "aaaaaaaa-1111-4111-8111-111111111111", B = "bbbbbbbb-1111-4111-8111-111111111111";
const C = "cccccccc-1111-4111-8111-111111111111", G = "dddddddd-1111-4111-8111-111111111111";
const DU = "019a0000-0000-7000-8000-00000000000d", EU = "019a0000-0000-7000-8000-00000000000e";
const proj = join(HOME, ".claude/projects/-work-voice");
mkdirSync(proj, { recursive: true });
const work = (n: string) => { const d = join(HOME, "work", n); mkdirSync(d, { recursive: true }); return d; };
const cwdA = work("voice"), cwdB = work("billing"), cwdD = work("screener");
const ts = (s: number) => `2026-09-2${s}T10:00:00.000Z`;
const u = (id: string, cwd: string, content: any, extra: object = {}) => line({ type: "user", sessionId: id, cwd, timestamp: ts(0), message: { role: "user", content }, ...extra });
const a = (id: string, cwd: string, content: any, extra: object = {}) => line({ type: "assistant", sessionId: id, cwd, timestamp: ts(1), message: { role: "assistant", content }, ...extra });
const secret = "ghp_" + "Z9y8X7w6V5u4T3s2R1q0P9o8N7m6L5k4J3i2";

const fileA = join(proj, `${A}.jsonl`);
writeFileSync(fileA,
  u(A, cwdA, "Caveat: zebra meta noise", { isMeta: true })
  + u(A, cwdA, "<command-name>/clear</command-name> wrapperword")
  + u(A, cwdA, [{ type: "text", text: "<system-reminder>sysword</system-reminder>" }])
  + u(A, cwdA, [{ type: "text", text: "the voice input keeps dropping words" }])
  + a(A, cwdA, [{ type: "thinking", thinking: "thinkword" }, { type: "tool_use", id: "t1", name: "Bash", input: { command: "tooluseword" } }])
  + u(A, cwdA, [{ type: "tool_result", tool_use_id: "t1", content: "toolresultword" }])
  + a(A, cwdA, [{ type: "text", text: "The recognizer restarts on every partial result, so voice input loses the tail." }])
  + a(A, cwdA, [{ type: "text", text: "sidechainword from a side agent" }], { isSidechain: true })
  + u(A, cwdA, [{ type: "image", source: { type: "base64", data: "aW1hZ2V3b3Jk" } }, { type: "text", text: "see the screenshot captionword" }])
  + line({ type: "ai-title", sessionId: A, aiTitle: "Fix voice input dropouts" }));
writeFileSync(join(proj, `${B}.jsonl`),
  u(B, cwdB, "refactor the billing module")
  + line({ type: "custom-title", sessionId: B, customTitle: "Billing refactor" })
  + a(B, cwdB, [{ type: "text", text: "done, the billing module is split in two" }]));
writeFileSync(join(proj, `${C}.jsonl`),
  u(C, join(HOME, "work/onboarding"), "<command-message>init</command-message>")
  + u(C, join(HOME, "work/onboarding"), "  make   the\n onboarding   faster  ")
  + a(C, join(HOME, "work/onboarding"), [{ type: "text", text: "onboarding now skips the tour" }]));
writeFileSync(join(proj, `${G}.jsonl`), u(G, cwdA, `rotate ${secret} deploykey now`));

const cx = join(HOME, ".codex/sessions/2026/09/20");
mkdirSync(cx, { recursive: true });
const DID = `rollout-2026-09-20T10-00-00-${DU}`, EID = `rollout-2026-09-20T11-00-00-${EU}`;
const msg = (role: string, parts: string[], extra: object = {}) => line({ timestamp: ts(2), type: "response_item",
  payload: { type: "message", role, content: parts.map((text) => ({ type: role === "assistant" ? "output_text" : "input_text", text })), ...extra } });
writeFileSync(join(cx, `${DID}.jsonl`),
  line({ timestamp: ts(2), type: "session_meta", payload: { id: DU, cwd: cwdD, source: "vscode", thread_source: "user" } })
  + msg("developer", ["devword instructions"])
  + msg("user", ["<environment_context>envword</environment_context>", "# AGENTS.md instructions for /x\nagentsword",
      "# Files mentioned by the user:\n\n## a.pdf: /x\n\n## My request for Codex:\nsummarise the screener results"])
  + msg("user", ["# Files mentioned by the user:\n## b.txt: /y\nfilesword"])
  + msg("assistant", ["I am looking at commentaryword first"], { phase: "commentary" })
  + msg("assistant", ["The screener flagged three tickers finalword"], { phase: "final_answer" }));
writeFileSync(join(cx, `${EID}.jsonl`),
  line({ timestamp: ts(3), type: "session_meta", payload: { id: EU, cwd: cwdD, source: { subagent: { thread_spawn: { parent_thread_id: DU, depth: 1 } } }, parent_thread_id: DU, forked_from_id: DU, thread_source: "subagent" } })
  + line({ timestamp: ts(3), type: "session_meta", payload: { id: DU, cwd: cwdD, source: "vscode", thread_source: "user" } })
  + msg("user", ["review the screener subagentword"])
  + msg("assistant", ["subagent verdict: fine"], { phase: "final_answer" }));

await sweep();
await drain();

// ---- extraction
const hitA = find("voice input");
ok(hitA.length === 1 && hitA[0].id === A, `"voice input" should find exactly session A, found ${JSON.stringify(hitA.map((r) => r.id))}`);
ok(hitA[0]?.title === "Fix voice input dropouts", `ai-title did not win: ${hitA[0]?.title}`);
ok(hitA[0]?.excerpts?.length === 2 && hitA[0].excerpts.every((e: any) => /«voice» «input»/.test(e.text)), `excerpts do not mark the match: ${JSON.stringify(hitA[0]?.excerpts)}`);
ok(hitA[0]?.cwd === cwdA && hitA[0]?.cwdExists === true && hitA[0]?.live === true && hitA[0]?.kind === "user" && hitA[0]?.shortId === A, "row fields (cwd/cwdExists/live/kind/shortId) wrong for A");
ok(find("voic")[0]?.id === A, "the last term is not a prefix (search-as-you-type)");
ok(find("captionword")[0]?.id === A, "the text part next to an image was dropped");
for (const w of ["zebra", "wrapperword", "sysword", "thinkword", "tooluseword", "toolresultword", "sidechainword", "aW1hZ2V3b3Jk",
  "devword", "envword", "agentsword", "filesword", "commentaryword", "Files", "AGENTS"])
  ok(find(w, true).length === 0, `"${w}" was indexed but is not conversation`);
ok(find("billing")[0]?.title === "Billing refactor", "custom-title did not win");
ok(find("tour")[0]?.title === "make the onboarding faster", `first-user-text title wrong: ${find("tour")[0]?.title}`);
const d = find("screener");
ok(d.length === 1 && d[0].id === DID && d[0].shortId === DU && d[0].runtime === "codex", `Codex row wrong: ${JSON.stringify(d.map((r) => [r.id, r.shortId]))}`);
ok(d[0]?.title === "summarise the screener results" && d[0]?.cwd === cwdD, `Codex title/cwd wrong: ${d[0]?.title} / ${d[0]?.cwd}`);
ok(find("finalword").length === 1, "a Codex final answer was not indexed");

// ---- subagents hidden unless all
ok(find("subagentword").length === 0, "a Codex subagent rollout is listed without all=1");
const sub = find("subagentword", true);
ok(sub.length === 1 && sub[0].id === EID && sub[0].kind === "subagent", "all=1 does not show the subagent rollout (or its kind is wrong)");

// ---- redaction
const g = find("deploykey")[0];
ok(!!g && !JSON.stringify(g).includes(secret) && g.excerpts[0].text.includes("ghp_••••••") && g.title.includes("ghp_••••••"), `a ghp_ token leaked: ${JSON.stringify(g)}`);
const late = "zqxmeshpeertoken0123456789";
appendFileSync(fileA, u(A, cwdA, `the lighthouse token is ${late} ok`));
await snapshot(fileA); await drain();
addKnownSecrets([["hosts.json", late]]);  // learned after it was indexed: only the way out can hide it
const lh = find("lighthouse")[0];
ok(!!lh && !JSON.stringify(lh).includes(late) && lh.excerpts[0].text.includes("••••••"), `a secret learned after indexing leaked in an excerpt: ${lh?.excerpts?.[0]?.text}`);

// ---- incremental: an append adds only its messages; a cut line is carried, then indexed once
const before = rows(A);
appendFileSync(fileA, u(A, cwdA, "second question about latency") + a(A, cwdA, [{ type: "text", text: "latency answer" }]));
ok(await snapshot(fileA) === "append", "the append was not stored as an append");
await drain();
ok(rows(A) === before + 2, `an append of 2 messages changed A's rows by ${rows(A) - before}`);
const cut = u(A, cwdA, "the kumquat question arrives in two halves");
appendFileSync(fileA, a(A, cwdA, [{ type: "text", text: "whole line first" }]) + cut.slice(0, 40));
ok(await snapshot(fileA) === "append", "the half-line append was not stored");
await drain();
ok(rows(A) === before + 3 && find("kumquat").length === 0, "a half-written line was indexed before it was complete");
appendFileSync(fileA, cut.slice(40));
await snapshot(fileA); await drain();
ok(find("kumquat")[0]?.id === A, "the carried line was never indexed once completed");
ok(rows(A) === before + 4, `the completed line was indexed ${rows(A) - before - 3} times`);

// ---- compaction: a new base replaces the session's rows
writeFileSync(join(proj, `${B}.jsonl`), line({ type: "summary", summary: "compacted" }) + u(B, cwdB, "after compaction: pineapple"));
ok(await snapshot(join(proj, `${B}.jsonl`)) === "base", "the rewrite was not a new base");
await drain();
ok(rows(B) === 1 && find("billing").length === 0 && find("pineapple")[0]?.id === B, `a compaction base did not replace B's rows (${rows(B)} rows)`);

// ---- resume plans
const plan = async (p: string) => { const r = await req("POST", p); return { status: r!.status, body: await r!.json() as any }; };
let p = await plan(`/sessions/claude/${A}/resume`);
ok(p.status === 200 && p.body.cmd.startsWith(`claude --resume ${A} || `) && p.body.cwd === cwdA && p.body.cwdMissing === false && p.body.name === `resume-${A.slice(-8)}` && !("restoredFrom" in p.body), `Claude plan wrong: ${JSON.stringify(p)}`);
ok((await import(`${M}/sessions.ts`)).resumedTranscript(p.body.name) === join(proj, `${A}.jsonl`), "the plan did not tell the chat view which transcript the pane resumes");
p = await plan(`/sessions/codex/${DID}/resume`);
ok(p.status === 200 && p.body.cmd.startsWith(`codex resume ${DU} || `) && p.body.cwd === cwdD && p.body.name === `resume-${DU.slice(-8)}`, `Codex plan wrong: ${JSON.stringify(p)}`);
rmSync(cwdB, { recursive: true });
p = await plan(`/sessions/claude/${B}/resume`);
ok(p.body.cwd === HOME && p.body.cwdMissing === true, `a missing folder did not fall back to HOME: ${JSON.stringify(p.body)}`);
ok(find("pineapple")[0]?.cwdExists === false, "cwdExists still true for a deleted folder");
ok(p.body.cmd.endsWith('exec "${SHELL:-/bin/sh}"; }'), `a failing CLI would close its pane: ${p.body.cmd}`);
const savedPath = process.env.PATH; process.env.PATH = "/nonexistent";
const noCli = await plan(`/sessions/codex/${DID}/resume`);
process.env.PATH = savedPath;
ok(noCli.status === 424 && /codex is not installed/.test(noCli.body.error ?? ""), `a machine without codex still planned a resume: ${JSON.stringify(noCli)}`);
for (const bogus of ["/sessions/claude/not-a-uuid/resume", `/sessions/claude/${A}%3Brm%20-rf/resume`, "/sessions/codex/rollout-2026-09-20T10-00-00-abc/resume", `/sessions/codex/${DU}/resume`])
  ok((await plan(bogus)).status === 400, `a malformed id was not refused: ${bogus}`);
ok((await plan(`/sessions/claude/${"e".repeat(8)}-1111-4111-8111-111111111111/resume`)).status === 404, "an unknown session did not 404");
unlinkSync(join(proj, `${C}.jsonl`));
ok(find("tour")[0]?.live === false, "live still true after the runtime deleted the transcript");
p = await plan(`/sessions/claude/${C}/resume`);
const newId = /^claude --resume ([0-9a-f-]{36}) \|\| /.exec(p.body.cmd ?? "")?.[1];
ok(p.status === 200 && p.body.restoredFrom === C && !!newId && newId !== C && p.body.name === `resume-${newId!.slice(-8)}`, `restore-then-plan wrong: ${JSON.stringify(p.body)}`);
ok(!!newId && readFileSync(join(proj, `${newId}.jsonl`), "utf8").includes(`"sessionId":"${newId}"`), "the restored transcript is not where claude --resume looks");
const again = await plan(`/sessions/claude/${C}/resume`);
ok(again.body.name === p.body.name && again.body.cmd === p.body.cmd, "resuming a deleted session twice restored two copies");
ok(!("restoredFrom" in again.body), "a second resume claimed it restored again");
ok(readdirSync(proj).filter((f) => f.endsWith(".jsonl") && f.startsWith(newId!.slice(0, 8))).length === 1, "a second restore wrote another file");
unlinkSync(join(cx, `${DID}.jsonl`));
ok((await plan(`/sessions/codex/${DID}/resume`)).status === 410, "a deleted Codex rollout was planned anyway");

// ---- federation over two peers, each with its own token
const seen: Record<string, string[]> = { alpha: [], beta: [] };
const peer = (name: string, token: string) => Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: async (q) => {
  const url = new URL(q.url);
  seen[name].push(url.search);
  if (q.headers.get("authorization") !== `Bearer ${token}`) return new Response("unauthorized", { status: 401 });
  return (await handleSessions(q, url)) ?? new Response("no", { status: 404 });
} });
const pa = peer("alpha", "alpha-token-0123456789"), pb = peer("beta", "beta-token-0123456789");
const dead = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: () => new Response("") }); const deadPort = dead.port; dead.stop(true);
writeFileSync(join(HOME, ".mesh/hosts.json"), JSON.stringify({ hosts: {
  alpha: { ip: "localhost", port: pa.port, token: "alpha-token-0123456789" },
  beta: { ip: "localhost", port: pb.port, token: "beta-token-0123456789" },
  gone: { ip: "localhost", port: deadPort, token: "gone-token-0123456789" },
  me: { ip: "127.0.0.1", port: pa.port, token: "x" } } }));
const fed = await (await req("GET", "/sessions/search?q=screener"))!.json() as any;
const hosts = fed.results.map((r: any) => r.host).sort();
const me = "me";  // this machine is named by its hosts.json entry, so `mesh -H` can take it back
ok(JSON.stringify(hosts) === JSON.stringify(["alpha", "beta", me].sort()), `federated rows are not tagged by host: ${JSON.stringify(hosts)}`);
const peerOk = Object.fromEntries(fed.peers.map((x: any) => [x.host, x.ok]));
ok(peerOk.alpha === true && peerOk.beta === true && peerOk.gone === false && !("me" in peerOk), `peers wrong: ${JSON.stringify(fed.peers)}`);
ok(seen.alpha.length === 1 && seen.beta.length === 1 && seen.alpha.every((s) => s.includes("federate=0")), `peers were not asked exactly once with federate=0: ${JSON.stringify(seen)}`);
ok(fed.results.every((r: any, i: number, all: any[]) => i === 0 || all[i - 1].score <= r.score), "merged rows are not ordered by score");
const local = await (await req("GET", "/sessions/search?q=screener&federate=0"))!.json() as any;
ok(local.results.length === 1 && local.results[0].host === me && local.peers.length === 0, "federate=0 still fanned out");
pa.stop(true); pb.stop(true);

// ---- hostile inputs: a NUL query, a broken hosts.json, an unreadable cwd
ok(Array.isArray(find("\u0000")) && find("\u0000").length === 0, "a NUL query did not come back empty");
writeFileSync(join(HOME, ".mesh/hosts.json"), "{ not json");
const broken = await req("GET", "/sessions/search?q=screener");
ok(broken!.status === 200 && ((await broken!.json()) as any).results.length === 1, "a broken hosts.json cost the local results");
const locked = join(HOME, "locked"); mkdirSync(join(locked, "inner"), { recursive: true });
const L = "1d1d1d1d-1111-4111-8111-111111111111";
writeFileSync(join(proj, `${L}.jsonl`), u(L, join(locked, "inner"), "quokka in a locked folder"));
await snapshot(join(proj, `${L}.jsonl`)); await drain();
chmodSync(locked, 0o000);
let lockedRes: Response | null = null;
try { lockedRes = await req("GET", "/sessions/search?q=quokka&federate=0"); } catch {} finally { chmodSync(locked, 0o700); }
ok(lockedRes?.status === 200 && ((await lockedRes!.json()) as any).results[0]?.cwdExists === false, "an unreadable cwd broke the search");

// ---- a secret learned after indexing, spanning several FTS tokens, stays hidden in every excerpt
const Sx = "2e2e2e2e-1111-4111-8111-111111111111";
const spanning = "Qw3rTy-uIoP_aSdF-gHjK_lZxC-vBnM_1234";
writeFileSync(join(proj, `${Sx}.jsonl`), u(Sx, cwdA, `paste this key ${spanning} into the lighthouse config`));
await snapshot(join(proj, `${Sx}.jsonl`)); await drain();
addKnownSecrets([["spanning", spanning]]);
for (const q of ["lighthouse", "gHjK", "aSdF"]) ok(!find(q).some((r) => r.excerpts.some((e: any) => /gHjK|aSdF|lZxC/.test(e.text.replace(/[«»]/g, "")))), `a multi-token secret leaked through q=${q}`);

// ---- a store rebuilt from scratch (deleted to free space) is re-indexed, not trusted
const Rb = "3f3f3f3f-1111-4111-8111-111111111111";
writeFileSync(join(proj, `${Rb}.jsonl`), u(Rb, cwdA, "tangerine one") + u(Rb, cwdA, "tangerine two"));
await snapshot(join(proj, `${Rb}.jsonl`));
appendFileSync(join(proj, `${Rb}.jsonl`), u(Rb, cwdA, "tangerine three"));
await snapshot(join(proj, `${Rb}.jsonl`)); await drain();
rmSync(join(HOME, ".mesh/sessions/claude", Rb), { recursive: true });
writeFileSync(join(proj, `${Rb}.jsonl`), u(Rb, cwdA, "persimmon only"));
await snapshot(join(proj, `${Rb}.jsonl`));
appendFileSync(join(proj, `${Rb}.jsonl`), u(Rb, cwdA, "persimmon again"));
await snapshot(join(proj, `${Rb}.jsonl`)); await drain();
ok(find("persimmon")[0]?.id === Rb && find("tangerine").length === 0, "a rebuilt store kept the old rows or missed the new ones");

// ---- the index file
ok((statSync(DB).mode & 0o777) === 0o600, "chats.sqlite is not 0600");
for (const f of [`${DB}-wal`, `${DB}-shm`]) if (existsSync(f)) ok((statSync(f).mode & 0o777) === 0o600, `${f} is not 0600`);
process.exit(bad);
TS
HOME="$T/home" MESHD="$ROOT/install/payload/meshd" MESH_SESSIONS_DIR="$T/home/.mesh/sessions" bun "$T/run.ts" || fail=1

[ "$fail" = 0 ] && echo "check-chat-search: OK" || exit 1

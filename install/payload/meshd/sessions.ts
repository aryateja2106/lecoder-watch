// sessions.ts — lossless version history for agent transcripts on this machine: every Claude Code and Codex session is snapshotted before compaction or cleanup can destroy it, and any version can be read back or restored as a new resumable session.
//
// Why this exists: an agent's transcript is a JSONL file its runtime rewrites when it
// compacts and deletes after 30 days (Claude Code's default cleanupPeriodDays), so "the
// conversation that finally cracked the bug" disappears. agent-git (github.com/Einsia/
// agent-git) solves the same problem but records versions only through its hosted hub,
// with usage statistics that cannot be turned off there; this keeps every byte on the
// machine that produced it.
//
// Storage, per session, under ~/.mesh/sessions/<runtime>/<id>/ (0700, files 0600):
//   index.json   the version list
//   v<N>.gz      version N — either a full BASE, or an APPEND holding only the bytes that
//                were added after version N-1
// Transcripts are append-mostly and large (138 MB for one long Claude session, measured
// 2026-09-23), so a full copy per turn — what a plain git commit would store until a gc —
// is gigabytes an hour. A version is an append when the file's first <previous size> bytes
// still hash to the previous version; anything else (compaction, a rewrite) is a new base.
//
//   GET  /sessions                          newest first: runtime, id, cwd, title, versions
//   GET  /sessions/:runtime/:id             that session's version list
//   GET  /sessions/:runtime/:id/raw?v=N     version N, byte-for-byte (default: latest)
//   POST /sessions/:runtime/:id/restore?v=N Claude only: version N as a NEW session in the
//                                           same project, so `claude --resume <new id>` picks
//                                           it up without touching the original
//   GET  /sessions/:runtime/:id/chunk?v=N   version N's own bytes (a base: the file; an
//                                           append: what it added), REDACTED — what a mirror pulls
//   GET  /sessions?mirror=1                 the sessions this machine mirrors from its peers
//   GET  /sessions/mirror-token             this machine's MIRROR token (created on first ask)
//   POST /sessions/mirror-peers             on the mirror: {name, ip?, port, token} to pull from
//
// A mirror token is a second bearer that opens only the list, a session's index and its
// redacted chunks — never /raw, /restore or anything else on the machine — so the
// always-on machine holds one per peer instead of each peer's full token.
//
// Mirror (MESH_SESSIONS_MIRROR=on, meant for the always-on machine): every ten minutes, pull
// each peer's new versions from hosts.json into ~/.mesh/sessions-mirror/<host>/<runtime>/
// <id>.jsonl — plain redacted JSONL an agent there can grep or hand off. An append is
// appended; a new base (compaction) keeps the previous file as <id>.v<N>.jsonl.gz. Redaction
// happens on the machine that wrote the transcript, so a secret never crosses the tailnet.
import { homedir, networkInterfaces } from "node:os";
import { join, basename, dirname } from "node:path";
import { mkdir, readdir, readFile, rename, stat, writeFile, chmod, appendFile, truncate } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { gzipSync, gunzipSync } from "node:zlib";
import { randomUUID, randomBytes } from "node:crypto";
import { redact, addKnownSecrets } from "./redact";
import { isAuthorized } from "./auth";

const HOME = homedir();
const STORE = process.env.MESH_SESSIONS_DIR || join(HOME, ".mesh", "sessions");
const CLAUDE_PROJECTS = join(HOME, ".claude", "projects");
const CODEX_SESSIONS = join(HOME, ".codex", "sessions");
const MIRROR = process.env.MESH_SESSIONS_MIRROR_DIR || join(HOME, ".mesh", "sessions-mirror");

type Runtime = "claude" | "codex";
type Version = { n: number; kind: "base" | "append"; size: number; sha256: string; mtimeMs: number; ts: string };
type Index = { runtime: Runtime; id: string; source: string; cwd: string | null; title: string | null; versions: Version[] };

const sha = (b: Uint8Array) => new Bun.CryptoHasher("sha256").update(b).digest("hex");
const dirOf = (runtime: Runtime, id: string) => join(STORE, runtime, id);

async function readIndex(runtime: Runtime, id: string): Promise<Index | null> {
  try { return JSON.parse(await readFile(join(dirOf(runtime, id), "index.json"), "utf8")); } catch { return null; }
}
async function writePrivate(path: string, data: Uint8Array | string) {
  const tmp = `${path}.${process.pid}.tmp`;
  await writeFile(tmp, data, { mode: 0o600 });
  await rename(tmp, path);
}

/// The runtime's own id for a transcript, and which runtime wrote it.
function identify(path: string): { runtime: Runtime; id: string } | null {
  if (path.startsWith(CLAUDE_PROJECTS + "/")) {
    const name = basename(path, ".jsonl");
    // Subagent transcripts (agent-…) belong to the parent conversation's history, not a
    // session anyone resumes; they are skipped rather than listed as sessions.
    return name.startsWith("agent-") ? null : { runtime: "claude", id: name };
  }
  if (path.startsWith(CODEX_SESSIONS + "/")) return { runtime: "codex", id: basename(path, ".jsonl") };
  return null;
}

/// cwd and the first thing the person asked, from the head of the transcript.
function describe(bytes: Uint8Array): { cwd: string | null; title: string | null } {
  const head = new TextDecoder().decode(bytes.subarray(0, 262144));
  let cwd: string | null = null, title: string | null = null;
  for (const line of head.split("\n")) {
    let o: any; try { o = JSON.parse(line); } catch { continue; }
    cwd ??= o.cwd ?? o.payload?.cwd ?? null;
    if (!title) {
      const c = o.type === "user" ? o.message?.content : o.payload?.type === "user_message" ? o.payload?.message : null;
      const text = typeof c === "string" ? c : Array.isArray(c) ? c.find((p: any) => p?.type === "text")?.text : null;
      // Hook and system wrappers are not what the person typed.
      if (typeof text === "string" && text.trim() && !text.startsWith("<")) title = text.trim().replace(/\s+/g, " ").slice(0, 120);
    }
    if (cwd && title) break;
  }
  return { cwd, title };
}

type Outcome = "unchanged" | "base" | "append" | "skipped";
const inflight = new Map<string, Promise<Outcome>>();
/// Record the current state of one transcript. A no-op when nothing changed. Calls for
/// the same file queue behind each other: the Stop-event trigger and the sweep can land
/// together, and two writers picking the same v<N> would break every later version.
export function snapshot(path: string): Promise<Outcome> {
  const next = (inflight.get(path) ?? Promise.resolve("skipped" as Outcome)).catch(() => "skipped" as Outcome).then(() => take(path));
  inflight.set(path, next);
  next.finally(() => { if (inflight.get(path) === next) inflight.delete(path); }).catch(() => {});
  return next;
}

async function take(path: string): Promise<Outcome> {
  const who = identify(path);
  if (!who) return "skipped";
  const st = await stat(path).catch(() => null);
  if (!st || !st.isFile()) return "skipped";
  const index = (await readIndex(who.runtime, who.id)) ?? { runtime: who.runtime, id: who.id, source: path, cwd: null, title: null, versions: [] };
  const last = index.versions.at(-1);
  if (last && last.size === st.size && last.mtimeMs === st.mtimeMs) return "unchanged";

  // The common case, a turn appended to the file: hash the old prefix in chunks and read
  // only the new bytes, so a 139 MB transcript costs its delta in memory, not a full copy
  // per turn (measured: 593 MB RSS reading it whole, every turn).
  if (last && last.size > 0 && st.size > last.size) {
    const h = new Bun.CryptoHasher("sha256");
    // node:fs, not Bun.file().slice().stream(): on bun 1.3.14 that stream never ends when
    // the slice stops mid-file past its first chunk (reproduced with 200 KB of 400 KB).
    for await (const chunk of createReadStream(path, { start: 0, end: last.size - 1 })) h.update(chunk);
    if (h.copy().digest("hex") === last.sha256) {
      const delta = new Uint8Array(await Bun.file(path).slice(last.size).arrayBuffer());
      return record(index, path, st.mtimeMs, "append", delta, last.size + delta.length, h.update(delta).digest("hex"));
    }
  }
  // First sight, or the runtime rewrote the file (compaction): a new full base.
  // ponytail: reads the whole file (~2.5x its size in RSS, once per session and per
  // compaction); stream it through createGzip if a base ever has to fit a tight box.
  const bytes = new Uint8Array(await Bun.file(path).arrayBuffer());
  const full = sha(bytes);
  if (last && last.sha256 === full) return "unchanged";
  return record(index, path, st.mtimeMs, "base", bytes, bytes.length, full);
}

async function record(index: Index, path: string, mtimeMs: number, kind: Version["kind"], bytes: Uint8Array, size: number, sha256: string) {
  const n = (index.versions.at(-1)?.n ?? 0) + 1;
  const dir = dirOf(index.runtime, index.id);
  await mkdir(dir, { recursive: true, mode: 0o700 });
  await chmod(STORE, 0o700).catch(() => {});
  await writePrivate(join(dir, `v${n}.gz`), gzipSync(bytes));
  if (!index.cwd || !index.title) {
    const head = kind === "base" ? bytes : new Uint8Array(await Bun.file(path).slice(0, 262144).arrayBuffer());
    const d = describe(head); index.cwd ??= d.cwd; index.title ??= d.title;
  }
  index.source = path;
  index.versions.push({ n, kind, size, sha256, mtimeMs, ts: new Date().toISOString() });
  await writePrivate(join(dir, "index.json"), JSON.stringify(index, null, 1));
  return kind;
}

/// Version `n` (default: latest), rebuilt from its base and the appends after it, and
/// checked against the hash recorded when it was taken.
export async function reconstruct(runtime: Runtime, id: string, n?: number): Promise<Uint8Array | null> {
  const index = await readIndex(runtime, id);
  if (!index?.versions.length) return null;
  const target = n ?? index.versions.at(-1)!.n;
  const upto = index.versions.filter((v) => v.n <= target);
  const baseAt = upto.map((v) => v.kind).lastIndexOf("base");
  if (baseAt < 0) return null;
  const parts: Uint8Array[] = [];
  for (const v of upto.slice(baseAt)) parts.push(gunzipSync(await readFile(join(dirOf(runtime, id), `v${v.n}.gz`))));
  const out = new Uint8Array(parts.reduce((s, p) => s + p.length, 0));
  let at = 0; for (const p of parts) { out.set(p, at); at += p.length; }
  return sha(out) === upto.at(-1)!.sha256 ? out : null;
}

async function* transcripts(): AsyncGenerator<string> {
  for (const slug of await readdir(CLAUDE_PROJECTS).catch(() => [] as string[])) {
    for (const f of await readdir(join(CLAUDE_PROJECTS, slug)).catch(() => [] as string[])) {
      if (f.endsWith(".jsonl")) yield join(CLAUDE_PROJECTS, slug, f);
    }
  }
  // sessions/YYYY/MM/DD/rollout-*.jsonl
  const walk = async function* (dir: string, depth: number): AsyncGenerator<string> {
    for (const e of await readdir(dir, { withFileTypes: true }).catch(() => [] as any[])) {
      const p = join(dir, e.name);
      if (e.isDirectory() && depth < 3) yield* walk(p, depth + 1);
      else if (e.isFile() && e.name.startsWith("rollout-") && e.name.endsWith(".jsonl")) yield p;
    }
  };
  yield* walk(CODEX_SESSIONS, 0);
}

let sweeping = false;
/// Snapshot every transcript that changed. One file at a time, yielding between them, so a
/// first run over a year of history does not stall the daemon's other routes.
export async function sweep(): Promise<{ scanned: number; recorded: number }> {
  if (sweeping) return { scanned: 0, recorded: 0 };
  sweeping = true;
  let scanned = 0, recorded = 0;
  try {
    for await (const path of transcripts()) {
      scanned++;
      const r = await snapshot(path).catch(() => "skipped");
      if (r === "base" || r === "append") recorded++;
      await Bun.sleep(0);
    }
  } finally { sweeping = false; }
  return { scanned, recorded };
}

/// Start the background sweep: shortly after launch, then every ten minutes. A turn that
/// ends between sweeps is caught earlier by the Stop-event trigger in server.ts.
export function startSessionSweep(): void {
  if (process.env.MESH_SESSIONS === "off") return;
  setTimeout(() => { sweep().catch(() => {}); setInterval(() => sweep().catch(() => {}), 10 * 60_000); }, 30_000);
}

async function list(limit: number) {
  const rows: any[] = [];
  for (const runtime of ["claude", "codex"] as Runtime[]) {
    for (const id of await readdir(join(STORE, runtime)).catch(() => [] as string[])) {
      const ix = await readIndex(runtime, id);
      if (!ix?.versions.length) continue;
      const last = ix.versions.at(-1)!;
      rows.push({ runtime, id, cwd: ix.cwd, title: ix.title, versions: ix.versions.length, size: last.size, lastTs: last.ts,
        live: await stat(ix.source).then(() => true, () => false) });
    }
  }
  return rows.sort((a, b) => b.lastTs.localeCompare(a.lastTs)).slice(0, limit);
}

/// Version n's own chunk, redacted in ~1 MB batches cut at newlines, so a 139 MB base never
/// becomes one giant string.
async function redactedChunk(runtime: Runtime, id: string, n: number): Promise<{ kind: Version["kind"]; body: ReadableStream } | null> {
  const v = (await readIndex(runtime, id))?.versions.find((x) => x.n === n);
  if (!v) return null;
  const raw = gunzipSync(await readFile(join(dirOf(runtime, id), `v${n}.gz`)));
  const dec = new TextDecoder(), enc = new TextEncoder();
  let at = 0;
  const body = new ReadableStream({
    pull(ctrl) {
      if (at >= raw.length) return ctrl.close();
      const nl = raw.indexOf(10, Math.min(raw.length - 1, at + (1 << 20)));
      const end = nl < 0 ? raw.length : nl + 1;
      ctrl.enqueue(enc.encode(redact(dec.decode(raw.subarray(at, end))).text));
      at = end;
    },
  });
  return { kind: v.kind, body };
}

const MIRROR_TOKEN = join(HOME, ".mesh", "mirror-token");
const MIRROR_PEERS = join(MIRROR, "peers.json");
let mirrorToken: string | null = null;
async function ownMirrorToken(create: boolean): Promise<string | null> {
  mirrorToken ??= await readFile(MIRROR_TOKEN, "utf8").then((t) => t.trim() || null, () => null);
  if (!mirrorToken && create) {
    mirrorToken = randomBytes(32).toString("base64url");
    await mkdir(dirname(MIRROR_TOKEN), { recursive: true, mode: 0o700 });
    await writePrivate(MIRROR_TOKEN, mirrorToken + "\n");
  }
  if (mirrorToken) addKnownSecrets([["mirror-token", mirrorToken]]);
  return mirrorToken;
}

/// Called only when the full token was refused: does this request carry the mirror
/// token, for one of the three read routes a mirror needs?
export async function mirrorReadAllowed(req: Request, url: URL): Promise<boolean> {
  if (req.method !== "GET") return false;
  const readable = (url.pathname === "/sessions" && !url.searchParams.has("mirror"))
    || /^\/sessions\/(claude|codex)\/[A-Za-z0-9][A-Za-z0-9._-]*(\/chunk)?$/.test(url.pathname);
  const token = readable ? await ownMirrorToken(false) : null;
  return !!token && isAuthorized(token, req.headers.get("authorization") ?? "");
}

type MirrorEntry = { runtime: Runtime; id: string; n: number; size: number; cwd: string | null; title: string | null; ts: string };

/// Pull one peer's new versions. Versions are applied in order and the index is written
/// after each, so an interrupted pull resumes where it stopped.
async function mirrorPeer(name: string, base: string, token: string): Promise<number> {
  const get = (p: string) => fetch(base + p, { headers: token ? { Authorization: `Bearer ${token}` } : {}, signal: AbortSignal.timeout(120_000) });
  const res = await get("/sessions?limit=500");
  if (!res.ok) return 0;
  const { sessions } = await res.json() as { sessions: any[] };
  const dir = join(MIRROR, name);
  await mkdir(dir, { recursive: true, mode: 0o700 });
  await chmod(MIRROR, 0o700).catch(() => {});
  const ixPath = join(dir, "index.json");
  const index: Record<string, MirrorEntry> = await readFile(ixPath, "utf8").then(JSON.parse, () => ({}));
  let fetched = 0;
  for (const s of sessions) {
    if (s.runtime !== "claude" && s.runtime !== "codex") continue;
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(String(s.id))) continue;  // it names a file here
    const key = `${s.runtime}/${s.id}`;
    const have: MirrorEntry = index[key] ?? { runtime: s.runtime, id: s.id, n: 0, size: 0, cwd: s.cwd ?? null, title: s.title ?? null, ts: "" };
    if (have.n >= s.versions) continue;
    const up = await get(`/sessions/${key}`).then((r) => (r.ok ? r.json() : null), () => null) as Index | null;
    if (!up) continue;
    const file = join(dir, s.runtime, `${s.id}.jsonl`);
    await mkdir(dirname(file), { recursive: true, mode: 0o700 });
    for (const v of up.versions.filter((x) => x.n > have.n)) {
      const r = await get(`/sessions/${key}/chunk?v=${v.n}`).catch(() => null);
      if (!r?.ok) break;
      const chunk = new Uint8Array(await r.arrayBuffer());
      if (v.kind === "base") {
        if (have.size > 0) await writePrivate(join(dir, s.runtime, `${s.id}.v${have.n}.jsonl.gz`), gzipSync(await readFile(file)));
        await writePrivate(file, chunk);
        have.size = chunk.length;
      } else {
        // Undo a half-written append from an interrupted pull before adding this one.
        if (((await stat(file).catch(() => null))?.size ?? 0) > have.size) await truncate(file, have.size);
        await appendFile(file, chunk, { mode: 0o600 });
        have.size += chunk.length;
      }
      have.n = v.n; have.ts = v.ts; have.cwd ??= up.cwd; have.title ??= up.title;
      index[key] = have;
      await writePrivate(ixPath, JSON.stringify(index, null, 1));
      fetched++;
    }
  }
  return fetched;
}

let mirroring = false;
export async function mirrorOnce(): Promise<{ peers: number; fetched: number }> {
  if (mirroring) return { peers: 0, fetched: 0 };
  mirroring = true;
  let peers = 0, fetched = 0;
  try {
    // Peers registered with a mirror token win over a full token in hosts.json.
    const cfg = await readFile(join(HOME, ".mesh", "hosts.json"), "utf8").then(JSON.parse, () => ({}));
    const registered = await readFile(MIRROR_PEERS, "utf8").then(JSON.parse, () => ({}));
    const mine = new Set(Object.values(networkInterfaces()).flat().map((i) => i?.address));
    for (const [name, h] of Object.entries<any>({ ...(cfg?.hosts ?? {}), ...registered })) {
      if (!h?.ip || mine.has(h.ip) || h.ip === "127.0.0.1" || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) continue;
      peers++;
      // A peer that is asleep or predates `sessions` is simply tried again next round.
      fetched += await mirrorPeer(name, `http://${h.ip}:${h.port || 8899}`, h.token ? String(h.token) : "").catch(() => 0);
    }
  } finally { mirroring = false; }
  return { peers, fetched };
}

export function startSessionMirror(): void {
  if (process.env.MESH_SESSIONS_MIRROR !== "on") return;
  setTimeout(() => { mirrorOnce().catch(() => {}); setInterval(() => mirrorOnce().catch(() => {}), 10 * 60_000); }, 60_000);
}

async function mirrorList() {
  const rows: any[] = [];
  for (const host of await readdir(MIRROR).catch(() => [] as string[])) {
    const index: Record<string, MirrorEntry> = await readFile(join(MIRROR, host, "index.json"), "utf8").then(JSON.parse, () => ({}));
    for (const e of Object.values(index)) rows.push({ host, ...e, path: join(MIRROR, host, e.runtime, `${e.id}.jsonl`) });
  }
  return rows.sort((a, b) => b.ts.localeCompare(a.ts));
}

/// Mirrors handleInput's contract: null = not our route. Auth has already passed.
export async function handleSessions(req: Request, url: URL, server?: any): Promise<Response | null> {
  if (url.pathname === "/sessions/mirror-token" && req.method === "GET") {
    return Response.json({ token: await ownMirrorToken(true) });
  }
  if (url.pathname === "/sessions/mirror-peers" && req.method === "POST") {
    const b = await req.json().catch(() => null) as any;
    const ip = b?.ip || (server?.requestIP?.(req)?.address ?? "").replace(/^::ffff:/, "");
    if (!b || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(String(b.name ?? "")) || !ip || typeof b.token !== "string" || b.token.length < 32) {
      return Response.json({ error: "need name, token (a mirror token), and ip unless it is the caller" }, { status: 400 });
    }
    const peers = await readFile(MIRROR_PEERS, "utf8").then(JSON.parse, () => ({}));
    peers[b.name] = { ip, port: Number(b.port) || 8899, token: b.token };
    await mkdir(MIRROR, { recursive: true, mode: 0o700 });
    await writePrivate(MIRROR_PEERS, JSON.stringify(peers, null, 1));
    addKnownSecrets([[`mirror-token:${b.name}`, b.token]]);
    return Response.json({ ok: true, name: b.name, ip, mirroring: process.env.MESH_SESSIONS_MIRROR === "on" }, { status: 201 });
  }
  if (url.pathname === "/sessions" && req.method === "GET") {
    if (url.searchParams.get("mirror") === "1") return Response.json({ sessions: await mirrorList() });
    return Response.json({ sessions: await list(Math.min(500, Number(url.searchParams.get("limit") ?? 50) || 50)) });
  }
  const m = url.pathname.match(/^\/sessions\/(claude|codex)\/([A-Za-z0-9][A-Za-z0-9._-]*)(\/raw|\/restore|\/chunk)?$/);
  if (!m) return null;
  const [, runtime, id, tail] = m as unknown as [string, Runtime, string, string | undefined];
  const v = url.searchParams.has("v") ? Number(url.searchParams.get("v")) : undefined;
  if (!tail && req.method === "GET") {
    const ix = await readIndex(runtime, id);
    return ix ? Response.json(ix) : Response.json({ error: "no such session" }, { status: 404 });
  }
  if (tail === "/raw" && req.method === "GET") {
    const bytes = await reconstruct(runtime, id, v);
    return bytes ? new Response(bytes, { headers: { "content-type": "application/x-ndjson" } })
                 : Response.json({ error: "no such version, or it no longer matches its recorded hash" }, { status: 404 });
  }
  if (tail === "/chunk" && req.method === "GET") {
    const c = v ? await redactedChunk(runtime, id, v) : null;
    return c ? new Response(c.body, { headers: { "content-type": "application/x-ndjson", "x-mesh-kind": c.kind } })
             : Response.json({ error: "no such version" }, { status: 404 });
  }
  if (tail === "/restore" && req.method === "POST") {
    if (runtime !== "claude") return Response.json({ error: "restore is Claude Code only for now" }, { status: 400 });
    const ix = await readIndex(runtime, id);
    const bytes = await reconstruct(runtime, id, v);
    if (!ix || !bytes) return Response.json({ error: "no such version" }, { status: 404 });
    // A new id, in the same project folder: Claude finds a session by its file name, and
    // the lines inside carry the id they were written under, so both are rewritten —
    // the original transcript is never touched.
    const newId = randomUUID();
    const text = new TextDecoder().decode(bytes).replaceAll(`"sessionId":"${id}"`, `"sessionId":"${newId}"`);
    const dest = join(dirname(ix.source), `${newId}.jsonl`);
    await mkdir(dirname(dest), { recursive: true });
    await writeFile(dest, text, { mode: 0o600 });
    return Response.json({ ok: true, id: newId, path: dest, cwd: ix.cwd, resume: `claude --resume ${newId}` }, { status: 201 });
  }
  return null;
}

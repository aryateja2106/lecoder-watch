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
//   GET  /sessions/search?q=                full-text over what was said in them (chats.ts),
//                                           on this machine and every hosts.json peer
//   POST /sessions/:runtime/:id/resume      the plan to start one again — {name, cmd, cwd,
//                                           cwdMissing, restoredFrom?}; starts nothing (the
//                                           caller hands it to /agents/new)
//   GET  /sessions?mirror=1                 the sessions this machine mirrors from its peers
//   GET  /sessions/mirror-token             this machine's MIRROR token (created on first ask)
//   POST /sessions/mirror-peers             on the mirror: {name, ip?, port, token} to pull from
//
// A mirror token is a second bearer that opens only the list, a session's index and its
// redacted chunks — never /raw, /restore or anything else on the machine — so the
// always-on machine holds one per peer instead of each peer's full token.
//
// Mirror (meant for the always-on machine): every ten minutes, pull each registered peer's
// new versions (`mesh sessions mirror-to <this machine>`; with MESH_SESSIONS_MIRROR=on, every
// hosts.json peer too; =off stops it) into ~/.mesh/sessions-mirror/<host>/<runtime>/
// <id>.jsonl — plain redacted JSONL an agent there can grep or hand off. An append is
// appended; a new base (compaction) keeps the previous file as <id>.v<N>.jsonl.gz. Redaction
// happens on the machine that wrote the transcript, so a secret never crosses the tailnet.
import { homedir, networkInterfaces } from "node:os";
import { join, basename, dirname } from "node:path";
import { mkdir, readdir, readFile, rename, stat, writeFile, chmod, truncate, unlink } from "node:fs/promises";
import { createReadStream, createWriteStream } from "node:fs";
import { pipeline } from "node:stream/promises";
import { Readable } from "node:stream";
import { gunzipSync, createGzip, createGunzip } from "node:zlib";
import { randomUUID, randomBytes } from "node:crypto";
import { redact, addKnownSecrets } from "./redact";
import { isAuthorized } from "./auth";
import { indexSession, catchUp, searchRoute } from "./chats";

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
      const p = o.payload;
      const c = o.type === "user" ? o.message?.content
        : p?.type === "user_message" ? p.message
        : p?.type === "message" && p.role === "user" ? p.content : null;
      const parts: string[] = typeof c === "string" ? [c] : Array.isArray(c) ? c.map((x: any) => x?.text).filter((t: any) => typeof t === "string") : [];
      for (let text of parts) {
        // Codex's desktop app puts attached files first and the ask after this heading.
        const ask = text.indexOf("## My request for Codex:");
        if (ask >= 0) text = text.slice(ask + 24);
        text = text.trim();
        // Hook, system and instruction wrappers are not what the person typed.
        if (text && !/^(<|# AGENTS\.md|# Files mentioned|\[Image)/.test(text)) { title = text.replace(/\s+/g, " ").slice(0, 120); break; }
      }
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
  // The one switch for every caller: the sweep, the Stop-event trigger, anything later.
  if (process.env.MESH_SESSIONS === "off") return Promise.resolve("skipped");
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

  // Nothing below holds a transcript in memory: bytes stream from the file through the
  // hasher and gzip into the store (a 139 MB first sweep pushed meshd to 1.3 GB RSS when
  // bases were read whole, and Bun does not hand that memory back).
  const dir = dirOf(who.runtime, who.id);
  await mkdir(dir, { recursive: true, mode: 0o700 });
  await chmod(STORE, 0o700).catch(() => {});
  const tmp = join(dir, `.incoming-${randomUUID()}.gz`);
  try {
    // The common case, a turn appended to the file: hash the old prefix, store only the rest.
    if (last && last.size > 0 && st.size > last.size) {
      const h = new Bun.CryptoHasher("sha256");
      // node:fs, not Bun.file().slice().stream(): on bun 1.3.14 that stream never ends when
      // the slice stops mid-file past its first chunk (reproduced with 200 KB of 400 KB).
      for await (const chunk of createReadStream(path, { start: 0, end: last.size - 1 })) h.update(chunk);
      if (h.copy().digest("hex") === last.sha256) {
        const added = await gzipFrom(path, last.size, h, tmp);
        if (!added) return "unchanged";
        return await record(index, path, st.mtimeMs, "append", tmp, last.size + added, h.digest("hex"));
      }
    }
    // First sight, or the runtime rewrote the file (compaction): a new full base.
    const h = new Bun.CryptoHasher("sha256");
    const size = await gzipFrom(path, 0, h, tmp);
    const full = h.digest("hex");
    if (last && last.sha256 === full) return "unchanged";
    return await record(index, path, st.mtimeMs, "base", tmp, size, full);
  } finally {
    await unlink(tmp).catch(() => {});  // gone already when it became a version
  }
}

/// Stream bytes [start, EOF) of `path` through `h` into a gzip file. Returns the count.
async function gzipFrom(path: string, start: number, h: InstanceType<typeof Bun.CryptoHasher>, dest: string): Promise<number> {
  let n = 0;
  await pipeline(createReadStream(path, { start }), async function* (src: AsyncIterable<Buffer>) {
    for await (const c of src) { h.update(c); n += c.length; yield c; }
  }, createGzip(), createWriteStream(dest, { mode: 0o600 }));
  return n;
}

async function record(index: Index, path: string, mtimeMs: number, kind: Version["kind"], gz: string, size: number, sha256: string) {
  const n = (index.versions.at(-1)?.n ?? 0) + 1;
  await rename(gz, join(dirOf(index.runtime, index.id), `v${n}.gz`));
  if (!index.cwd || !index.title) {
    const d = describe(new Uint8Array(await Bun.file(path).slice(0, 262144).arrayBuffer()));
    index.cwd ??= d.cwd; index.title ??= d.title;
  }
  index.source = path;
  index.versions.push({ n, kind, size, sha256, mtimeMs, ts: new Date().toISOString() });
  await writePrivate(join(dirOf(index.runtime, index.id), "index.json"), JSON.stringify(index, null, 1));
  indexSession(index.runtime, index.id).catch(() => {});  // search follows the store
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
  // After the first sweep, index whatever was stored before chats.ts existed.
  setTimeout(() => { sweep().then(() => catchUp()).catch(() => {}); setInterval(() => sweep().catch(() => {}), 10 * 60_000); }, 30_000);
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

/// Version n's own chunk, redacted in ~1 MB batches cut at newlines and streamed, so a
/// 139 MB base never sits in memory whole or becomes one giant string.
async function redactedChunk(runtime: Runtime, id: string, n: number): Promise<{ kind: Version["kind"]; body: ReadableStream } | null> {
  const v = (await readIndex(runtime, id))?.versions.find((x) => x.n === n);
  const file = join(dirOf(runtime, id), `v${n}.gz`);
  if (!v || !(await stat(file).catch(() => null))) return null;
  const it = redactBatches(createReadStream(file).pipe(createGunzip()));
  const enc = new TextEncoder();
  const body = new ReadableStream({
    async pull(ctrl) { const { value, done } = await it.next(); if (done) ctrl.close(); else ctrl.enqueue(enc.encode(value)); },
    async cancel() { await it.return(undefined); },
  });
  return { kind: v.kind, body };
}

async function* redactBatches(src: AsyncIterable<Buffer>): AsyncGenerator<string> {
  const dec = new TextDecoder();
  let pending = "";
  for await (const c of src) {
    pending += dec.decode(c, { stream: true });
    const cut = pending.length >= 1 << 20 ? pending.lastIndexOf("\n") + 1 : 0;
    if (cut > 0) { yield redact(pending.slice(0, cut)).text; pending = pending.slice(cut); }
  }
  pending += dec.decode();
  if (pending) yield redact(pending).text;
}

/// Write a response body to a file without buffering it; "a" appends. Returns the count.
async function streamTo(body: ReadableStream, dest: string, flags: "w" | "a"): Promise<number> {
  let n = 0;
  await pipeline(Readable.fromWeb(body as any), async function* (src: AsyncIterable<Buffer>) {
    for await (const c of src) { n += c.length; yield c; }
  }, createWriteStream(dest, { flags, mode: 0o600 }));
  return n;
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
  const res = await get("/sessions?limit=5000");
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
      if (!r?.ok || !r.body) break;
      if (v.kind === "base") {
        const incoming = `${file}.incoming`;
        const size = await streamTo(r.body, incoming, "w");
        if (have.size > 0) {
          const kept = join(dir, s.runtime, `${s.id}.v${have.n}.jsonl.gz`);
          await pipeline(createReadStream(file), createGzip(), createWriteStream(`${kept}.tmp`, { mode: 0o600 }));
          await rename(`${kept}.tmp`, kept);
        }
        await rename(incoming, file);
        have.size = size;
      } else {
        // Undo a half-written append from an interrupted pull before adding this one.
        if (((await stat(file).catch(() => null))?.size ?? 0) > have.size) await truncate(file, have.size);
        have.size += await streamTo(r.body, file, "a");
      }
      have.n = v.n; have.ts = v.ts; have.cwd ??= up.cwd; have.title ??= up.title;
      index[key] = have;
      await writePrivate(ixPath, JSON.stringify(index, null, 1));
      fetched++;
    }
  }
  return fetched;
}

let running: Promise<{ peers: number; fetched: number }> | null = null;
/// One pull round. A caller arriving mid-round waits for that round instead of starting a
/// second one over the same files.
export function mirrorOnce(): Promise<{ peers: number; fetched: number }> {
  running ??= pullRound().finally(() => { running = null; });
  return running;
}

async function pullRound(): Promise<{ peers: number; fetched: number }> {
  let peers = 0, fetched = 0;
  {
    // A registered peer (mirror token) wins over the same name in hosts.json (full token),
    // and hosts.json peers are pulled only when the owner asked for it.
    const cfg = process.env.MESH_SESSIONS_MIRROR === "on" ? await readFile(join(HOME, ".mesh", "hosts.json"), "utf8").then(JSON.parse, () => ({})) : {};
    const registered = await readFile(MIRROR_PEERS, "utf8").then(JSON.parse, () => ({}));
    const mine = new Set(Object.values(networkInterfaces()).flat().map((i) => i?.address));
    for (const [name, h] of Object.entries<any>({ ...(cfg?.hosts ?? {}), ...registered })) {
      if (!h?.ip || mine.has(h.ip) || h.ip === "127.0.0.1" || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) continue;
      peers++;
      // A peer that is asleep or predates `sessions` is simply tried again next round.
      fetched += await mirrorPeer(name, `http://${h.ip}:${h.port || 8899}`, h.token ? String(h.token) : "").catch(() => 0);
    }
  }
  return { peers, fetched };
}

export function startSessionMirror(): void {
  if (process.env.MESH_SESSIONS_MIRROR === "off") return;
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
    const on = process.env.MESH_SESSIONS_MIRROR !== "off";
    if (on) mirrorOnce().catch(() => {});  // start pulling now, not at the next ten-minute tick
    return Response.json({ ok: true, name: b.name, ip, mirroring: on }, { status: 201 });
  }
  if (url.pathname === "/sessions/search" && req.method === "GET") return Response.json(await searchRoute(url.searchParams));
  const rs = url.pathname.match(/^\/sessions\/(claude|codex)\/([^/]+)\/resume$/);
  if (rs && req.method === "POST") return resumePlan(rs[1] as Runtime, rs[2]);
  if (url.pathname === "/sessions" && req.method === "GET") {
    if (url.searchParams.get("mirror") === "1") return Response.json({ sessions: await mirrorList() });
    return Response.json({ sessions: await list(Math.min(5000, Number(url.searchParams.get("limit") ?? 50) || 50)) });
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
    const r = ix ? await restoreClaude(ix, v) : null;
    if (!r) return Response.json({ error: "no such version" }, { status: 404 });
    return Response.json({ ok: true, id: r.id, path: r.path, cwd: ix!.cwd, resume: `claude --resume ${r.id}` }, { status: 201 });
  }
  return null;
}

/// Version v (default: latest) of a Claude session written back as a NEW session. A new
/// id, in the same project folder: Claude finds a session by its file name, and the lines
/// inside carry the id they were written under, so both are rewritten — the original
/// transcript is never touched.
/// Version `v` (default: latest) written back as a Claude session under a new id, streamed
/// chunk by chunk — never the whole transcript in memory (a 122 MB restore took meshd to
/// 1.08 GB). The new id is derived from the session and version, so restoring the same
/// version again reuses the copy instead of writing another one.
async function restoreClaude(ix: Index, v?: number): Promise<{ id: string; path: string; reused?: boolean } | null> {
  const target = v ?? ix.versions.at(-1)?.n;
  const upto = ix.versions.filter((x) => x.n <= (target ?? 0));
  const baseAt = upto.map((x) => x.kind).lastIndexOf("base");
  if (!upto.length || upto.at(-1)!.n !== target || baseAt < 0) return null;
  const h = sha(new TextEncoder().encode(`${ix.id}:${upto.at(-1)!.sha256}`));
  const newId = `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-${"89ab"[parseInt(h[16], 16) & 3]}${h.slice(17, 20)}-${h.slice(20, 32)}`;
  const dest = join(dirname(ix.source), `${newId}.jsonl`);
  if ((await stat(dest).catch(() => null))?.size) return { id: newId, path: dest, reused: true };
  await mkdir(dirname(dest), { recursive: true });
  const tmp = `${dest}.${randomUUID()}.tmp`;
  const hasher = new Bun.CryptoHasher("sha256");
  const from = `"sessionId":"${ix.id}"`, to = `"sessionId":"${newId}"`;
  let carry = Buffer.alloc(0);
  // Whole lines only, so an id split across two chunks is still found; latin1 maps each
  // byte to one character, so the rest of the line passes through byte for byte.
  const rewrite = (b: Buffer) => Buffer.from(b.toString("latin1").split(from).join(to), "latin1");
  try {
    await pipeline(async function* () {
      for (const x of upto.slice(baseAt)) {
        for await (const c of createReadStream(join(dirOf("claude", ix.id), `v${x.n}.gz`)).pipe(createGunzip())) {
          hasher.update(c);
          const buf = carry.length ? Buffer.concat([carry, c]) : c;
          const cut = buf.lastIndexOf(10) + 1;
          carry = buf.subarray(cut);
          if (cut) yield rewrite(buf.subarray(0, cut));
        }
      }
      if (carry.length) yield rewrite(carry);
    }, createWriteStream(tmp, { mode: 0o600 }));
    if (hasher.digest("hex") !== upto.at(-1)!.sha256) throw new Error("does not match its recorded hash");
    await rename(tmp, dest);
    return { id: newId, path: dest };
  } catch {
    await unlink(tmp).catch(() => {});
    return null;
  }
}

/// Which transcript a resumed pane is showing, by the pane's name, until its first hook
/// event says so itself: before that the chat view guessed "the newest transcript in this
/// folder", which is whatever else was running there (seen in the simulator).
const resumedTranscripts = new Map<string, string>();
export const resumedTranscript = (name: string) => resumedTranscripts.get(name);

const UUID_RE = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
/// How to start a stored session again, without starting it. The uuid is validated here —
/// it goes into a shell command line — and a Claude transcript the runtime already deleted
/// is restored first, so the plan resumes the restored copy under its new id.
async function resumePlan(runtime: Runtime, id: string): Promise<Response> {
  const uuid = runtime === "claude" ? id.match(new RegExp(`^${UUID_RE}$`, "i"))?.[0]
    : id.match(new RegExp(`^rollout-[0-9T:-]+-(${UUID_RE})$`, "i"))?.[1];
  if (!uuid) return Response.json({ error: "not a resumable session id" }, { status: 400 });
  const ix = await readIndex(runtime, id);
  if (!ix) return Response.json({ error: "no such session" }, { status: 404 });
  // A machine can hold transcripts of a CLI it no longer has (the Pi keeps Codex rollouts
  // from April and no codex): say so, instead of a pane that dies before anyone sees it.
  const bin = runtime === "claude" ? "claude" : "codex";
  if (!Bun.which(bin, { PATH: process.env.PATH ?? "" })) return Response.json({ error: `${bin} is not installed on this machine` }, { status: 424 });
  let resumeId = uuid, restoredFrom: string | undefined, restoredPath: string | undefined;
  if (!(await stat(ix.source).catch(() => null))) {
    // Codex finds a rollout by its uuid anywhere under ~/.codex/sessions; restoring one is not built.
    if (runtime !== "claude") return Response.json({ error: "Codex deleted this rollout, and restore is Claude Code only" }, { status: 410 });
    const r = await restoreClaude(ix);
    if (!r) return Response.json({ error: "no stored version rebuilds cleanly" }, { status: 404 });
    // Named only when this call wrote the copy; a later resume reuses it silently.
    resumeId = r.id; restoredPath = r.path; if (!r.reused) restoredFrom = id;
  }
  // The folder it was started in: Claude looks a session up by that folder's project slug.
  const ok = !!ix.cwd && !!(await stat(ix.cwd).catch(() => null))?.isDirectory();
  resumedTranscripts.set(`resume-${resumeId.slice(-8)}`, restoredPath ?? ix.source);
  return Response.json({
    // The END of the uuid: Codex ids are UUIDv7, whose first 8 hex are a timestamp that
    // sessions started in the same minute share.
    name: `resume-${resumeId.slice(-8)}`,
    // A CLI that fails (logged out, a session it cannot open) leaves a shell saying so,
    // rather than a pane that closes before the phone gets to show it.
    cmd: `${runtime === "claude" ? `claude --resume ${resumeId}` : `codex resume ${resumeId}`} || { s=$?; echo; echo "[mesh] ${bin} exited with status $s"; exec "\${SHELL:-/bin/sh}"; }`,
    cwd: ok ? ix.cwd : HOME, cwdMissing: !ok, ...(restoredFrom ? { restoredFrom } : {}),
  });
}

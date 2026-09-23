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
import { homedir } from "node:os";
import { join, basename, dirname } from "node:path";
import { mkdir, readdir, readFile, rename, stat, writeFile, chmod } from "node:fs/promises";
import { gzipSync, gunzipSync } from "node:zlib";
import { randomUUID } from "node:crypto";

const HOME = homedir();
const STORE = process.env.MESH_SESSIONS_DIR || join(HOME, ".mesh", "sessions");
const CLAUDE_PROJECTS = join(HOME, ".claude", "projects");
const CODEX_SESSIONS = join(HOME, ".codex", "sessions");

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

/// Record the current state of one transcript. A no-op when nothing changed.
export async function snapshot(path: string): Promise<"unchanged" | "base" | "append" | "skipped"> {
  const who = identify(path);
  if (!who) return "skipped";
  const st = await stat(path).catch(() => null);
  if (!st || !st.isFile()) return "skipped";
  const index = (await readIndex(who.runtime, who.id)) ?? { runtime: who.runtime, id: who.id, source: path, cwd: null, title: null, versions: [] };
  const last = index.versions.at(-1);
  if (last && last.size === st.size && last.mtimeMs === st.mtimeMs) return "unchanged";

  const bytes = new Uint8Array(await Bun.file(path).arrayBuffer());
  const full = sha(bytes);
  if (last && last.sha256 === full) return "unchanged";
  const appended = !!last && bytes.length > last.size && sha(bytes.subarray(0, last.size)) === last.sha256;
  const n = (last?.n ?? 0) + 1;
  const dir = dirOf(who.runtime, who.id);
  await mkdir(dir, { recursive: true, mode: 0o700 });
  await chmod(STORE, 0o700).catch(() => {});
  await writePrivate(join(dir, `v${n}.gz`), gzipSync(appended ? bytes.subarray(last!.size) : bytes));
  if (!index.cwd || !index.title) { const d = describe(bytes); index.cwd ??= d.cwd; index.title ??= d.title; }
  index.source = path;
  index.versions.push({ n, kind: appended ? "append" : "base", size: bytes.length, sha256: full, mtimeMs: st.mtimeMs, ts: new Date().toISOString() });
  await writePrivate(join(dir, "index.json"), JSON.stringify(index, null, 1));
  return appended ? "append" : "base";
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

/// Mirrors handleInput's contract: null = not our route. Auth has already passed.
export async function handleSessions(req: Request, url: URL): Promise<Response | null> {
  if (url.pathname === "/sessions" && req.method === "GET") {
    return Response.json({ sessions: await list(Math.min(500, Number(url.searchParams.get("limit") ?? 50) || 50)) });
  }
  const m = url.pathname.match(/^\/sessions\/(claude|codex)\/([A-Za-z0-9._-]+)(\/raw|\/restore)?$/);
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

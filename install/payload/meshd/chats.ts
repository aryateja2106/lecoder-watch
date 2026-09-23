// chats.ts — full-text search over every agent conversation this machine kept: the user and assistant text of the transcripts sessions.ts stores, indexed version by version, searchable here and across the mesh.
//
// Why: "the session where we fixed voice input" is one of hundreds of transcripts on four
// machines, and a transcript is mostly tool calls, thinking and attachments. Only what the
// person typed and what the agent answered is indexed, so a hit is a conversation, not a
// grep match inside a 40 MB tool dump.
//
// The index follows the session store (~/.mesh/sessions), never the runtime's live file:
// each stored version is streamed through gunzip once (a whole-file read took meshd to
// 1.36 GB RSS), an append adds only its own lines, and a new base (compaction) replaces
// the session's rows. A line cut off by the end of a version waits in `carry` until the
// append that completes it.
//
//   GET /sessions/search?q=&limit=&all=1&federate=0|1   routed in sessions.ts
//
// Text is redacted before it is stored — a snippet can start mid-secret, past the prefix
// any pattern would recognise — and every excerpt and title is redacted again on the way
// out, for secrets this daemon learned about after it indexed them.
import { Database } from "bun:sqlite";
import { homedir, hostname, networkInterfaces } from "node:os";
import { join, dirname } from "node:path";
import { mkdirSync, openSync, closeSync, chmodSync, existsSync, statSync, readFileSync, createReadStream } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { createGunzip } from "node:zlib";
import { redact } from "./redact";

const HOME = homedir();
const STORE = process.env.MESH_SESSIONS_DIR || join(HOME, ".mesh", "sessions");
const DB_PATH = process.env.MESH_CHATS_DB || join(HOME, ".mesh", "chats.sqlite");
const CLIP = 2800;
const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Hook output, slash commands, reminders: `<system-reminder>`, `<command-name>`, …
const WRAPPER = /^<[a-z][a-z0-9_-]*[\s>]/i;

type Runtime = "claude" | "codex";
// `lines` numbers each message's line within the session since its last base.
// `sha` is the indexed version's hash: a store rebuilt from scratch restarts at v1, and a
// matching n with a different hash means the rows describe a transcript that is gone.
// `carry` is bytes, not text, so a UTF-8 character cut by a version boundary survives.
type Session = { cwd: string | null; title: string | null; kind: string | null; n: number; sha: string | null; carry: Uint8Array; last_ts: string | null; lines: number };
const fresh = (): Session => ({ cwd: null, title: null, kind: null, n: 0, sha: null, carry: new Uint8Array(0), last_ts: null, lines: 0 });
const off = () => process.env.MESH_SESSIONS === "off";

let db: Database | null = null;
function getDb(): Database {
  if (db) return db;
  mkdirSync(dirname(DB_PATH), { recursive: true, mode: 0o700 });
  // Created 0600 before SQLite opens it: SQLite gives its -wal and -shm files the mode
  // of the database, and these rows are what people said to their agents.
  closeSync(openSync(DB_PATH, "a", 0o600));
  chmodSync(DB_PATH, 0o600);
  const d = new Database(DB_PATH, { create: true });
  d.exec("PRAGMA journal_mode = WAL;");
  d.exec(`
    CREATE TABLE IF NOT EXISTS chat_sessions(
      runtime TEXT NOT NULL, id TEXT NOT NULL, cwd TEXT, title TEXT, kind TEXT,
      n INTEGER NOT NULL DEFAULT 0, sha TEXT, carry BLOB NOT NULL DEFAULT x'', last_ts TEXT,
      lines INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(runtime, id)
    );
    CREATE TABLE IF NOT EXISTS chat_messages(
      rowid INTEGER PRIMARY KEY, runtime TEXT NOT NULL, id TEXT NOT NULL,
      role TEXT NOT NULL, ts TEXT, line INTEGER, text TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS chat_messages_session ON chat_messages(runtime, id);
    CREATE VIRTUAL TABLE IF NOT EXISTS chat_messages_fts USING fts5(
      text, content='chat_messages', content_rowid='rowid'
    );
    CREATE TRIGGER IF NOT EXISTS chat_messages_ai AFTER INSERT ON chat_messages BEGIN
      INSERT INTO chat_messages_fts(rowid, text) VALUES (new.rowid, new.text);
    END;
    CREATE TRIGGER IF NOT EXISTS chat_messages_ad AFTER DELETE ON chat_messages BEGIN
      INSERT INTO chat_messages_fts(chat_messages_fts, rowid, text) VALUES('delete', old.rowid, old.text);
    END;
  `);
  return (db = d);
}

const clean = (t: string) => redact(t).text.slice(0, CLIP);

/// The conversation text in one transcript line, and what the line says about its session.
function extract(runtime: Runtime, o: any, s: Session): { role: string; text: string }[] {
  let role: string;
  const texts: string[] = [];
  if (runtime === "claude") {
    // Subagent transcripts (agent-*.jsonl) never reach the store; an SDK run is automation.
    if (typeof o.entrypoint === "string" && /^sdk/.test(o.entrypoint)) s.kind = "automation";
    else s.kind ??= "user";
    if (typeof o.cwd === "string") s.cwd = o.cwd;
    const named = o.type === "custom-title" ? o.customTitle : o.type === "ai-title" ? o.aiTitle : null;
    if (typeof named === "string" && named.trim()) s.title = clean(named.replace(/\s+/g, " ").trim()).slice(0, 120);
    if ((o.type !== "user" && o.type !== "assistant") || o.isMeta || o.isSidechain || o.isCompactSummary) return [];
    role = o.type;
    const c = o.message?.content;
    // tool_use, tool_result, thinking and images are the work, not the conversation.
    for (const t of typeof c === "string" ? [c] : Array.isArray(c) ? c.filter((p: any) => p?.type === "text").map((p: any) => p.text) : []) {
      const x = typeof t === "string" ? t.trim() : "";
      if (x && !WRAPPER.test(x)) texts.push(x);
    }
  } else {
    const p = o.payload ?? {};
    if (o.type === "session_meta") {
      if (typeof p.cwd === "string") s.cwd = p.cwd;
      // The rollout's own meta comes first; a fork repeats its parent's after it. A thread a
      // script or another agent started (codex exec, agent_created_thread) is automation:
      // searchable with all=1, not listed next to conversations a person had.
      s.kind ??= (p.source && typeof p.source === "object") || p.parent_thread_id || p.forked_from_id
        || /^(subagent|guardian_review)$/.test(String(p.thread_source ?? "")) ? "subagent"
        : p.source === "exec" || p.originator === "codex_exec" || p.thread_source === "agent_created_thread" ? "automation" : "user";
    }
    if (o.type !== "response_item" || p.type !== "message" || (p.role !== "user" && p.role !== "assistant")) return [];
    if (p.role === "assistant" && p.phase === "commentary") return [];  // progress narration, not the answer
    role = p.role;
    for (const part of Array.isArray(p.content) ? p.content : []) {
      let t = part?.text;
      if (typeof t !== "string") continue;
      if (role === "user") {
        // Codex's desktop app puts attached files first and the ask after this heading.
        const ask = t.indexOf("## My request for Codex:");
        if (ask >= 0) t = t.slice(ask + 24);
        else if (/^\s*(<|# AGENTS\.md|# Files mentioned)/.test(t)) continue;  // environment, instructions, attachments
      }
      t = t.trim();
      if (t) texts.push(t);
    }
  }
  const out = texts.map((text) => ({ role, text: clean(text) }));
  if (!s.title && role === "user" && out.length) s.title = out[0].text.replace(/\s+/g, " ").slice(0, 120);
  return out;
}

// ponytail: one global chain, so two passes never insert one session twice and a first
// catch-up over a year of history holds one session in memory, not all of them. Per-session
// chains if indexing throughput ever matters.
let queue: Promise<unknown> = Promise.resolve();
/// Index the stored versions of one session that are not indexed yet. Returns how many
/// messages it added.
export function indexSession(runtime: Runtime, id: string): Promise<number> {
  if (off()) return Promise.resolve(0);
  const next = queue.catch(() => {}).then(() => index(runtime, id));
  queue = next;
  return next;
}

async function index(runtime: Runtime, id: string): Promise<number> {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id)) return 0;
  const dir = join(STORE, runtime, id);
  const ix = await readFile(join(dir, "index.json"), "utf8").then(JSON.parse, () => null);
  if (!ix?.versions?.length) return 0;
  const versions = [...ix.versions].sort((a: any, b: any) => a.n - b.n);
  const d = getDb();
  let s: Session = (d.query("SELECT cwd, title, kind, n, sha, carry, last_ts, lines FROM chat_sessions WHERE runtime=? AND id=?").get(runtime, id) as Session) ?? fresh();
  // The store was rebuilt under us (deleted to free space, a new MESH_SESSIONS_DIR): start over.
  if (s.n && versions.find((v: any) => v.n === s.n)?.sha256 !== s.sha) s = { ...fresh(), n: -1 };
  let added = 0;
  for (const v of versions.filter((x: any) => x.n > s.n)) {
    const reset = v.kind === "base" || s.n === -1;
    if (reset) s = fresh();
    const ins = d.query("INSERT INTO chat_messages(runtime, id, role, ts, line, text) VALUES (?,?,?,?,?,?)");
    const take = (text: string) => {
      for (const line of text.split("\n")) {
        const at = s.lines++;
        let o: any; try { o = JSON.parse(line); } catch { continue; }
        const ts = typeof o?.timestamp === "string" ? o.timestamp : null;
        if (ts) s.last_ts = ts;
        for (const m of extract(runtime, o, s)) { ins.run(runtime, id, m.role, ts, at, m.text); added++; }
      }
    };
    // One transaction per version, streamed: rows go in as lines are read, so a text-heavy
    // base costs a chunk of memory, not every message it holds. Only this queue writes.
    d.exec("BEGIN");
    try {
      if (reset) d.query("DELETE FROM chat_messages WHERE runtime=? AND id=?").run(runtime, id);
      let pending: Buffer = Buffer.from(s.carry);
      for await (const c of createReadStream(join(dir, `v${v.n}.gz`)).pipe(createGunzip()) as AsyncIterable<Buffer>) {
        const buf = pending.length ? Buffer.concat([pending, c]) : c;
        const cut = buf.lastIndexOf(10);
        if (cut < 0) { pending = buf; continue; }
        take(buf.subarray(0, cut).toString("utf8"));
        pending = buf.subarray(cut + 1);
        await Bun.sleep(0);  // a big first index must not stall the daemon's other routes
      }
      s.carry = new Uint8Array(pending);
      s.n = v.n; s.sha = v.sha256;
      d.query(`INSERT INTO chat_sessions(runtime, id, cwd, title, kind, n, sha, carry, last_ts, lines) VALUES (?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(runtime, id) DO UPDATE SET cwd=excluded.cwd, title=excluded.title, kind=excluded.kind, n=excluded.n,
        sha=excluded.sha, carry=excluded.carry, last_ts=excluded.last_ts, lines=excluded.lines`)
        .run(runtime, id, s.cwd, s.title, s.kind, s.n, s.sha, s.carry, s.last_ts ?? v.ts ?? null, s.lines);
      d.exec("COMMIT");
    } catch {
      d.exec("ROLLBACK");  // a missing or damaged chunk: nothing half-indexed, the next call retries it
      return added;
    }
  }
  return added;
}

/// Index everything in the store that is not indexed yet — sessions stored before this
/// index existed. A no-op when the index is current.
export async function catchUp(): Promise<number> {
  if (off()) return 0;
  let added = 0;
  for (const runtime of ["claude", "codex"] as Runtime[]) {
    for (const id of await readdir(join(STORE, runtime)).catch(() => [] as string[])) added += await indexSession(runtime, id).catch(() => 0);
  }
  return added;
}

const isDir = (p: string | null | undefined) => { try { return !!p && statSync(p, { throwIfNoEntry: false })?.isDirectory() === true; } catch { return false; } };

/// A secret learned after it was indexed can span several FTS tokens, and the « » markers
/// would split it past an exact match; redact the unmarked text, and keep the markers only
/// when nothing was hidden.
function redactExcerpt(marked: string): string {
  const plain = marked.replace(/[«»]/g, "");
  const r = redact(plain).text;
  return r === plain ? marked : r;
}

const readHosts = () => readFile(join(HOME, ".mesh", "hosts.json"), "utf8").then((t) => { try { return JSON.parse(t); } catch { return {}; } }, () => ({}));

// Quote each term so typed text cannot break MATCH syntax (as kb.ts does); the last one is
// a prefix, so a search-as-you-type box already finds "voic".
const ftsQuery = (terms: string[]) => terms.map((t, i) => `"${t.replace(/"/g, '""')}"${i === terms.length - 1 ? "*" : ""}`).join(" ");

/// This machine's conversations that match `q`, best first: one row per session, up to
/// three excerpts each with the match between « ». `score` is bm25 — lower is better.
export function search({ q, limit = 20, all = false }: { q: string; limit?: number; all?: boolean }): any[] {
  const terms = q.replace(/[\u0000-\u001f\u007f]/g, " ").split(/\s+/).filter(Boolean);
  if (!terms.length || off()) return [];
  const d = getDb();
  const hits = d.query(`SELECT m.runtime, m.id, m.role, m.ts, bm25(chat_messages_fts) AS score,
      snippet(chat_messages_fts, 0, '«', '»', '…', 32) AS text
    FROM chat_messages_fts JOIN chat_messages m ON m.rowid = chat_messages_fts.rowid
    JOIN chat_sessions s ON s.runtime = m.runtime AND s.id = m.id
    WHERE chat_messages_fts MATCH ? AND (? OR s.kind IS 'user')
    ORDER BY score LIMIT 300`).all(ftsQuery(terms), all ? 1 : 0) as any[];
  const rows = new Map<string, any>();
  for (const h of hits) {
    const key = `${h.runtime}/${h.id}`;
    let row = rows.get(key);
    if (!row) {
      if (rows.size >= limit) continue;
      rows.set(key, (row = { runtime: h.runtime, id: h.id, score: Math.round(h.score * 1000) / 1000, excerpts: [] }));
    }
    if (row.excerpts.length < 3) row.excerpts.push({ role: h.role, ts: h.ts, text: redactExcerpt(h.text) });
  }
  for (const row of rows.values()) {
    const s = d.query("SELECT cwd, title, kind, last_ts FROM chat_sessions WHERE runtime=? AND id=?").get(row.runtime, row.id) as any;
    let ix: any = null;
    try { ix = JSON.parse(readFileSync(join(STORE, row.runtime, row.id, "index.json"), "utf8")); } catch {}
    const title = s?.title ?? ix?.title ?? null;
    Object.assign(row, {
      shortId: row.runtime === "codex" ? (row.id.match(UUID)?.[0] ?? row.id) : row.id,
      // The store's cwd, the one the resume plan starts in, so the row and the plan agree.
      title: title && redact(title).text, cwd: ix?.cwd ?? s?.cwd ?? null,
      cwdExists: isDir(ix?.cwd ?? s?.cwd),
      live: !!ix?.source && existsSync(ix.source),
      lastTs: s?.last_ts ?? ix?.versions?.at(-1)?.ts ?? null, kind: s?.kind ?? null,
    });
  }
  return [...rows.values()];
}

/// GET /sessions/search. federate (the default) also asks every hosts.json peer — with
/// federate=0, so none of them fans out again — and merges by score; a peer that is asleep
/// or predates chatSearch is named in `peers` as not ok, never an error.
export async function searchRoute(sp: URLSearchParams): Promise<{ results: any[]; peers: { host: string; ok: boolean }[] }> {
  const q = (sp.get("q") ?? "").trim();
  const limit = Math.min(100, Math.max(1, Number(sp.get("limit")) || 20));
  const all = sp.get("all") === "1";
  const cfg = await readHosts();
  const mine = new Set(Object.values(networkInterfaces()).flat().map((i) => i?.address));
  const self = (h: any) => mine.has(h?.ip) || h?.ip === "127.0.0.1" || h?.ip === "::1";
  // This machine by the name `mesh -H` knows it by, so a row's host can be passed back.
  const me = Object.entries<any>(cfg?.hosts ?? {}).find(([, h]) => self(h))?.[0] ?? hostname().split(".")[0];
  const results = search({ q, limit, all }).map((r) => ({ host: me, ...r }));
  const peers: { host: string; ok: boolean }[] = [];
  if (q && sp.get("federate") !== "0") {
    const qs = new URLSearchParams({ q, limit: String(limit), federate: "0", ...(all ? { all: "1" } : {}) });
    await Promise.all(Object.entries<any>(cfg?.hosts ?? {}).filter(([, h]) => h?.ip && !self(h)).map(async ([name, h]) => {
      const r = await fetch(`http://${h.ip}:${h.port || 8899}/sessions/search?${qs}`, {
        headers: h.token ? { authorization: `Bearer ${h.token}` } : {}, signal: AbortSignal.timeout(2500),
      }).then((x) => (x.ok ? x.json() : null)).catch(() => null) as any;
      peers.push({ host: name, ok: Array.isArray(r?.results) });
      for (const row of r?.results ?? []) results.push({ ...row, host: name });
    }));
  }
  results.sort((a, b) => a.score - b.score);
  return { results: results.slice(0, limit), peers };
}

// meshd KB — durable, searchable shared memory for agents (bun:sqlite + FTS5).
// Zero new deps. One file at ~/.mesh/kb.sqlite. Upsert by (scope,key) so repeated
// writes dedupe instead of bloating. Cross-machine search is read-federation in
// server.ts (each machine owns its own DB); this module is purely local.
// ponytail: SQLite FTS5 is the whole search engine — no embeddings/pgvector until
// proven needed. The HTTP+schema contract is the stable part; the engine can later
// become factory's Postgres+pgvector behind the same routes.
import { Database } from "bun:sqlite";
import { homedir } from "node:os";
import { join } from "node:path";
import { mkdirSync } from "node:fs";

const KB_PATH = process.env.MESHD_KB_PATH ?? join(homedir(), ".mesh", "kb.sqlite");
const MAX_BODY = 8192;
const MAX_TITLE = 500;
const COLS = "id,scope,kind,key,title,body,tags,source,host,created,updated";

export type KbEntry = {
  id: string; scope: string; kind: string | null; key: string;
  title: string | null; body: string | null; tags: string | null;
  source: string | null; host: string | null; created: string; updated: string;
};

let db: Database | null = null;
function getDb(): Database {
  if (db) return db;
  mkdirSync(join(homedir(), ".mesh"), { recursive: true });
  const d = new Database(KB_PATH, { create: true });
  d.exec("PRAGMA journal_mode = WAL;");
  d.exec(`
    CREATE TABLE IF NOT EXISTS entries(
      id TEXT PRIMARY KEY, scope TEXT NOT NULL, kind TEXT, key TEXT NOT NULL,
      title TEXT, body TEXT, tags TEXT, source TEXT, host TEXT,
      created TEXT, updated TEXT
    );
    CREATE UNIQUE INDEX IF NOT EXISTS entries_scope_key ON entries(scope, key);
    CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
      title, body, tags, content='entries', content_rowid='rowid'
    );
    CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
      INSERT INTO entries_fts(rowid, title, body, tags) VALUES (new.rowid, new.title, new.body, new.tags);
    END;
    CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
      INSERT INTO entries_fts(entries_fts, rowid, title, body, tags) VALUES('delete', old.rowid, old.title, old.body, old.tags);
    END;
    CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
      INSERT INTO entries_fts(entries_fts, rowid, title, body, tags) VALUES('delete', old.rowid, old.title, old.body, old.tags);
      INSERT INTO entries_fts(rowid, title, body, tags) VALUES (new.rowid, new.title, new.body, new.tags);
    END;
  `);
  db = d;
  return d;
}

export function kbPut(input: any, host: string): KbEntry {
  const now = new Date().toISOString();
  const scope = String(input.scope ?? "").trim();
  const key = String(input.key ?? "").trim();
  if (!scope || !key) throw new Error("scope and key are required");
  const tags = input.tags == null ? null
    : Array.isArray(input.tags) ? input.tags.join(" ") : String(input.tags);
  const d = getDb();
  d.query(`
    INSERT INTO entries(${COLS})
    VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(scope,key) DO UPDATE SET
      kind=excluded.kind, title=excluded.title, body=excluded.body,
      tags=excluded.tags, source=excluded.source, host=excluded.host, updated=excluded.updated
  `).run(
    String(input.id ?? `${scope}/${key}`),
    scope,
    input.kind != null ? String(input.kind) : null,
    key,
    input.title != null ? String(input.title).slice(0, MAX_TITLE) : null,
    input.body != null ? String(input.body).slice(0, MAX_BODY) : null,
    tags,
    input.source != null ? String(input.source) : null,
    host,
    now,
    now,
  );
  return kbGet(scope, key)!;
}

export function kbGet(scope: string, key: string): KbEntry | null {
  return (getDb().query(`SELECT ${COLS} FROM entries WHERE scope=? AND key=?`)
    .get(scope, key) as KbEntry | undefined) ?? null;
}

export function kbSearch(opts: { q?: string; scope?: string; kind?: string; limit?: number }): KbEntry[] {
  const d = getDb();
  const limit = Math.min(Math.max(Number(opts.limit ?? 30) || 30, 1), 200);
  const filters: string[] = [];
  const args: any[] = [];
  if (opts.scope) { filters.push("scope = ?"); args.push(opts.scope); }
  if (opts.kind) { filters.push("kind = ?"); args.push(opts.kind); }
  const q = (opts.q ?? "").trim();
  if (q) {
    const where = filters.map((f) => "e." + f).join(" AND ");
    const sql = `SELECT ${COLS.split(",").map((c) => "e." + c).join(",")}
      FROM entries_fts f JOIN entries e ON e.rowid = f.rowid
      WHERE entries_fts MATCH ?${where ? " AND " + where : ""}
      ORDER BY bm25(entries_fts) LIMIT ?`;
    return d.query(sql).all(ftsQuery(q), ...args, limit) as KbEntry[];
  }
  const where = filters.length ? "WHERE " + filters.join(" AND ") : "";
  return d.query(`SELECT ${COLS} FROM entries ${where} ORDER BY updated DESC LIMIT ?`)
    .all(...args, limit) as KbEntry[];
}

// Quote each term so arbitrary user text can't break FTS5 MATCH syntax; AND them.
function ftsQuery(q: string): string {
  const terms = q.split(/\s+/).filter(Boolean).map((t) => `"${t.replace(/"/g, '""')}"`);
  return terms.join(" ") || '""';
}

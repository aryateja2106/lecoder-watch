// One scripted step for an agent that already has a note on this machine.
// Read that note, ask the caller's own model for a draft, write that draft
// into one file in the caller's cwd, and stop. The file is not executed.
// A further command runs only when the caller passes confirm. That is the
// review-before-dispatch gate.
//
// The caller passes a base URL. modelClassOf already sorts that URL into
// "local" or "user-subscription". The daemon POSTs the note text to that
// URL's OpenAI-compatible /v1/chat/completions and stores the assistant
// text. A text/html body is the app source itself and is stored the same
// way. Anything that does not classify as one of those two is not fetched.
// The transcript records the class string only. The base URL and any key
// in it are not written, logged, or returned.
//
// file is an optional relative path and defaults to draft.txt. Absolute
// paths, "..", and any path that resolves outside cwd are refused.
//
//   POST /agent-note  { id?, q?, cwd, model, file?, command?, confirm? }
//        -> { modelClass, draft, commandRan, held }
//
// id alone is the note, as before. When id is absent, q selects one note
// with the same local-text refusal as knowledge search and the listNotes
// needle. One match continues this draft path. A note that names a pairing
// code, hosts.json, a mesh token, or .mesh/token is held before any model
// call. No match is 404. Several matches are 409 and are not guessed. An
// empty q is 400.
import { basename, dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { constants as fsConstants } from "node:fs";
import { chmod, lstat, mkdir, open, realpath, stat } from "node:fs/promises";
import { listNotes, readNote } from "./knowledge";

const FILE_MODE = 0o600;
const DRAFT_NAME = "draft.txt";
const MODEL_MS = 8_000;

export type ModelClass = "local" | "user-subscription";

class AgentNoteError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function isLocalHost(host: string): boolean {
  if (host === "localhost" || host === "127.0.0.1" || host === "::1" || host === "0.0.0.0") return true;
  if (host.endsWith(".localhost") || host.endsWith(".local")) return true;
  const parts = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!parts) return false;
  const n = parts.slice(1).map((x) => Number(x));
  if (n.some((x) => x > 255)) return false;
  const a = n[0];
  const b = n[1];
  if (a === 10 || a === 127) return true;
  if (a === 192 && b === 168) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 169 && b === 254) return true;
  return false;
}

// Classify in memory. The string the caller passed is not part of the result.
export function modelClassOf(model: string): ModelClass {
  const raw = model.trim();
  if (raw === "local" || raw === "user-subscription") return raw;
  let host = "";
  try {
    const withScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(raw) ? raw : `http://${raw}`;
    host = new URL(withScheme).hostname.replace(/^\[|\]$/g, "").toLowerCase();
  } catch {
    host = "";
  }
  return isLocalHost(host) ? "local" : "user-subscription";
}

// The caller's base URL, with any userinfo or query stripped so a key cannot
// ride along. Null means there is nothing we are willing to call.
export function completionsEndpoint(model: string): string | null {
  const raw = model.trim();
  if (!raw || raw === "local" || raw === "user-subscription") return null;
  const modelClass = modelClassOf(raw);
  if (modelClass !== "local" && modelClass !== "user-subscription") return null;
  let parsed: URL;
  try {
    const withScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(raw) ? raw : `http://${raw}`;
    parsed = new URL(withScheme);
  } catch {
    return null;
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
  if (!parsed.hostname) return null;
  parsed.username = "";
  parsed.password = "";
  parsed.search = "";
  parsed.hash = "";
  const path = parsed.pathname.replace(/\/+$/, "");
  if (path.endsWith("/chat/completions")) parsed.pathname = path;
  else if (path.endsWith("/v1")) parsed.pathname = `${path}/chat/completions`;
  else parsed.pathname = `${path}/v1/chat/completions`;
  return parsed.toString();
}

// Same refusal as knowledge search: a remote URL, a scheme, a
// protocol-relative value, or any string containing :// is not a needle.
// Empty means the caller passed no query. null means the query is refused.
function localNeedle(raw: string): string | null {
  const text = raw.trim();
  if (!text) return "";
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text) || text.startsWith("//") || text.includes("://")) return null;
  if (/^[a-z][a-z0-9+.-]*:/i.test(text)) return null;
  return text.toLowerCase();
}

// Same asks the local route holds, matched here so the daemon does not
// import that module. A clean note continues to the draft path.
function textHeldByRoute(value: string): boolean {
  if (/\bmesh\s+(?:token|bearer)\b/i.test(value)) return true;
  if (/\bpairing\s+code\b/i.test(value)) return true;
  if (/\bhosts\.json\b/.test(value)) return true;
  if (/\.mesh\/token\b/.test(value)) return true;
  return false;
}

function heldByRoute(note: { title: string; body: string }): boolean {
  return textHeldByRoute(note.title) || textHeldByRoute(note.body);
}

function noteText(note: { title: string; body: string }): string {
  const title = note.title.trim();
  const body = note.body.trim();
  return title ? `${title}\n\n${body}` : body;
}

function assistantText(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const choices = (payload as { choices?: unknown }).choices;
  if (!Array.isArray(choices) || choices.length === 0) return null;
  const message = (choices[0] as { message?: { content?: unknown } })?.message;
  const content = message?.content;
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return null;
  const parts: string[] = [];
  for (const part of content) {
    if (typeof part === "string") parts.push(part);
    else if (part && typeof part === "object" && typeof (part as { text?: unknown }).text === "string") {
      parts.push((part as { text: string }).text);
    }
  }
  return parts.length ? parts.join("") : null;
}

async function completeNote(endpoint: string, text: string, modelClass: ModelClass): Promise<string> {
  let res: Response;
  try {
    res = await fetch(endpoint, {
      method: "POST",
      redirect: "error",
      signal: AbortSignal.timeout(MODEL_MS),
      headers: { "content-type": "application/json", accept: "application/json, text/html" },
      body: JSON.stringify({
        model: modelClass,
        messages: [{ role: "user", content: text }],
      }),
    });
  } catch {
    throw new AgentNoteError("model request failed", 400);
  }
  if (!res.ok) {
    try { await res.body?.cancel(); } catch { /* the status is enough */ }
    throw new AgentNoteError("model request failed", 400);
  }
  let raw = "";
  try { raw = await res.text(); } catch {
    throw new AgentNoteError("model request failed", 400);
  }
  if (raw.length > 200_000) throw new AgentNoteError("model request failed", 400);
  // An HTML body is the app source. Store those bytes and do not run them.
  const contentType = (res.headers.get("content-type") ?? "").toLowerCase();
  if (contentType.includes("text/html")) {
    if (raw.length === 0) throw new AgentNoteError("model request failed", 400);
    return raw;
  }
  let payload: unknown;
  try { payload = JSON.parse(raw); } catch {
    throw new AgentNoteError("model request failed", 400);
  }
  const textOut = assistantText(payload);
  if (!textOut) throw new AgentNoteError("model request failed", 400);
  return textOut;
}

// The caller's file name, relative to cwd. Absolute paths and ".." are
// refused here, before the joined path is resolved.
function heldRelativeName(file: string | undefined): string {
  const raw = (file ?? "").trim();
  const name = raw.length === 0 ? DRAFT_NAME : raw;
  if (name.includes("\0")) throw new AgentNoteError("file must stay inside cwd", 400);
  if (isAbsolute(name) || name.startsWith("/") || name.startsWith("\\") || /^[A-Za-z]:[\\/]/.test(name)) {
    throw new AgentNoteError("file must stay inside cwd", 400);
  }
  const parts = name.split(/[\\/]+/);
  const kept: string[] = [];
  for (const part of parts) {
    if (part === "" || part === ".") continue;
    if (part === "..") throw new AgentNoteError("file must stay inside cwd", 400);
    kept.push(part);
  }
  if (kept.length === 0) throw new AgentNoteError("file must stay inside cwd", 400);
  return kept.join("/");
}

function pathInside(root: string, abs: string): boolean {
  const back = relative(root, abs);
  return Boolean(back) && back !== ".." && !back.startsWith(`..${sep}`) && !isAbsolute(back);
}

function ioCode(err: unknown): string {
  if (!err || typeof err !== "object" || !("code" in err)) return "";
  return String((err as { code?: unknown }).code ?? "");
}

// Join cwd and the relative name. realpath the deepest existing ancestor so
// a symlink chain cannot land the write outside cwd.
async function resolveHeldFile(cwd: string, file: string | undefined): Promise<{ abs: string; rel: string }> {
  const rel = heldRelativeName(file);
  const root = await realpath(cwd);
  const abs = resolve(root, rel);
  if (!pathInside(root, abs)) throw new AgentNoteError("file must stay inside cwd", 400);
  const landed = await landedHeldPath(root, abs);
  if (!pathInside(root, landed)) throw new AgentNoteError("file must stay inside cwd", 400);
  const back = relative(root, abs);
  return { abs, rel: back.split(sep).join("/") };
}

async function landedHeldPath(root: string, abs: string): Promise<string> {
  const missing: string[] = [];
  let cursor = abs;
  while (true) {
    let info;
    try {
      info = await lstat(cursor);
    } catch (err) {
      if (ioCode(err) !== "ENOENT") throw err;
      if (cursor === root) throw new AgentNoteError("file must stay inside cwd", 400);
      missing.unshift(basename(cursor));
      const parent = dirname(cursor);
      if (parent === cursor) throw new AgentNoteError("file must stay inside cwd", 400);
      cursor = parent;
      continue;
    }
    if (cursor === abs && info.isSymbolicLink()) throw new AgentNoteError("file must stay inside cwd", 400);
    const real = await realpath(cursor).catch(() => "");
    if (!real) throw new AgentNoteError("file must stay inside cwd", 400);
    return resolve(real, ...missing);
  }
}

// Store the assistant text. O_NOFOLLOW so a symlink cannot redirect the write.
async function writeHeldFile(abs: string, text: string): Promise<void> {
  const parent = dirname(abs);
  await mkdir(parent, { recursive: true, mode: 0o700 });
  const noFollow = typeof fsConstants.O_NOFOLLOW === "number" ? fsConstants.O_NOFOLLOW : 0;
  const flags = fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_TRUNC | noFollow;
  let fh;
  try {
    fh = await open(abs, flags, FILE_MODE);
  } catch (err) {
    if (ioCode(err) === "ELOOP") throw new AgentNoteError("file must stay inside cwd", 400);
    throw err;
  }
  try {
    await fh.writeFile(text);
  } finally {
    await fh.close();
  }
  await chmod(abs, FILE_MODE);
}

export async function runAgentNote(opts: {
  id: string;
  cwd: string;
  model: string;
  file?: string;
  command?: string;
  confirm?: boolean;
}): Promise<{ modelClass: ModelClass; draft: string; commandRan: boolean; held: boolean }> {
  if (!opts.model.trim()) throw new AgentNoteError("model required", 400);
  const modelClass = modelClassOf(opts.model);
  // Classification is the gate. A URL that is neither class is not called.
  if (modelClass !== "local" && modelClass !== "user-subscription") {
    throw new AgentNoteError("model url not allowed", 400);
  }
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(opts.cwd.trim())) throw new AgentNoteError("cwd must be a local directory", 400);
  const cwd = resolve(opts.cwd);
  const info = await stat(cwd).catch(() => null);
  if (!info) throw new AgentNoteError("cwd not found", 404);
  if (!info.isDirectory()) throw new AgentNoteError("cwd is not a directory", 400);
  // Refuse a path that leaves cwd before any model request.
  const heldFile = await resolveHeldFile(cwd, opts.file);
  const note = await readNote(opts.id);
  if (!note) throw new AgentNoteError("note not found", 404);
  const endpoint = completionsEndpoint(opts.model);
  if (!endpoint) throw new AgentNoteError("model url not allowed", 400);
  const assistant = await completeNote(endpoint, noteText(note), modelClass);
  await writeHeldFile(heldFile.abs, assistant);

  const command = opts.command?.trim() ?? "";
  if (!command) return { modelClass, draft: heldFile.rel, commandRan: false, held: false };
  // Review before dispatch: the file stays on disk. A shell command runs
  // only when the caller confirmed, and that command is not the file.
  if (opts.confirm !== true) return { modelClass, draft: heldFile.rel, commandRan: false, held: true };

  const proc = Bun.spawn(["/bin/sh", "-c", command], {
    cwd,
    stdin: "ignore",
    stdout: "ignore",
    stderr: "ignore",
  });
  const code = await proc.exited;
  if (code !== 0) throw new AgentNoteError("command failed", 400);
  return { modelClass, draft: heldFile.rel, commandRan: true, held: false };
}

export async function handleAgentNote(req: Request, url: URL): Promise<Response | null> {
  if (url.pathname !== "/agent-note") return null;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = (await req.json().catch(() => null)) as {
    id?: unknown;
    q?: unknown;
    cwd?: unknown;
    model?: unknown;
    file?: unknown;
    command?: unknown;
    confirm?: unknown;
  } | null;
  if (!body || typeof body.cwd !== "string" || !body.cwd.trim()) {
    return json({ error: "id and cwd required" }, 400);
  }
  if (typeof body.model !== "string") return json({ error: "model required" }, 400);
  if (body.file !== undefined && typeof body.file !== "string") return json({ error: "file must stay inside cwd" }, 400);
  const givenId = typeof body.id === "string" ? body.id.trim() : "";
  let id = givenId;
  if (!givenId) {
    if (typeof body.q !== "string") return json({ error: "id and cwd required" }, 400);
    const needle = localNeedle(body.q);
    if (needle === null) return json({ error: "query must be local text" }, 400);
    if (!needle) return json({ error: "q required" }, 400);
    const notes = await listNotes(needle);
    if (notes.length === 0) return json({ error: "note not found" }, 404);
    if (notes.length > 1) return json({ error: "more than one note" }, 409);
    id = notes[0].id;
    const note = await readNote(id);
    if (!note) return json({ error: "note not found" }, 404);
    if (heldByRoute(note)) {
      if (!body.model.trim()) return json({ error: "model required" }, 400);
      return json({ modelClass: modelClassOf(body.model), draft: null, commandRan: false, held: true });
    }
  }
  try {
    const result = await runAgentNote({
      id,
      cwd: body.cwd,
      model: body.model,
      file: typeof body.file === "string" ? body.file : undefined,
      command: typeof body.command === "string" ? body.command : undefined,
      confirm: body.confirm === true,
    });
    return json(result);
  } catch (err) {
    if (err instanceof AgentNoteError) return json({ error: err.message }, err.status);
    return json({ error: "failed" }, 400);
  }
}

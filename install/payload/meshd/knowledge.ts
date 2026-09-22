// Local notes for a later agent. A PDF that already lives on this machine
// becomes one file under the daemon state directory. Nothing in this module
// opens a socket: no Supabase client, no model call, no download.
//
//   POST /knowledge      { path, speak? } | { audio }  -> { id, title, spoken }
//   GET  /knowledge                        -> { notes: [{ id, title }] }
//   GET  /knowledge/:id                    -> { id, title, body }
//
// speak is optional. When it is true and MESH_TTS names a binary the user
// already has, that binary receives the note text on stdin. The note is
// written either way.
//
// audio is optional. When it names a local file and MESH_STT names a local
// binary, that binary is the only process started. Its stdout is the note
// body. A scheme:// value or any other remote URL is not started. A missing
// binary, a nonzero exit, or a transcript that is empty writes no note.
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import { chmod, mkdir, readdir, readFile, stat, writeFile } from "node:fs/promises";
import { inflateSync } from "node:zlib";

const DIR_MODE = 0o700;
const FILE_MODE = 0o600;
const MAX_PDF_BYTES = 20 * 1024 * 1024;
const MAX_TITLE = 200;
const MAX_BODY = 100_000;
const SPEAK_MS = 8_000;
const STT_MS = 8_000;

export function knowledgeDir(): string {
  const root = (process.env.MESHD_STATE ?? "").trim() || join(homedir(), ".mesh");
  return join(root, "knowledge");
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function latin1(bytes: Uint8Array): string {
  const parts: string[] = [];
  for (let i = 0; i < bytes.length; i += 8192) {
    parts.push(String.fromCharCode(...bytes.subarray(i, Math.min(bytes.length, i + 8192))));
  }
  return parts.join("");
}

function clip(text: string, max: number): string {
  return text.length > max ? text.slice(0, max) : text;
}

function unescapePdfString(inner: string): string {
  let out = "";
  for (let i = 0; i < inner.length; i++) {
    const c = inner[i];
    if (c !== "\\") { out += c; continue; }
    const n = inner[++i];
    if (n === undefined) break;
    if (n === "n") out += "\n";
    else if (n === "r") out += "\r";
    else if (n === "t") out += "\t";
    else if (n === "b") out += "\b";
    else if (n === "f") out += "\f";
    else if (n === "(" || n === ")" || n === "\\") out += n;
    else if (n >= "0" && n <= "7") {
      let oct = n;
      let k = 0;
      while (k < 2 && i + 1 < inner.length && inner[i + 1] >= "0" && inner[i + 1] <= "7") {
        oct += inner[++i];
        k++;
      }
      out += String.fromCharCode(parseInt(oct, 8));
    } else if (n === "\r") {
      if (inner[i + 1] === "\n") i++;
    } else if (n !== "\n") out += n;
  }
  return out;
}

function pdfTitle(text: string): string {
  const literal = text.match(/\/Title\s*(\((?:\\.|[^\\)])*\))/);
  if (literal) return unescapePdfString(literal[1].slice(1, -1));
  const hex = text.match(/\/Title\s*<([0-9A-Fa-f\s]+)>/);
  if (!hex) return "";
  const digits = hex[1].replace(/\s+/g, "");
  if (digits.length < 4 || digits.length % 2 !== 0) return "";
  const bytes = new Uint8Array(digits.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(digits.slice(i * 2, i * 2 + 2), 16);
  // PDF hex strings are UTF-16BE when they start with a BOM.
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    let out = "";
    for (let i = 2; i + 1 < bytes.length; i += 2) out += String.fromCharCode((bytes[i] << 8) | bytes[i + 1]);
    return out;
  }
  return latin1(bytes);
}

function shownText(text: string): string {
  const parts: string[] = [];
  const single = /\(((?:\\.|[^\\)])*)\)\s*Tj/g;
  let m: RegExpExecArray | null;
  while ((m = single.exec(text))) parts.push(unescapePdfString(m[1]));
  const arrays = /\[(?:\s|\S)*?\]\s*TJ/g;
  while ((m = arrays.exec(text))) {
    const inner = m[0];
    const strs = /\(((?:\\.|[^\\)])*)\)/g;
    let s: RegExpExecArray | null;
    const row: string[] = [];
    while ((s = strs.exec(inner))) row.push(unescapePdfString(s[1]));
    if (row.length) parts.push(row.join(""));
  }
  return parts.join("\n");
}

function inflatedStreams(bytes: Uint8Array): string[] {
  const buf = Buffer.from(bytes);
  const out: string[] = [];
  const needle = Buffer.from("stream");
  let from = 0;
  while (from < buf.length) {
    const at = buf.indexOf(needle, from);
    if (at < 0) break;
    const look = buf.subarray(Math.max(0, at - 400), at).toString("latin1");
    let start = at + needle.length;
    if (buf[start] === 0x0d && buf[start + 1] === 0x0a) start += 2;
    else if (buf[start] === 0x0a || buf[start] === 0x0d) start += 1;
    const end = buf.indexOf("endstream", start);
    if (end < 0) break;
    if (look.includes("/FlateDecode")) {
      let slice = buf.subarray(start, end);
      while (slice.length && (slice[slice.length - 1] === 0x0a || slice[slice.length - 1] === 0x0d)) {
        slice = slice.subarray(0, slice.length - 1);
      }
      try { out.push(inflateSync(slice).toString("latin1")); } catch { /* leave the raw bytes */ }
    }
    from = end + "endstream".length;
  }
  return out;
}

export function extractPdf(bytes: Uint8Array): { title: string; body: string } {
  const raw = latin1(bytes);
  const extra = inflatedStreams(bytes).join("\n");
  const all = extra ? `${raw}\n${extra}` : raw;
  const shown = shownText(all).replace(/\u0000/g, "").trim();
  const title = pdfTitle(all).replace(/\s+/g, " ").replace(/\u0000/g, "").trim();
  const fallback = shown.split("\n").map((line) => line.trim()).find(Boolean) ?? "";
  return {
    title: clip(title || fallback, MAX_TITLE),
    body: clip(shown, MAX_BODY),
  };
}

async function ensureDir(dir: string): Promise<void> {
  await mkdir(dir, { recursive: true, mode: DIR_MODE });
  // mkdir applies mode only as bits the umask leaves, and only on create.
  await chmod(dir, DIR_MODE);
}

export type NoteSummary = { id: string; title: string };

const NOTE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function readNote(id: string): Promise<{ id: string; title: string; body: string } | null> {
  let decoded = id;
  try { decoded = decodeURIComponent(id); } catch { return null; }
  if (!NOTE_ID.test(decoded)) return null;
  try {
    const raw = JSON.parse(await readFile(join(knowledgeDir(), `${decoded}.json`), "utf8"));
    if (raw?.id !== decoded || typeof raw.title !== "string" || typeof raw.body !== "string") return null;
    return { id: raw.id, title: raw.title, body: raw.body };
  } catch {
    return null;
  }
}

export async function listNotes(): Promise<NoteSummary[]> {
  let names: string[];
  try { names = await readdir(knowledgeDir()); } catch { return []; }
  const notes: NoteSummary[] = [];
  for (const name of names) {
    if (!name.endsWith(".json")) continue;
    try {
      const raw = JSON.parse(await readFile(join(knowledgeDir(), name), "utf8"));
      if (typeof raw?.id === "string" && typeof raw?.title === "string") {
        notes.push({ id: raw.id, title: raw.title });
      }
    } catch { /* a torn write is not a note */ }
  }
  notes.sort((a, b) => a.title.localeCompare(b.title) || a.id.localeCompare(b.id));
  return notes;
}

function isRemote(path: string): boolean {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(path.trim());
}

// scheme:// and a protocol-relative URL are not local files. A path that
// merely contains :// is treated the same way so a remote address cannot be
// handed to the transcriber.
function refusesRemote(value: string): boolean {
  const text = value.trim();
  return isRemote(text) || text.startsWith("//") || text.includes("://");
}

async function readCapped(stream: ReadableStream<Uint8Array>, max: number): Promise<string> {
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      const value = next.value;
      if (!value?.length || total >= max) continue;
      const room = max - total;
      const take = value.byteLength > room ? value.subarray(0, room) : value;
      chunks.push(take);
      total += take.byteLength;
    }
  } finally {
    try { reader.releaseLock(); } catch { /* already released */ }
  }
  const buf = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    buf.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(buf);
}

// Spawn only the local binary the caller named. A stuck transcriber is killed
// and its text is dropped: a killed run did not finish, so it is not a note.
async function runStt(bin: string, audioPath: string): Promise<string | null> {
  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn([bin, audioPath], {
      stdin: "ignore",
      stdout: "pipe",
      stderr: "ignore",
    });
  } catch {
    return null;
  }
  const killer = setTimeout(() => { try { proc.kill(); } catch { /* already gone */ } }, STT_MS);
  const stdout = proc.stdout;
  const textPromise = stdout
    ? readCapped(stdout, MAX_BODY).catch(() => "")
    : Promise.resolve("");
  const code = await proc.exited.catch(() => 1);
  clearTimeout(killer);
  const text = (await textPromise).replace(/\u0000/g, "").trim();
  if (code !== 0) return null;
  return text ? clip(text, MAX_BODY) : null;
}

async function ingestSpoken(audio: string): Promise<Response> {
  if (refusesRemote(audio)) return json({ error: "audio must be a local file" }, 400);
  const audioPath = resolve(audio.trim());
  const info = await stat(audioPath).catch(() => null);
  if (!info) return json({ error: "not found" }, 404);
  if (!info.isFile()) return json({ error: "not a file" }, 400);
  if (info.size > MAX_PDF_BYTES) return json({ error: "audio too large" }, 400);
  const bin = (process.env.MESH_STT ?? "").trim();
  if (!bin || refusesRemote(bin)) return json({ error: "stt must be a local binary" }, 400);
  const binPath = resolve(bin);
  const binInfo = await stat(binPath).catch(() => null);
  if (!binInfo?.isFile()) return json({ error: "stt unavailable" }, 400);
  const transcript = await runStt(binPath, audioPath);
  if (transcript === null) return json({ error: "stt failed" }, 400);
  const line = transcript.split("\n").map((part) => part.trim()).find(Boolean) ?? "";
  const title = clip(line.replace(/\s+/g, " "), MAX_TITLE) || basename(audioPath) || "note";
  const id = crypto.randomUUID();
  const dir = knowledgeDir();
  await ensureDir(dir);
  const file = join(dir, `${id}.json`);
  const note = {
    id,
    title,
    body: transcript,
    source: basename(audioPath),
    created: new Date().toISOString(),
  };
  await writeFile(file, `${JSON.stringify(note)}\n`, { mode: FILE_MODE });
  await chmod(file, FILE_MODE);
  await chmod(dir, DIR_MODE);
  return json({ id, title, spoken: false }, 201);
}

async function maybeSpeak(text: string, speak: boolean): Promise<boolean> {
  if (!speak) return false;
  const bin = (process.env.MESH_TTS ?? "").trim();
  if (!bin || isRemote(bin)) return false;
  const proc = Bun.spawn([bin], {
    stdin: new TextEncoder().encode(text),
    stdout: "ignore",
    stderr: "ignore",
  });
  const killer = setTimeout(() => { try { proc.kill(); } catch { /* already gone */ } }, SPEAK_MS);
  await proc.exited.catch(() => 1);
  clearTimeout(killer);
  return true;
}

async function ingest(req: Request): Promise<Response> {
  const body = (await req.json().catch(() => null)) as { path?: unknown; speak?: unknown; audio?: unknown } | null;
  if (body && typeof body.audio === "string" && body.audio.trim()) return ingestSpoken(body.audio);
  if (!body || typeof body.path !== "string" || !body.path.trim()) return json({ error: "path required" }, 400);
  if (isRemote(body.path)) return json({ error: "path must be a local file" }, 400);
  const filePath = resolve(body.path);
  const info = await stat(filePath).catch(() => null);
  if (!info) return json({ error: "not found" }, 404);
  if (!info.isFile()) return json({ error: "not a file" }, 400);
  if (info.size > MAX_PDF_BYTES) return json({ error: "pdf too large" }, 400);
  let bytes: Uint8Array;
  try { bytes = new Uint8Array(await readFile(filePath)); }
  catch (e: any) {
    if (e?.code === "ENOENT" || e?.code === "ENOTDIR") return json({ error: "not found" }, 404);
    return json({ error: "could not read pdf" }, 400);
  }
  if (!(bytes.length >= 5 && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46 && bytes[4] === 0x2d)) {
    return json({ error: "not a pdf" }, 400);
  }
  const extracted = extractPdf(bytes);
  const title = extracted.title || basename(filePath).replace(/\.pdf$/i, "") || "note";
  const id = crypto.randomUUID();
  const dir = knowledgeDir();
  await ensureDir(dir);
  const file = join(dir, `${id}.json`);
  const note = {
    id,
    title,
    body: extracted.body,
    source: basename(filePath),
    created: new Date().toISOString(),
  };
  await writeFile(file, `${JSON.stringify(note)}\n`, { mode: FILE_MODE });
  await chmod(file, FILE_MODE);
  await chmod(dir, DIR_MODE);
  const spoken = await maybeSpeak(`${note.title}\n${note.body}`.trim(), body.speak === true);
  return json({ id, title, spoken }, 201);
}

export async function handleKnowledge(req: Request, url: URL): Promise<Response | null> {
  const one = url.pathname.match(/^\/knowledge\/([^/]+)$/);
  if (one) {
    if (req.method !== "GET") return json({ error: "method not allowed" }, 405);
    const note = await readNote(one[1]);
    return note ? json(note) : json({ error: "not found" }, 404);
  }
  if (url.pathname !== "/knowledge") return null;
  if (req.method === "GET") return json({ notes: await listNotes() });
  if (req.method === "POST") return ingest(req);
  return json({ error: "method not allowed" }, 405);
}

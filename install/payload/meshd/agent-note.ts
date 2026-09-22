// One scripted step for an agent that already has a note on this machine.
// Read that note, write a single draft into the caller's cwd, and stop.
// A further command runs only when the caller passes confirm. That is the
// review-before-dispatch gate: the draft is for a person to read first.
//
// The model is recorded as a hostname class, "local" or "user-subscription".
// The base URL and any key in it are not written, logged, or returned.
//
//   POST /agent-note  { id, cwd, model, command?, confirm? }
//        -> { modelClass, draft, commandRan, held }
import { resolve } from "node:path";
import { chmod, stat, writeFile } from "node:fs/promises";
import { readNote } from "./knowledge";

const FILE_MODE = 0o600;
const DRAFT_NAME = "draft.txt";

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

export async function runAgentNote(opts: {
  id: string;
  cwd: string;
  model: string;
  command?: string;
  confirm?: boolean;
}): Promise<{ modelClass: ModelClass; draft: string; commandRan: boolean; held: boolean }> {
  if (!opts.model.trim()) throw new AgentNoteError("model required", 400);
  const modelClass = modelClassOf(opts.model);
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(opts.cwd.trim())) throw new AgentNoteError("cwd must be a local directory", 400);
  const cwd = resolve(opts.cwd);
  const info = await stat(cwd).catch(() => null);
  if (!info) throw new AgentNoteError("cwd not found", 404);
  if (!info.isDirectory()) throw new AgentNoteError("cwd is not a directory", 400);
  const note = await readNote(opts.id);
  if (!note) throw new AgentNoteError("note not found", 404);
  const draftPath = resolve(cwd, DRAFT_NAME);
  await writeFile(draftPath, `${note.title}\n\n${note.body}\n`, { mode: FILE_MODE });
  await chmod(draftPath, FILE_MODE);

  const command = opts.command?.trim() ?? "";
  if (!command) return { modelClass, draft: DRAFT_NAME, commandRan: false, held: false };
  // Review before dispatch: do not spawn unless the caller confirmed.
  if (opts.confirm !== true) return { modelClass, draft: DRAFT_NAME, commandRan: false, held: true };

  const proc = Bun.spawn(["/bin/sh", "-c", command], {
    cwd,
    stdin: "ignore",
    stdout: "ignore",
    stderr: "ignore",
  });
  const code = await proc.exited;
  if (code !== 0) throw new AgentNoteError("command failed", 400);
  return { modelClass, draft: DRAFT_NAME, commandRan: true, held: false };
}

export async function handleAgentNote(req: Request, url: URL): Promise<Response | null> {
  if (url.pathname !== "/agent-note") return null;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const body = (await req.json().catch(() => null)) as {
    id?: unknown;
    cwd?: unknown;
    model?: unknown;
    command?: unknown;
    confirm?: unknown;
  } | null;
  if (!body || typeof body.id !== "string" || !body.id.trim() || typeof body.cwd !== "string" || !body.cwd.trim()) {
    return json({ error: "id and cwd required" }, 400);
  }
  if (typeof body.model !== "string") return json({ error: "model required" }, 400);
  try {
    const result = await runAgentNote({
      id: body.id,
      cwd: body.cwd,
      model: body.model,
      command: typeof body.command === "string" ? body.command : undefined,
      confirm: body.confirm === true,
    });
    return json(result);
  } catch (err) {
    if (err instanceof AgentNoteError) return json({ error: err.message }, err.status);
    return json({ error: "failed" }, 400);
  }
}

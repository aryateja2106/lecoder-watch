// chat.ts — the structured view of an agent session, read from the agent's own transcript.
//
// Why a transcript and not the terminal: Claude Code and Codex draw full-screen TUIs, and a
// regex over capture-pane text guessed at markers (`<thinking>`, `$ `) that no agent prints.
// Both agents also write every turn to disk as JSONL — the user's prompt, the assistant's
// text, its thinking, every tool call and every tool result. Reading that file gives the
// phone the same conversation the Mac's screen shows, already structured, with no
// change to how the agent runs. The terminal mode still streams the real PTY beside it.
//
// Sources, in order: the transcript a mesh-hook event named for this session; else the
// newest Claude transcript for the pane's cwd; else the newest Codex rollout for it; else
// the newest cursor-agent transcript for it (same block shapes as Claude's, no timestamps);
// else `null`, and server.ts falls back to capture-pane lines as `source: "output"`.
//
// Every text field is redacted on the way out — a tool result is exactly where `cat .env`
// lands. Pure reads: nothing here starts, writes to or signals a session.
import { readdir, readFile, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { redact, record, type Finding } from "./redact";

export type ChatRole = "user" | "assistant" | "thinking" | "tool" | "result" | "system";
export type ChatMessage = {
  id: string;
  ts: string;
  role: ChatRole;
  text: string;
  tool?: { name: string; input: string };
  status?: "running" | "ok" | "error";
};
export type ChatPage = { name: string; source: "claude" | "codex" | "cursor" | "output" | "none"; cursor: string; messages: ChatMessage[] };

const CLAUDE_PROJECTS = process.env.MESH_CLAUDE_PROJECTS ?? join(homedir(), ".claude", "projects");
const CODEX_SESSIONS = process.env.MESH_CODEX_SESSIONS ?? join(process.env.CODEX_HOME ?? join(homedir(), ".codex"), "sessions");
const CURSOR_PROJECTS = process.env.MESH_CURSOR_PROJECTS ?? join(homedir(), ".cursor", "projects");
const TEXT_CAP = 2000;
const RESULT_CAP = 600;
const DEFAULT_LIMIT = 60;
const MAX_LIMIT = 200;
const OUTPUT_DEDUPE_MS = 10 * 60_000;

function clip(s: string, n: number): string {
  return s.length > n ? `${s.slice(0, n - 1)}…` : s;
}

/// Claude Code names a project folder after the cwd with every `/` and `.` turned into `-`
/// (`/Users/a/x/.claude/w` → `-Users-a-x--claude-w`). Measured on this machine, not inferred.
export function claudeProjectSlug(cwd: string): string {
  return cwd.replace(/[/.]/g, "-");
}

async function newestJsonl(dir: string, filter?: (name: string) => boolean): Promise<string | null> {
  const names = await readdir(dir).catch(() => [] as string[]);
  let best: { path: string; mtime: number } | null = null;
  for (const name of names) {
    if (!name.endsWith(".jsonl")) continue;
    if (filter && !filter(name)) continue;
    const path = join(dir, name);
    const st = await stat(path).catch(() => null);
    if (!st) continue;
    if (!best || st.mtimeMs > best.mtime) best = { path, mtime: st.mtimeMs };
  }
  return best?.path ?? null;
}

/// The newest Claude Code transcript for a working directory. Subagent transcripts are
/// their own files named `agent-…`; the main conversation is the one a person is having.
export async function findClaudeTranscript(cwd: string): Promise<string | null> {
  return newestJsonl(join(CLAUDE_PROJECTS, claudeProjectSlug(cwd)), (n) => !n.startsWith("agent-"));
}

/// cursor-agent keeps `~/.cursor/projects/<cwd minus its leading slash, "/" → "-">/
/// agent-transcripts/<chatId>/<chatId>.jsonl`, one `{role, message}` line per turn.
export function cursorProjectSlug(cwd: string): string {
  return cwd.replace(/^\//, "").replace(/\//g, "-");
}
export async function findCursorTranscript(cwd: string): Promise<string | null> {
  const root = join(CURSOR_PROJECTS, cursorProjectSlug(cwd), "agent-transcripts");
  let best: { path: string; mtime: number } | null = null;
  for (const chat of await readdir(root).catch(() => [] as string[])) {
    const path = await newestJsonl(join(root, chat));
    if (!path) continue;
    const st = await stat(path).catch(() => null);
    if (st && (!best || st.mtimeMs > best.mtime)) best = { path, mtime: st.mtimeMs };
  }
  return best?.path ?? null;
}

/// The newest Codex rollout whose session_meta.cwd is this directory. Rollouts live in
/// sessions/YYYY/MM/DD/rollout-<ts>-<id>.jsonl; only the last two days are scanned.
export async function findCodexRollout(cwd: string): Promise<string | null> {
  const days: string[] = [];
  for (let back = 0; back < 2; back++) {
    const d = new Date(Date.now() - back * 86_400_000);
    days.push(join(CODEX_SESSIONS, String(d.getUTCFullYear()), String(d.getUTCMonth() + 1).padStart(2, "0"), String(d.getUTCDate()).padStart(2, "0")));
  }
  let best: { path: string; mtime: number } | null = null;
  for (const dir of days) {
    for (const name of await readdir(dir).catch(() => [] as string[])) {
      if (!name.endsWith(".jsonl")) continue;
      const path = join(dir, name);
      const st = await stat(path).catch(() => null);
      if (!st || (best && st.mtimeMs <= best.mtime)) continue;
      const head = await readHead(path, 4096);
      const meta = head.split("\n").map(parseLine).find((l) => l?.type === "session_meta");
      if (meta?.payload?.cwd === cwd) best = { path, mtime: st.mtimeMs };
    }
  }
  return best?.path ?? null;
}

async function readHead(path: string, bytes: number): Promise<string> {
  const file = Bun.file(path);
  return await file.slice(0, bytes).text().catch(() => "");
}

function parseLine(line: string): any | null {
  if (!line) return null;
  try { return JSON.parse(line); } catch { return null; }
}

/// One-line summary of a tool call's input, so a card reads like a sentence.
function toolInputSummary(name: string, input: any): string {
  if (input == null) return "";
  if (typeof input === "string") return clip(input, 160);
  const pick = input.command ?? input.cmd ?? input.file_path ?? input.path ?? input.pattern ?? input.query ?? input.url ?? input.prompt ?? input.description;
  if (typeof pick === "string") return clip(pick.replace(/\s+/g, " ").trim(), 160);
  if (name.toLowerCase().includes("exec") && typeof input.arguments === "string") return clip(input.arguments, 160);
  return clip(JSON.stringify(input), 160);
}

// ---------- Claude Code ----------
export function parseClaudeTranscript(raw: string): ChatMessage[] {
  const out: ChatMessage[] = [];
  const toolIndex = new Map<string, number>(); // tool_use id → index in out
  let n = 0;
  for (const lineText of raw.split("\n")) {
    const line = parseLine(lineText);
    if (!line || line.isSidechain) continue;
    const kind = line.type ?? line.role; // Claude Code: type; cursor-agent: role
    if (kind !== "user" && kind !== "assistant") continue;
    line.type = kind;
    const ts = String(line.timestamp ?? "");
    const base = String(line.uuid ?? `${ts}-${n}`);
    const content = line.message?.content;
    const blocks: any[] = Array.isArray(content) ? content : typeof content === "string" ? [{ type: "text", text: content }] : [];
    let i = 0;
    for (const block of blocks) {
      const id = `${base}:${i++}`;
      if (block?.type === "text" && line.type === "user") {
        const text = String(block.text ?? "").trim();
        // Claude Code injects its own bracketed system notes into the user turn.
        if (!text || /^<(system-reminder|command-|local-command)/.test(text)) continue;
        out.push({ id, ts, role: "user", text: clip(text, TEXT_CAP) });
      } else if (block?.type === "text") {
        const text = String(block.text ?? "").trim();
        if (text) out.push({ id, ts, role: "assistant", text: clip(text, TEXT_CAP) });
      } else if (block?.type === "thinking") {
        const text = String(block.thinking ?? "").trim();
        if (text) out.push({ id, ts, role: "thinking", text: clip(text, TEXT_CAP) });
      } else if (block?.type === "tool_use") {
        const name = String(block.name ?? "tool");
        toolIndex.set(String(block.id ?? ""), out.length);
        out.push({ id, ts, role: "tool", text: `${name}`, tool: { name, input: toolInputSummary(name, block.input) }, status: "running" });
      } else if (block?.type === "tool_result") {
        const idx = toolIndex.get(String(block.tool_use_id ?? ""));
        const status = block.is_error ? "error" : "ok";
        if (idx !== undefined && out[idx]) out[idx].status = status;
        const body = Array.isArray(block.content)
          ? block.content.map((c: any) => (typeof c === "string" ? c : c?.text ?? "")).join("\n")
          : String(block.content ?? "");
        const text = body.trim();
        if (text) out.push({ id, ts, role: "result", text: clip(text, RESULT_CAP), status });
      }
    }
    n++;
  }
  return out;
}

// ---------- Codex ----------
export function parseCodexRollout(raw: string): ChatMessage[] {
  const out: ChatMessage[] = [];
  const callIndex = new Map<string, number>();
  let n = 0;
  for (const lineText of raw.split("\n")) {
    const line = parseLine(lineText);
    if (!line || line.type !== "response_item") continue;
    const p = line.payload ?? {};
    const ts = String(line.timestamp ?? p.timestamp ?? "");
    const id = String(p.id ?? p.call_id ?? `codex-${n}`);
    n++;
    if (p.type === "message") {
      const text = (Array.isArray(p.content) ? p.content : [])
        .map((c: any) => (typeof c === "string" ? c : c?.text ?? ""))
        .join("\n").trim();
      if (!text) continue;
      // Codex prefixes its own instructions/context into some user messages.
      if (p.role === "user" && /^<(environment_context|user_instructions|permissions instructions)/i.test(text)) continue;
      out.push({ id, ts, role: p.role === "user" ? "user" : "assistant", text: clip(text, TEXT_CAP) });
    } else if (p.type === "reasoning") {
      const text = (Array.isArray(p.summary) ? p.summary : [])
        .map((s: any) => (typeof s === "string" ? s : s?.text ?? "")).join("\n").trim();
      if (text) out.push({ id, ts, role: "thinking", text: clip(text, TEXT_CAP) });
    } else if (p.type === "custom_tool_call" || p.type === "function_call") {
      const name = String(p.name ?? "tool");
      let input: any = p.input ?? p.arguments ?? "";
      if (typeof input === "string" && input.startsWith("{")) { try { input = JSON.parse(input); } catch { /* keep the string */ } }
      callIndex.set(String(p.call_id ?? id), out.length);
      out.push({ id, ts, role: "tool", text: name, tool: { name, input: toolInputSummary(name, input) }, status: "running" });
    } else if (p.type === "custom_tool_call_output" || p.type === "function_call_output") {
      const idx = callIndex.get(String(p.call_id ?? ""));
      let output: any = p.output ?? "";
      if (typeof output === "string" && output.startsWith("[")) {
        try { output = (JSON.parse(output) as any[]).map((c) => c?.text ?? "").join("\n"); } catch { /* raw */ }
      }
      const text = String(output).trim();
      const status = /error|failed|exit code [1-9]/i.test(text.slice(0, 200)) ? "error" : "ok";
      if (idx !== undefined && out[idx]) out[idx].status = status;
      if (text) out.push({ id, ts, role: "result", text: clip(text, RESULT_CAP), status });
    }
  }
  return out;
}

// ---------- assembly ----------
export type ChatDeps = {
  /// The transcript path a hook event named for this session, if any.
  transcriptHint: (session: string) => string | undefined;
  /// The pane's current working directory, or null when the mux cannot say.
  cwdOf: (session: string) => Promise<string | null>;
  /// "claude" | "codex" | anything else, from the pane's running command.
  agentTypeOf: (session: string) => Promise<string | undefined>;
};

function redactAll(messages: ChatMessage[]): ChatMessage[] {
  const findings: Finding[] = [];
  const clean = messages.map((m) => {
    const r = redact(m.text);
    findings.push(...r.findings);
    const tool = m.tool ? { name: m.tool.name, input: (() => { const t = redact(m.tool.input); findings.push(...t.findings); return t.text; })() } : undefined;
    return { ...m, text: r.text, ...(tool ? { tool } : {}) };
  });
  if (findings.length) record(findings, "output", OUTPUT_DEDUPE_MS).catch(() => {});
  return clean;
}

function page(name: string, source: ChatPage["source"], all: ChatMessage[], since: string | null, limit: number): ChatPage {
  // A tool call that anything followed is finished. Claude Code writes a tool_result that
  // settles this exactly; cursor-agent's transcript has no result blocks, so without this
  // every one of its cards would say "running" forever.
  for (let i = 0; i < all.length - 1; i++) if (all[i].role === "tool" && all[i].status === "running") all[i].status = "ok";
  let start = 0;
  if (since) {
    const idx = all.findIndex((m) => m.id === since);
    if (idx >= 0) start = idx + 1;
  }
  const slice = all.slice(start);
  const messages = redactAll(slice.slice(-limit));
  const cursor = all.length ? all[all.length - 1].id : since ?? "";
  return { name, source, cursor, messages };
}

/// The chat page for a session, or null when no transcript can be found (the caller then
/// serves capture-pane lines instead).
export async function chatFor(name: string, since: string | null, limitRaw: number | null, deps: ChatDeps): Promise<ChatPage | null> {
  const limit = Math.min(MAX_LIMIT, Math.max(1, limitRaw ?? DEFAULT_LIMIT));
  const hinted = deps.transcriptHint(name);
  if (hinted) {
    const raw = await readFile(hinted, "utf8").catch(() => "");
    if (raw) {
      const isCodex = hinted.includes("/rollout-") || /"type":"session_meta"/.test(raw.slice(0, 2048));
      return page(name, isCodex ? "codex" : "claude", isCodex ? parseCodexRollout(raw) : parseClaudeTranscript(raw), since, limit);
    }
  }
  const cwd = await deps.cwdOf(name);
  if (!cwd) return null;
  const kind = (await deps.agentTypeOf(name))?.toLowerCase() ?? "";
  const all: Array<"claude" | "codex" | "cursor"> = ["claude", "codex", "cursor"];
  const first = all.find((s) => kind.includes(s));
  const order = first ? [first, ...all.filter((s) => s !== first)] : all;
  for (const source of order) {
    const path = source === "claude" ? await findClaudeTranscript(cwd) : source === "codex" ? await findCodexRollout(cwd) : await findCursorTranscript(cwd);
    if (!path) continue;
    // A transcript older than a day for this cwd is a different conversation, not this pane's.
    const st = await stat(path).catch(() => null);
    if (!st || Date.now() - st.mtimeMs > 86_400_000) continue;
    const raw = await readFile(path, "utf8").catch(() => "");
    if (!raw) continue;
    return page(name, source, source === "codex" ? parseCodexRollout(raw) : parseClaudeTranscript(raw), since, limit);
  }
  return null;
}

/// Turn capture-pane lines into a one-message page so clients have one shape to render.
export function outputPage(name: string, lines: string[]): ChatPage {
  const text = lines.join("\n").replace(/\n+$/, "");
  const messages = text ? redactAll([{ id: `output-${lines.length}-${text.length}`, ts: new Date().toISOString(), role: "system", text: clip(text, TEXT_CAP * 4) }]) : [];
  return { name, source: "output", cursor: messages[0]?.id ?? "", messages };
}

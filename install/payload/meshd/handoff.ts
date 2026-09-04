// handoff.ts — move a task between agents, and pick a conversation back up.
//
// Two asks from the first device day. "I started with Claude Code and mid-session I want a
// different harness to pick it up" — a hand-off: the conversation so far is written to
// HANDOFF.md in the working directory (the one file every CLI agent can read), the current
// agent is interrupted, and the chosen CLI is launched in the same pane with the instruction
// to continue from that file. OMP can import a Claude Code session directly, so it gets the
// transcript path instead. "Resume a session from the phone" — a list of the conversations
// each CLI kept for a directory, with the exact command that reopens each one.
//
// Nothing here parses terminal output. Conversations come from chat.ts; keystrokes go
// through the same send route the phone already uses.
import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { type ChatMessage, type ChatPage, claudeProjectSlug, cursorProjectSlug } from "./chat";

export type ResumableKind = "claude" | "codex" | "cursor";
export type Resumable = { kind: ResumableKind; id: string; title: string; updated: string; cmd: string };

const CLAUDE_PROJECTS = process.env.MESH_CLAUDE_PROJECTS ?? join(homedir(), ".claude", "projects");
const CODEX_SESSIONS = process.env.MESH_CODEX_SESSIONS ?? join(process.env.CODEX_HOME ?? join(homedir(), ".codex"), "sessions");
const CURSOR_PROJECTS = process.env.MESH_CURSOR_PROJECTS ?? join(homedir(), ".cursor", "projects");
const PER_KIND = 8;

/// The agents a session can be handed to, and how each is started in a shell.
export const HANDOFF_TARGETS = ["claude", "codex", "cursor-agent", "omp", "agy", "hermes"] as const;
export type HandoffTarget = (typeof HANDOFF_TARGETS)[number];

const CONTINUE = "Read HANDOFF.md in this folder and continue the task from where it stopped.";
/// A target's own conversation in this directory is resumed when it is this fresh —
/// the hand-off then lands on top of the context that CLI already had, which is what
/// "hand it back to Claude" means. Older than this, a fresh start reads better than a
/// week-old chat.
const RESUME_WINDOW_MS = 24 * 3600_000;

function shellQuote(s: string): string {
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

/// The command that launches `to` with the hand-off already in hand. CLIs that take an
/// initial prompt get it on the command line; the rest are started bare and told after
/// their prompt appears (see handoff()). OMP imports a Claude Code transcript directly.
/// `resumeId` reopens the target's own recent conversation first; `bin` is the absolute
/// path, since a respawned pane does not have the user's shell PATH.
export function launchCommand(to: HandoffTarget, source: ChatPage["source"], transcriptPath?: string, resumeId?: string, bin?: string): { cmd: string; tellAfter: boolean } {
  const b = bin ?? to;
  switch (to) {
    case "claude": return { cmd: `${b} ${resumeId ? `--resume ${shellQuote(resumeId)} ` : ""}${shellQuote(CONTINUE)}`, tellAfter: false };
    case "codex": return resumeId
      ? { cmd: `${b} resume ${shellQuote(resumeId)}`, tellAfter: true }
      : { cmd: `${b} ${shellQuote(CONTINUE)}`, tellAfter: false };
    case "cursor-agent": return { cmd: `${b} ${resumeId ? `--resume ${shellQuote(resumeId)} ` : ""}${shellQuote(CONTINUE)}`, tellAfter: false };
    case "omp":
      return source === "claude" && transcriptPath
        ? { cmd: `${b} --from-claude ${shellQuote(transcriptPath)}`, tellAfter: true }
        : { cmd: b, tellAfter: true };
    case "agy": return { cmd: b, tellAfter: true };
    case "hermes": return { cmd: b, tellAfter: true };
  }
}

const RESUME_KIND: Partial<Record<HandoffTarget, ResumableKind>> = { claude: "claude", codex: "codex", "cursor-agent": "cursor" };

/// The target's newest conversation for this directory, if it is recent enough to resume.
export async function resumeFor(to: HandoffTarget, cwd: string, now = Date.now()): Promise<Resumable | undefined> {
  const kind = RESUME_KIND[to];
  if (!kind) return undefined;
  const mine = (await listResumable(cwd)).filter((r) => r.kind === kind);
  const newest = mine[0];
  if (!newest || now - Date.parse(newest.updated) > RESUME_WINDOW_MS) return undefined;
  return newest;
}

/// HANDOFF.md: enough for a fresh agent to continue, short enough to read in one screen.
export function handoffMarkdown(session: string, page: ChatPage, now = new Date()): string {
  const msgs = page.messages;
  const lastAssistant = [...msgs].reverse().find((m) => m.role === "assistant")?.text ?? "";
  const turns = msgs.filter((m) => m.role === "user" || m.role === "assistant").slice(-30);
  const tools = msgs.filter((m) => m.role === "tool").slice(-15);
  const lines: string[] = [];
  lines.push(`# Hand-off from session \`${session}\``);
  lines.push("");
  lines.push(`Written ${now.toISOString()} by LeSearch Mesh from the ${page.source} transcript. Continue the task; do not restart it.`);
  lines.push("");
  lines.push("## Where it stopped");
  lines.push("");
  lines.push(lastAssistant ? lastAssistant.trim() : "(no assistant message yet)");
  lines.push("");
  lines.push("## Conversation so far (last 30 turns)");
  lines.push("");
  for (const m of turns) {
    lines.push(`**${m.role === "user" ? "User" : "Agent"}:** ${m.text.trim().replace(/\n{3,}/g, "\n\n")}`);
    lines.push("");
  }
  if (tools.length) {
    lines.push("## Recent tool activity");
    lines.push("");
    for (const t of tools) lines.push(`- ${t.tool?.name ?? t.text}${t.tool?.input ? `: ${t.tool.input}` : ""}${t.status ? ` (${t.status})` : ""}`);
    lines.push("");
  }
  return lines.join("\n");
}

// ---------- resumable conversations ----------
async function firstUserText(path: string, pick: (line: any) => string | undefined): Promise<string> {
  const head = await Bun.file(path).slice(0, 65536).text().catch(() => "");
  for (const raw of head.split("\n")) {
    if (!raw) continue;
    let line: any;
    try { line = JSON.parse(raw); } catch { continue; }
    const t = pick(line);
    if (t && t.trim() && !/^<(system-reminder|command-|local-command|environment_context|user_instructions)/.test(t.trim())) {
      return t.trim().replace(/\s+/g, " ").slice(0, 80);
    }
  }
  return "";
}

function claudeUserText(line: any): string | undefined {
  if (line?.type !== "user") return undefined;
  const c = line.message?.content;
  if (typeof c === "string") return c;
  if (Array.isArray(c)) return c.find((b: any) => b?.type === "text")?.text;
  return undefined;
}

export async function listResumable(cwd: string): Promise<Resumable[]> {
  const out: Resumable[] = [];
  // Claude Code: one file per session under the project folder.
  const cdir = join(CLAUDE_PROJECTS, claudeProjectSlug(cwd));
  for (const name of await readdir(cdir).catch(() => [] as string[])) {
    if (!name.endsWith(".jsonl") || name.startsWith("agent-")) continue;
    const path = join(cdir, name);
    const st = await stat(path).catch(() => null);
    if (!st) continue;
    const id = basename(name, ".jsonl");
    out.push({ kind: "claude", id, title: await firstUserText(path, claudeUserText), updated: st.mtime.toISOString(), cmd: `claude --resume ${id}` });
  }
  // Codex: rollouts in date folders; session_meta names the cwd and the id.
  for (let back = 0; back < 7; back++) {
    const d = new Date(Date.now() - back * 86_400_000);
    const dir = join(CODEX_SESSIONS, String(d.getUTCFullYear()), String(d.getUTCMonth() + 1).padStart(2, "0"), String(d.getUTCDate()).padStart(2, "0"));
    for (const name of await readdir(dir).catch(() => [] as string[])) {
      if (!name.endsWith(".jsonl")) continue;
      const path = join(dir, name);
      const head = await Bun.file(path).slice(0, 8192).text().catch(() => "");
      let meta: any = null;
      for (const raw of head.split("\n")) { try { const l = JSON.parse(raw); if (l?.type === "session_meta") { meta = l.payload; break; } } catch { /* skip */ } }
      if (!meta || meta.cwd !== cwd || !meta.id) continue;
      const st = await stat(path).catch(() => null);
      if (!st) continue;
      const title = await firstUserText(path, (l) => (l?.type === "response_item" && l.payload?.type === "message" && l.payload.role === "user")
        ? (Array.isArray(l.payload.content) ? l.payload.content.map((c: any) => c?.text ?? "").join(" ") : "") : undefined);
      out.push({ kind: "codex", id: String(meta.id), title, updated: st.mtime.toISOString(), cmd: `codex resume ${meta.id}` });
    }
  }
  // cursor-agent: one folder per chat under the project's agent-transcripts.
  const root = join(CURSOR_PROJECTS, cursorProjectSlug(cwd), "agent-transcripts");
  for (const chat of await readdir(root).catch(() => [] as string[])) {
    const path = join(root, chat, `${chat}.jsonl`);
    const st = await stat(path).catch(() => null);
    if (!st) continue;
    out.push({ kind: "cursor", id: chat, title: await firstUserText(path, (l) => (l?.role === "user" ? claudeUserText({ type: "user", message: l.message }) : undefined)), updated: st.mtime.toISOString(), cmd: `cursor-agent --resume ${chat}` });
  }
  // Newest first, a handful per kind — a phone list, not an archive.
  const byKind = new Map<ResumableKind, Resumable[]>();
  for (const r of out.sort((a, b) => (a.updated < b.updated ? 1 : -1))) {
    const list = byKind.get(r.kind) ?? [];
    if (list.length < PER_KIND) list.push(r);
    byKind.set(r.kind, list);
  }
  return [...byKind.values()].flat().sort((a, b) => (a.updated < b.updated ? 1 : -1));
}

// ---------- the hand-off itself ----------
/// One pane of a session, with the agent the daemon found running in it (from the
/// process tree, not the pane title: Claude Code's pane command reads as its version
/// number and cursor-agent's as `node`).
export type PaneInfo = { id: string; active: boolean; agent?: string };

export type HandoffDeps = {
  cwdOf: (session: string) => Promise<string | null>;
  transcriptHint: (session: string) => string | undefined;
  chat: (session: string) => Promise<ChatPage | null>;
  send: (session: string, text?: string, key?: string, pane?: string) => Promise<{ ok: boolean; error?: string }>;
  which: (bin: string) => string | null;
  /// The session's panes, or null when the multiplexer cannot be asked (herdr, cmux).
  panes?: (session: string) => Promise<PaneInfo[] | null>;
  /// Replace whatever runs in a pane with `cmd`, in `cwd` — the multiplexer kills the
  /// old process itself, so nothing depends on how an agent reacts to Ctrl-C.
  respawn?: (pane: string, cwd: string, cmd: string) => Promise<{ ok: boolean; error?: string }>;
};

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

/// The pane to hand over: the one running the agent whose conversation is being handed
/// off, else the active pane if an agent runs there, else the first pane with an agent,
/// else the active pane. A session can hold two agents (the one handed off earlier is
/// often still there) plus a shell pane split off from the phone; the hand-off must
/// land on the agent that owns the conversation.
export function pickPane(panes: PaneInfo[], source?: ChatPage["source"]): PaneInfo | undefined {
  const owner = source === "claude" ? "claude" : source === "codex" ? "codex" : source === "cursor" ? "cursor-agent" : undefined;
  return (owner && panes.find((p) => p.agent === owner))
    ?? panes.find((p) => p.active && p.agent) ?? panes.find((p) => p.agent) ?? panes.find((p) => p.active) ?? panes[0];
}

export type HandoffResult = { ok: boolean; error?: string; file?: string; cmd?: string; pane?: string; resumed?: string };

export async function handoff(session: string, to: string, deps: HandoffDeps): Promise<HandoffResult> {
  if (!(HANDOFF_TARGETS as readonly string[]).includes(to)) return { ok: false, error: `unknown agent: ${to}` };
  const target = to as HandoffTarget;
  const bin = deps.which(target);
  if (!bin) return { ok: false, error: `${target} is not installed on this machine` };
  const cwd = await deps.cwdOf(session);
  if (!cwd) return { ok: false, error: "the session's working directory is unknown" };
  const page = await deps.chat(session);
  if (!page || !page.messages.length) return { ok: false, error: "nothing to hand off yet — the session has no conversation" };
  const file = join(cwd, "HANDOFF.md");
  try {
    await writeFile(file, handoffMarkdown(session, page), { mode: 0o644 });
  } catch (e: any) {
    return { ok: false, error: `could not write ${file}: ${e?.message ?? e}` };
  }
  const resume = await resumeFor(target, cwd);
  const { cmd, tellAfter } = launchCommand(target, page.source, deps.transcriptHint(session), resume?.id, bin);

  // The sure path: the multiplexer replaces the pane's process with the new agent.
  // The first version typed Ctrl-C twice and then the launch line, and on a phone that
  // line landed INSIDE the old agent as a prompt — an approval dialog eats the first
  // interrupt, and no CLI here promises to exit on the second.
  const panes = deps.panes ? await deps.panes(session) : null;
  if (panes?.length && deps.respawn) {
    const pane = pickPane(panes, page.source)!;
    const r = await deps.respawn(pane.id, cwd, cmd);
    if (!r.ok) return { ok: false, error: r.error ?? "could not restart the pane" };
    if (tellAfter) {
      await wait(5000);
      await deps.send(session, CONTINUE, undefined, pane.id);
      await deps.send(session, undefined, "enter", pane.id);
    }
    return { ok: true, file, cmd, pane: pane.id, resumed: resume?.id };
  }

  // Panes the daemon cannot respawn (herdr, cmux): keystrokes, best effort.
  for (const _ of [0, 1]) {
    const r = await deps.send(session, undefined, "ctrl-c");
    if (!r.ok) return { ok: false, error: r.error };
    await wait(450);
  }
  await wait(900);
  const typed = await deps.send(session, cmd);
  if (!typed.ok) return { ok: false, error: typed.error };
  await deps.send(session, undefined, "enter");
  if (tellAfter) {
    // No prompt argument for this CLI: give it a moment to draw its prompt, then say it.
    await wait(5000);
    await deps.send(session, CONTINUE);
    await deps.send(session, undefined, "enter");
  }
  return { ok: true, file, cmd, resumed: resume?.id };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

/// GET /resumable?cwd=  · GET /agents/:n/resumable · POST /agents/:n/handoff {to}
export async function handleHandoff(req: Request, url: URL, deps: HandoffDeps): Promise<Response | null> {
  if (url.pathname === "/resumable" && req.method === "GET") {
    const cwd = url.searchParams.get("cwd") ?? "";
    if (!cwd.startsWith("/")) return json({ error: "cwd must be an absolute path" }, 400);
    return json({ cwd, items: await listResumable(cwd), targets: HANDOFF_TARGETS.filter((t) => deps.which(t)) });
  }
  const rm = url.pathname.match(/^\/agents\/([^/]+)\/resumable$/);
  if (rm && req.method === "GET") {
    const cwd = await deps.cwdOf(decodeURIComponent(rm[1]));
    if (!cwd) return json({ error: "the session's working directory is unknown" }, 404);
    return json({ cwd, items: await listResumable(cwd), targets: HANDOFF_TARGETS.filter((t) => deps.which(t)) });
  }
  const hm = url.pathname.match(/^\/agents\/([^/]+)\/handoff$/);
  if (hm && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as { to?: string };
    const result = await handoff(decodeURIComponent(hm[1]), String(body.to ?? ""), deps);
    return json(result, result.ok ? 200 : 400);
  }
  return null;
}

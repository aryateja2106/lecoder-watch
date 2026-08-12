// Orca (github.com/stablyai/orca) adapter — surfaces Orca's agent terminals as
// meshd agents so the phone and watch see them next to rmux/cmux sessions.
//
// Integration seam is the bundled `orca` CLI with --json, which Orca ships as its
// documented agent-facing contract (`orca agent-context --json`). The WebSocket on
// :6768 is deliberately NOT used: it is end-to-end encrypted with an undocumented
// e2ee_hello handshake, and its daemon socket name embeds a PID that changes on
// every restart.
//
// Everything here degrades to empty/false when Orca is absent, so a machine
// without Orca is unaffected.

const ORCA: string = process.env.ORCA_BIN ?? "orca";
const PREFIX = "orca:";
// Each `orca` invocation boots an Electron-as-node process, so it is slow and must
// never be allowed to stall meshd's poll loop.
const TIMEOUT_MS = Number(process.env.ORCA_TIMEOUT_MS ?? "6000");
const LIST_TTL_MS = Number(process.env.ORCA_LIST_TTL_MS ?? "3000");

export function isOrcaAgent(name: string): boolean {
  return name.startsWith(PREFIX);
}
function handleOf(name: string): string {
  return name.slice(PREFIX.length);
}

/** Run `orca … --json` with argv (no shell, so nothing needs quoting). */
async function orcaJson(args: string[]): Promise<any | null> {
  try {
    const proc = Bun.spawn([ORCA, ...args, "--json"], { stdout: "pipe", stderr: "ignore" });
    const timer = setTimeout(() => { try { proc.kill(); } catch {} }, TIMEOUT_MS);
    const text = await new Response(proc.stdout).text();
    await proc.exited;
    clearTimeout(timer);
    if (!text.trim()) return null;
    const parsed = JSON.parse(text);
    // Orca envelopes every response as { ok, result, ... }.
    return parsed?.ok ? parsed.result ?? null : null;
  } catch {
    return null; // orca not installed, not running, or output was not JSON
  }
}

let availableCache: { at: number; value: boolean } | null = null;
export async function orcaAvailable(): Promise<boolean> {
  const now = Date.now();
  if (availableCache && now - availableCache.at < 15_000) return availableCache.value;
  const status = await orcaJson(["status"]);
  const value = Boolean(status?.runtime?.reachable);
  availableCache = { at: now, value };
  return value;
}

/** "✳ Claude Code" / a worktree path → something readable on a 42mm screen. */
function displayTitle(t: any): string {
  const path = String(t?.worktreePath ?? "").trim();
  if (path) {
    const base = path.split("/").filter(Boolean).pop();
    if (base) return base;
  }
  const title = String(t?.title ?? "").trim();
  // Strip Orca's status glyph and any leading path ellipsis.
  const clean = title.replace(/^[^\p{L}\p{N}/]+/u, "").trim();
  return clean || handleOf(String(t?.handle ?? "")).slice(0, 8) || "orca";
}

function agentTypeOf(t: any): string {
  const hay = `${t?.title ?? ""} ${t?.preview ?? ""}`.toLowerCase();
  if (hay.includes("claude")) return "claude";
  if (hay.includes("codex")) return "codex";
  if (hay.includes("gemini")) return "gemini";
  if (hay.includes("opencode")) return "opencode";
  return "shell";
}

let listCache: { at: number; value: any[] } | null = null;

/** Orca terminals shaped like meshd agents (see Shared/Models.swift `Agent`). */
export async function orcaSessions(): Promise<any[]> {
  const now = Date.now();
  if (listCache && now - listCache.at < LIST_TTL_MS) return listCache.value;

  const result = await orcaJson(["terminal", "list"]);
  const terminals: any[] = Array.isArray(result?.terminals) ? result.terminals : [];
  const agents = terminals
    .filter((t) => t?.handle && !t?.orphaned)
    .map((t) => ({
      name: `${PREFIX}${t.handle}`,
      title: displayTitle(t),
      windows: 1,
      createdISO: undefined as string | undefined,
      attached: Boolean(t.connected),
      agentType: agentTypeOf(t),
      // Orca does not expose per-terminal process stats; leaving these undefined
      // makes the UI show "—" rather than a wrong number.
      memMB: undefined as number | undefined,
      cpuPct: undefined as number | undefined,
      orcaWritable: Boolean(t.writable),
      orcaWorktree: String(t.worktreePath ?? ""),
      orcaBranch: String(t.branch ?? "").replace(/^refs\/heads\//, ""),
    }));

  listCache = { at: now, value: agents };
  return agents;
}

export async function orcaOutput(name: string, lines: number): Promise<{ name: string; lines: string[] } | null> {
  const result = await orcaJson(["terminal", "read", "--terminal", handleOf(name), "--limit", String(lines)]);
  const tail = result?.terminal?.tail;
  if (!Array.isArray(tail)) return null;
  return { name, lines: tail.map((l: any) => String(l)) };
}

/**
 * Send text or a control key to an Orca terminal.
 * `key` mirrors meshd's rmux keys; only the ones Orca exposes are supported.
 */
export async function orcaSend(name: string, text?: string, key?: string): Promise<{ ok: boolean; error?: string }> {
  const handle = handleOf(name);
  const args = ["terminal", "send", "--terminal", handle];

  if (key) {
    const k = key.toLowerCase();
    if (k === "c-c" || k === "ctrl-c" || k === "interrupt") {
      args.push("--interrupt");
    } else if (k === "enter" || k === "cr") {
      args.push("--text", "", "--enter");
    } else {
      return { ok: false, error: `orca does not support key "${key}"` };
    }
  } else {
    // meshd's rmux path treats a trailing newline as "press enter"; Orca has a flag.
    const raw = text ?? "";
    const enter = raw.endsWith("\n");
    args.push("--text", enter ? raw.replace(/\n+$/, "") : raw);
    if (enter) args.push("--enter");
  }

  const result = await orcaJson(args);
  if (result === null) return { ok: false, error: "orca send failed (is Orca running?)" };
  listCache = null; // output is about to change; don't serve a stale list
  return { ok: true };
}

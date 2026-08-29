// herdr — the third multiplexer, alongside rmux and cmux. herdr keeps its state in a
// server process and answers over a unix socket, so the `herdr` CLI works from outside
// a herdr pane: meshd is a LaunchAgent with no herdr environment of its own and still
// gets a full pane list. That is the whole reason this lane can exist without a bridge.
//
// Session names are `herdr:<pane_id>` (`herdr:w9:p2`). Colons, not slashes, so the
// existing /agents/<name>/... route patterns match without change.
//
// Every call here reports the CLI's own exit code and error message rather than
// swallowing them. The defect this lane was written for was a terminal that showed an
// empty screen and accepted keystrokes into nothing — a wrong answer that looks like a
// working one. A surfaced "pane_not_found" is worth more than a blank pane.

const HERDR_BIN = process.env.HERDR_BIN ?? "herdr";

export const HERDR_PREFIX = "herdr:";
export function isHerdrAgent(name: string): boolean { return name.startsWith(HERDR_PREFIX); }
export function herdrPaneRef(name: string): string { return name.slice(HERDR_PREFIX.length); }

export type HerdrRun = (args: string[]) => Promise<{ out: string; err: string; code: number }>;

const defaultRun: HerdrRun = async (args) => {
  // argv straight to spawn, no shell: pane refs come off the URL, and a lane with no
  // /bin/sh -c in it has no quoting to get wrong. Bun resolves a bare binary via PATH.
  const p = Bun.spawn([HERDR_BIN, ...args], { stdout: "pipe", stderr: "pipe" });
  // /stats and /agents call this on their hot paths; a herdr server that stops
  // answering its socket must not wedge them. 5s is generous for a local socket RPC.
  const timer = setTimeout(() => { try { p.kill(); } catch { } }, 5000);
  try {
    const [out, err] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text()]);
    return { out, err: err.trim(), code: await p.exited };
  } finally {
    clearTimeout(timer);
  }
};

/// The CLI answers `{id, result}` on success and `{id, error:{code,message}}` on failure,
/// and it puts BOTH on stdout — an exit code alone does not tell you which, and a parse
/// failure is its own third case (binary absent, server down, output not JSON at all).
export function parseEnvelope(raw: string): { result?: any; error?: string } {
  const text = raw.trim();
  if (!text) return { error: "herdr returned nothing" };
  let body: any;
  try { body = JSON.parse(text); } catch { return { error: text.split("\n")[0].slice(0, 200) }; }
  if (body?.error) {
    const e = body.error;
    return { error: String(e?.message ?? e?.code ?? "herdr error") };
  }
  return { result: body?.result };
}

/// True only for the CLI's own failure envelope: one JSON object spanning the whole
/// output, with the `id` the CLI stamps on every response plus a truthy `error`.
/// Screen text that merely starts with "{" — or is valid JSON without the id — is a
/// pane's content, not a verdict about the pane.
export function isHerdrErrorEnvelope(raw: string): boolean {
  const text = raw.trim();
  if (!text.startsWith("{")) return false;
  try {
    const body = JSON.parse(text);
    return typeof body?.id === "string" && Boolean(body?.error);
  } catch {
    return false;
  }
}

/// The CLI does not agree with itself about where a failure goes: `pane read` prints
/// its error envelope on stdout, `pane send-keys` prints the same envelope on stderr
/// and leaves stdout empty. Measured against herdr on 2026-08-28. Reading only one
/// stream reported "herdr returned nothing" over a perfectly good "pane not found".
export function runError(r: { out: string; err: string }): string {
  for (const stream of [r.out, r.err]) {
    if (!stream.trim()) continue;
    const why = parseEnvelope(stream).error;
    if (why) return why;
  }
  return "herdr rejected the input";
}

export type HerdrPaneRow = {
  paneId: string;
  workspaceId: string;
  tabId?: string;
  label?: string;
  cwd?: string;
  focused: boolean;
  agentStatus?: string;
};

export type HerdrWorkspaceRow = { workspaceId: string; label?: string; repoName?: string };

export function parsePaneList(raw: string): HerdrPaneRow[] {
  const { result } = parseEnvelope(raw);
  const panes = Array.isArray(result?.panes) ? result.panes : [];
  return panes.flatMap((p: any) => {
    const paneId = typeof p?.pane_id === "string" ? p.pane_id : "";
    if (!paneId) return [];
    return [{
      paneId,
      workspaceId: String(p?.workspace_id ?? ""),
      tabId: p?.tab_id ? String(p.tab_id) : undefined,
      label: p?.label ? String(p.label) : undefined,
      cwd: p?.foreground_cwd ? String(p.foreground_cwd) : (p?.cwd ? String(p.cwd) : undefined),
      focused: p?.focused === true,
      agentStatus: p?.agent_status ? String(p.agent_status) : undefined,
    }];
  });
}

export function parseWorkspaceList(raw: string): Map<string, HerdrWorkspaceRow> {
  const { result } = parseEnvelope(raw);
  const rows = Array.isArray(result?.workspaces) ? result.workspaces : [];
  const map = new Map<string, HerdrWorkspaceRow>();
  for (const w of rows) {
    const id = typeof w?.workspace_id === "string" ? w.workspace_id : "";
    if (!id) continue;
    map.set(id, {
      workspaceId: id,
      label: w?.label ? String(w.label) : undefined,
      repoName: w?.worktree?.repo_name ? String(w.worktree.repo_name) : undefined,
    });
  }
  return map;
}

/// The label a phone row shows. herdr nests pane inside tab inside workspace, and a
/// pane id (`w9:p2`) means nothing on a wrist, so the workspace label carries the
/// context and the pane label distinguishes siblings. Both are optional in the API:
/// a workspace keeps its cwd-derived name unless renamed, and most panes have no
/// label at all, so the pane id is the last resort rather than the first choice.
export function herdrTitle(pane: HerdrPaneRow, workspaces: Map<string, HerdrWorkspaceRow>): string {
  const ws = workspaces.get(pane.workspaceId);
  const wsName = ws?.label || ws?.repoName;
  if (wsName && pane.label && pane.label !== wsName) return `${wsName} · ${pane.label}`;
  return wsName || pane.label || pane.paneId;
}

/// herdr's own agent detection, mapped onto the string the phone already renders.
/// `unknown` is what a plain shell reports, and claiming an agent type we did not
/// detect is exactly the kind of confident-wrong label this lane exists to avoid.
export function herdrAgentType(cmdline: string | undefined, agentStatus: string | undefined): string | undefined {
  const c = (cmdline ?? "").toLowerCase();
  if (c.includes("claude")) return "Claude";
  if (c.includes("codex")) return "Codex";
  if (c.includes("node") || c.includes("bun")) return "Node";
  if (c.includes("python")) return "Python";
  if (c) return "shell";
  return agentStatus && agentStatus !== "unknown" ? "shell" : undefined;
}

/// herdr's own per-pane agent verdict, folded onto the four words the phone renders.
/// Only statuses herdr affirmatively reports survive; "unknown" (a plain shell) maps
/// to undefined so the caller falls back to the event-index heuristic — without this,
/// a Claude grinding away in an unfocused herdr pane badges "idle" on the phone,
/// because no hook posts events under `herdr:w9:p2`-shaped names.
export function herdrStatus(agentStatus: string | undefined): "working" | "waiting" | "error" | "idle" | undefined {
  switch ((agentStatus ?? "").toLowerCase()) {
    case "working": case "running": case "busy": return "working";
    case "waiting": case "needs_attention": case "needs-attention": case "blocked": return "waiting";
    case "error": case "failed": return "error";
    case "idle": case "done": return "idle";
    default: return undefined;
  }
}

export type HerdrProcess = { shellPid?: number; pids: number[]; cmdline?: string };

export function parseProcessInfo(raw: string): HerdrProcess {
  const { result } = parseEnvelope(raw);
  const info = result?.process_info;
  const fg = Array.isArray(info?.foreground_processes) ? info.foreground_processes : [];
  const pids: number[] = [];
  const shellPid = Number(info?.shell_pid);
  if (Number.isFinite(shellPid) && shellPid > 0) pids.push(shellPid);
  for (const p of fg) {
    const pid = Number(p?.pid);
    if (Number.isFinite(pid) && pid > 0 && !pids.includes(pid)) pids.push(pid);
  }
  // The foreground process is what the pane is actually running; the login shell that
  // owns the pane says nothing about whether an agent is in there.
  const lead = fg.find((p: any) => Number(p?.pid) !== shellPid) ?? fg[0];
  const cmdline = lead?.cmdline ? String(lead.cmdline) : (lead?.name ? String(lead.name) : undefined);
  return { shellPid: Number.isFinite(shellPid) && shellPid > 0 ? shellPid : undefined, pids, cmdline };
}

/// Enumerate every herdr pane on this machine. Returns [] — never throws — when herdr
/// is not installed or its server is not running, because /agents must keep answering
/// with the rmux and cmux rows on a machine that has never heard of herdr.
export async function herdrSessions(
  usage: (pids: number[]) => { memMB: number; cpuPct: number },
  run: HerdrRun = defaultRun,
): Promise<any[]> {
  const [paneRaw, wsRaw] = await Promise.all([
    run(["pane", "list"]).catch(() => ({ out: "", err: "", code: 1 })),
    run(["workspace", "list"]).catch(() => ({ out: "", err: "", code: 1 })),
  ]);
  if (paneRaw.code !== 0) return [];
  const panes = parsePaneList(paneRaw.out);
  if (!panes.length) return [];
  const workspaces = wsRaw.code === 0 ? parseWorkspaceList(wsRaw.out) : new Map<string, HerdrWorkspaceRow>();

  const procs = await Promise.all(panes.map((p) =>
    run(["pane", "process-info", "--pane", p.paneId])
      .then((r): HerdrProcess => (r.code === 0 ? parseProcessInfo(r.out) : { pids: [] }))
      .catch((): HerdrProcess => ({ pids: [] }))
  ));

  return panes.map((pane, i) => {
    const proc = procs[i];
    const { memMB, cpuPct } = usage(proc.pids);
    return {
      name: `${HERDR_PREFIX}${pane.paneId}`,
      title: herdrTitle(pane, workspaces),
      windows: 1,
      createdISO: null,
      attached: pane.focused,
      agentType: herdrAgentType(proc.cmdline, pane.agentStatus),
      // herdr watches its own panes; its verdict beats the event-index heuristic,
      // which no hook feeds under herdr:* names. See herdrStatus() for the mapping.
      herdrStatus: herdrStatus(pane.agentStatus),
      memMB: memMB ? Math.round(memMB) : undefined,
      cpuPct: cpuPct ? Math.round(cpuPct * 10) / 10 : undefined,
      cwd: pane.cwd,
    };
  });
}

/// /stats wants the number only. Going through herdrSessions for it would spend one
/// process-info call per pane on a figure that is polled far more often than it is read.
export async function herdrPaneCount(run: HerdrRun = defaultRun): Promise<number> {
  const r = await run(["pane", "list"]).catch(() => ({ out: "", err: "", code: 1 }));
  return r.code === 0 ? parsePaneList(r.out).length : 0;
}

/// `null` means the pane could not be resolved, which the /agents/<s>/output route
/// turns into a 404. An empty `lines` array means the pane resolved and its screen is
/// genuinely blank. Collapsing those two into "200 with no lines" is what made a dead
/// session indistinguishable from a quiet one.
export async function herdrOutput(
  name: string, lines: number, join: boolean, run: HerdrRun = defaultRun,
): Promise<{ name: string; lines: string[] } | null> {
  const ref = herdrPaneRef(name);
  // recent-unwrapped joins the soft wraps back together, which is the same thing the
  // rmux lane asks capture-pane -J for: 80 columns wrapped onto a watch is unreadable.
  const source = join ? "recent-unwrapped" : "recent";
  const r = await run(["pane", "read", ref, "--source", source, "--lines", String(Math.max(1, lines))])
    .catch(() => ({ out: "", err: "herdr unavailable", code: 1 }));
  if (r.code !== 0) return null;
  // pane read prints terminal text, not JSON — but it prints the error envelope on
  // stdout when the pane is gone, and that envelope must not be rendered as output.
  // The discriminator has to be strict: a live pane whose screen happens to show JSON
  // (a curl'd API error, the top of a package.json) also starts with "{", and reporting
  // that pane dead is exactly the confident-wrong answer this lane exists to kill. The
  // CLI's envelope is one whole JSON object carrying both `id` and `error`; anything
  // that fails strict parsing, or parses without that shape, is screen content.
  if (isHerdrErrorEnvelope(r.out)) return null;
  const arr = r.out.replace(/\n+$/, "").split("\n");
  return { name, lines: arr.slice(-lines) };
}

/// The keys herdr's own binding syntax confirms (`ctrl+alt+d`, `cmd+w` in config.toml)
/// plus `esc`, which its CLI help names as canonical. Anything outside this set is
/// refused by name rather than sent and hoped for — an unsupported key that reports
/// itself beats one that silently does nothing.
export const HERDR_KEYS: Record<string, string> = {
  enter: "enter",
  "ctrl-c": "ctrl+c",
  "ctrl-d": "ctrl+d",
  up: "up",
  down: "down",
  left: "left",
  right: "right",
  tab: "tab",
  escape: "esc",
};

export async function herdrSend(
  name: string, text?: string, key?: string, paste = false, run: HerdrRun = defaultRun,
): Promise<{ ok: boolean; error?: string }> {
  const ref = herdrPaneRef(name);
  const hasText = typeof text === "string" && text.length > 0;
  const hasKey = typeof key === "string" && key.length > 0;
  if (!hasText && !hasKey) return { ok: false, error: "text or key required" };

  const mapped = hasKey ? HERDR_KEYS[key] : undefined;
  if (hasKey && !mapped) return { ok: false, error: `unsupported key: ${key}` };

  const fail = (r: { out: string; err: string }) => ({ ok: false, error: runError(r) });

  if (hasText) {
    // send-text is literal and never appends a newline, so a payload ending in "\n"
    // must become a real Enter press — otherwise the phone's send button composes the
    // line and leaves it sitting unsubmitted at the prompt.
    const submit = !paste && text.endsWith("\n");
    let body = submit ? text.slice(0, -1) : text;
    // A literal write is NOT paste-safe: embedded newline bytes hit the pty as Enter
    // presses, and a pasted paragraph becomes eight half-submitted prompts — the exact
    // regression the rmux lane's paste-buffer path exists to prevent. Bracketed-paste
    // markers make a TUI that has paste mode on (Claude Code, codex, every modern
    // readline) treat the span as one atomic paste.
    if (paste && body.includes("\n")) body = `\x1b[200~${body}\x1b[201~`;
    if (body.length) {
      const r = await run(["pane", "send-text", ref, body]).catch(() => ({ out: "", err: "herdr unavailable", code: 1 }));
      if (r.code !== 0) return fail(r);
    }
    if (submit) {
      const r = await run(["pane", "send-keys", ref, "enter"]).catch(() => ({ out: "", err: "herdr unavailable", code: 1 }));
      if (r.code !== 0) return fail(r);
    }
  }
  if (hasKey) {
    const r = await run(["pane", "send-keys", ref, mapped!]).catch(() => ({ out: "", err: "herdr unavailable", code: 1 }));
    if (r.code !== 0) return fail(r);
  }
  return { ok: true };
}

/// One pane per session by construction — a herdr session name addresses a single pane,
/// not a tab — so the /panes route reports exactly that rather than inventing a tree.
export async function herdrPanes(name: string, run: HerdrRun = defaultRun) {
  const ref = herdrPaneRef(name);
  const r = await run(["pane", "get", ref]).catch(() => ({ out: "", err: "", code: 1 }));
  if (r.code !== 0) return null;
  const { result, error } = parseEnvelope(r.out);
  if (error || !result?.pane) return null;
  const p = result.pane;
  return {
    name,
    panes: [{
      paneId: ref,
      windowIndex: 0,
      paneIndex: 0,
      command: "herdr",
      active: p?.focused === true,
      windowName: p?.label ? String(p.label) : ref,
      currentPath: p?.foreground_cwd ? String(p.foreground_cwd) : (p?.cwd ? String(p.cwd) : undefined),
    }],
  };
}

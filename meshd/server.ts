// meshd — one per machine. System stats + agent (rmux) control + OpenUsage, over Tailscale.
// bun + TypeScript. Auth: Bearer <MESHD_TOKEN>. Bind <MESHD_HOST>:<MESHD_PORT>.
import os from "node:os";
import { homedir } from "node:os";
import { join } from "node:path";
import { appendFile, mkdir, readFile, unlink } from "node:fs/promises";
import { kbPut, kbGet, kbSearch } from "./kb";

const PORT = Number(process.env.MESHD_PORT ?? "8899");
const HOST = process.env.MESHD_HOST ?? "0.0.0.0";
const TOKEN = process.env.MESHD_TOKEN ?? "";
const VERSION = "0.2.0";
const CAPABILITIES = ["events", "newPane", "paneTarget", "usage", "agents", "cmux", "tailscale", "kb", "screenPeek"];
const IS_MAC = process.platform === "darwin";
// Multiplexer: rmux on macOS, tmux on Linux (tmux-compatible). Override with MESH_MUX.
const MUX = process.env.MESH_MUX ?? (IS_MAC ? "rmux" : "tmux");
const EVENTS_PATH = process.env.MESHD_EVENTS_PATH ?? join(homedir(), ".mesh", "agent-events.jsonl");

async function sh(cmd: string): Promise<string> {
  const p = Bun.spawn(["/bin/sh", "-c", cmd], { stdout: "pipe", stderr: "ignore" });
  const out = await new Response(p.stdout).text();
  await p.exited;
  return out;
}

function num(x: string | undefined, d = 0): number {
  const n = Number((x ?? "").trim());
  return Number.isFinite(n) ? n : d;
}

// ---------- stats ----------
async function macCpuPct(): Promise<number> {
  const out = await sh(`top -l 2 -n 0 | grep "CPU usage" | tail -1`);
  const m = out.match(/(\d+\.?\d*)%\s*idle/);
  return m ? Math.max(0, Math.min(100, 100 - parseFloat(m[1]))) : 0;
}
async function macMem(): Promise<{ usedMB: number; totalMB: number; pct: number }> {
  const totalB = os.totalmem();
  const vm = await sh(`vm_stat`);
  const pageSize = num(vm.match(/page size of (\d+)/)?.[1], 16384);
  const pages = (label: string) => num(vm.match(new RegExp(`${label}:\\s+(\\d+)`))?.[1]);
  const usedB = (pages("Pages active") + pages("Pages wired down") + pages("Pages occupied by compressor")) * pageSize;
  const totalMB = totalB / 1048576, usedMB = usedB / 1048576;
  return { usedMB, totalMB, pct: (usedMB / totalMB) * 100 };
}
async function linuxCpuPct(): Promise<number> {
  const read = async () => {
    const l = (await sh(`head -1 /proc/stat`)).trim().split(/\s+/).slice(1).map(Number);
    const idle = l[3] + (l[4] ?? 0), total = l.reduce((a, b) => a + b, 0);
    return { idle, total };
  };
  const a = await read();
  await Bun.sleep(200);
  const b = await read();
  const dt = b.total - a.total, di = b.idle - a.idle;
  return dt > 0 ? Math.max(0, Math.min(100, (100 * (dt - di)) / dt)) : 0;
}
async function linuxMem(): Promise<{ usedMB: number; totalMB: number; pct: number }> {
  const mi = await sh(`cat /proc/meminfo`);
  const kb = (k: string) => num(mi.match(new RegExp(`${k}:\\s+(\\d+)`))?.[1]);
  const totalMB = kb("MemTotal") / 1024;
  const availMB = kb("MemAvailable") / 1024;
  const usedMB = totalMB - availMB;
  return { usedMB, totalMB, pct: (usedMB / totalMB) * 100 };
}
async function disk(): Promise<{ path: string; usedGB: number; totalGB: number; pct: number }> {
  const out = await sh(`df -k / | tail -1`);
  const f = out.trim().split(/\s+/);
  // macOS df: Filesystem 1024-blocks Used Avail Capacity ... ; linux: Filesystem 1K-blocks Used Available Use% Mounted
  const totalKB = num(f[1]), usedKB = num(f[2]);
  return { path: "/", usedGB: usedKB / 1048576, totalGB: totalKB / 1048576, pct: totalKB ? (usedKB / totalKB) * 100 : 0 };
}
async function topProcs(): Promise<any[]> {
  const cmd = IS_MAC
    ? `ps -Ao pid,pcpu,rss,comm -r | head -n 9`
    : `ps -eo pid,pcpu,rss,comm --sort=-pcpu | head -n 9`;
  const out = await sh(cmd);
  return out.trim().split("\n").slice(1).map((line) => {
    const f = line.trim().split(/\s+/);
    const pid = num(f[0]), cpuPct = num(f[1]), rssKB = num(f[2]);
    const cmdName = f.slice(3).join(" ").split("/").pop() ?? f.slice(3).join(" ");
    return { pid, cmd: cmdName, cpuPct, memMB: rssKB / 1024, memPct: (rssKB / 1024 / (os.totalmem() / 1048576)) * 100 };
  }).filter((p) => p.pid > 0);
}
async function getStats() {
  const [cpuPct, mem, dsk, procs, agentsCount] = await Promise.all([
    IS_MAC ? macCpuPct() : linuxCpuPct(),
    IS_MAC ? macMem() : linuxMem(),
    disk(),
    topProcs(),
    agentSessions().then((s) => s.length).catch(() => 0),
  ]);
  return { host: os.hostname(), platform: process.platform, cpuPct, load: os.loadavg(), mem, disk: dsk, topProcs: procs, agentsCount };
}

// ---------- agents (rmux) ----------
// One snapshot of every process: pid -> { ppid, rssKB, pcpu }. Works on mac + linux.
async function procTable(): Promise<Map<number, { ppid: number; rssKB: number; pcpu: number }>> {
  const out = await sh(`ps -A -o pid=,ppid=,rss=,pcpu= 2>/dev/null`);
  const t = new Map<number, { ppid: number; rssKB: number; pcpu: number }>();
  for (const line of out.split("\n")) {
    const f = line.trim().split(/\s+/);
    if (f.length < 4) continue;
    const pid = num(f[0]);
    if (pid > 0) t.set(pid, { ppid: num(f[1]), rssKB: num(f[2]), pcpu: num(f[3]) });
  }
  return t;
}
// Sum RSS + %CPU of each root pid AND all its descendants (the agent runs as a
// child of the pane's shell, so we must walk the tree, not just the pane pid).
function sumSubtrees(roots: number[], table: Map<number, { ppid: number; rssKB: number; pcpu: number }>) {
  const children = new Map<number, number[]>();
  for (const [pid, p] of table) {
    const arr = children.get(p.ppid) ?? [];
    arr.push(pid);
    children.set(p.ppid, arr);
  }
  let rssKB = 0, pcpu = 0;
  const seen = new Set<number>();
  const stack = [...roots];
  while (stack.length) {
    const pid = stack.pop()!;
    if (seen.has(pid)) continue;
    seen.add(pid);
    const p = table.get(pid);
    if (p) { rssKB += p.rssKB; pcpu += p.pcpu; }
    for (const c of children.get(pid) ?? []) stack.push(c);
  }
  return { memMB: rssKB / 1024, cpuPct: pcpu };
}

async function rmuxSessions(): Promise<any[]> {
  const out = await sh(`${MUX} list-sessions -F '#{session_name}|#{session_windows}|#{session_created}|#{session_attached}' 2>/dev/null`);
  if (!out.trim()) return [];
  const rows = out.trim().split("\n").map((l) => l.split("|"));
  const sessions = [] as any[];
  const HIDDEN = new Set(["meshd", "rmux-bridge"]); // infra, not user agents
  const table = await procTable();
  for (const r of rows) {
    const name = r[0];
    if (HIDDEN.has(name)) continue;
    // One pass over this session's panes: agent type (first pane) + all pane pids.
    const panesOut = await sh(`${MUX} list-panes -s -t ${shq(name)} -F '#{pane_pid}|#{pane_current_command}' 2>/dev/null`);
    const paneRows = panesOut.trim().split("\n").filter(Boolean).map((l) => l.split("|"));
    const panePids = paneRows.map((p) => num(p[0])).filter((n) => n > 0);
    const agentType = paneRows[0]?.[1] ? mapAgent(paneRows[0][1]) : undefined;
    const { memMB, cpuPct } = sumSubtrees(panePids, table);
    sessions.push({
      name,
      title: null,
      windows: num(r[1]),
      createdISO: r[2] ? new Date(num(r[2]) * 1000).toISOString() : null,
      attached: r[3] === "1",
      agentType,
      memMB: Math.round(memMB),
      cpuPct: Math.round(cpuPct * 10) / 10,
    });
  }
  return sessions;
}
function mapAgent(cmd: string): string {
  const c = cmd.toLowerCase();
  if (c.includes("claude")) return "Claude";
  if (c.includes("codex")) return "Codex";
  if (c.includes("node") || c.includes("bun")) return "Node";
  if (c.includes("python")) return "Python";
  return "shell";
}
function shq(s: string) { return `'${s.replace(/'/g, `'\\''`)}'`; }
function sanitize(s: string) { return s.replace(/[^a-zA-Z0-9._-]+/g, "-"); }

type CmuxTopRow = { cpuPct: number; memMB: number; parent: string; label: string };

function isCmuxAgent(name: string) { return name.startsWith("cmux:"); }
function cmuxSurfaceRef(value?: string) {
  if (!value) return null;
  if (value.startsWith("cmux:")) return value.slice("cmux:".length);
  if (value.startsWith("surface:")) return value;
  return null;
}

async function cmuxTop() {
  const out = await sh(`CMUX_QUIET=1 cmux top --all --flat --format tsv 2>/dev/null`);
  const rows = new Map<string, CmuxTopRow>();
  const agentByWorkspace = new Map<string, string>();
  for (const line of out.split("\n")) {
    const f = line.split("\t");
    if (f.length < 6) continue;
    const [cpu, memBytes, , kind, id, parent, label = ""] = f;
    rows.set(id, { cpuPct: num(cpu), memMB: num(memBytes) / 1048576, parent, label });
    if (kind === "tag") {
      if (id.includes(":tag:claude")) agentByWorkspace.set(parent, "Claude");
      else if (id.includes(":tag:codex")) agentByWorkspace.set(parent, "Codex");
      else if (id.includes(":tag:opencode")) agentByWorkspace.set(parent, "OpenCode");
    }
  }
  return { rows, agentByWorkspace };
}

async function cmuxSessions(): Promise<any[]> {
  const [tree, top] = await Promise.all([
    sh(`CMUX_QUIET=1 cmux tree --all --id-format both 2>/dev/null`),
    cmuxTop(),
  ]);
  const sessions = [] as any[];
  let workspaceRef = "";
  let workspaceTitle = "";
  let paneRef = "";

  for (const line of tree.split("\n")) {
    const workspace = line.match(/workspace (workspace:\d+) [A-F0-9-]+ "([^"]*)"/);
    if (workspace) {
      workspaceRef = workspace[1];
      workspaceTitle = workspace[2] ?? "";
      continue;
    }
    const pane = line.match(/pane (pane:\d+) /);
    if (pane) {
      paneRef = pane[1];
      continue;
    }
    const surface = line.match(/surface (surface:\d+) [A-F0-9-]+ \[(\w+)\] "([^"]*)"/);
    if (!surface || surface[2] !== "terminal") continue;

    const surfaceRef = surface[1];
    const title = surface[3] || workspaceTitle || surfaceRef;
    const metric = top.rows.get(surfaceRef);
    sessions.push({
      name: `cmux:${surfaceRef}`,
      title,
      windows: 1,
      createdISO: null,
      attached: line.includes("◀ active") || line.includes("◀ here"),
      agentType: top.agentByWorkspace.get(workspaceRef) ?? mapAgent(title),
      memMB: metric ? Math.round(metric.memMB) : undefined,
      cpuPct: metric ? Math.round(metric.cpuPct * 10) / 10 : undefined,
      panes: [{
        paneId: surfaceRef,
        windowIndex: num(workspaceRef.split(":")[1]),
        paneIndex: num(paneRef.split(":")[1]),
        command: "cmux",
        active: line.includes("◀ active") || line.includes("◀ here"),
        windowName: workspaceTitle,
        currentPath: workspaceTitle || undefined,
      }],
    });
  }
  return sessions;
}

async function agentSessions(): Promise<any[]> {
  const [rmux, cmux] = await Promise.all([
    rmuxSessions().catch(() => []),
    cmuxSessions().catch(() => []),
  ]);
  return [...rmux, ...cmux];
}

async function agentPanes(name: string) {
  if (isCmuxAgent(name)) return cmuxPanes(name);
  const has = await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`);
  if (!has.trim().endsWith("0")) return null;
  const out = await sh(`${MUX} list-panes -s -t ${shq(name)} -F '#{window_index}.#{pane_index}|#{pane_id}|#{pane_current_command}|#{pane_active}|#{window_name}|#{pane_current_path}' 2>/dev/null`);
  const panes = out.trim().split("\n").filter(Boolean).map((line) => {
    const f = line.split("|");
    const [windowIndex, paneIndex] = (f[0] ?? "").split(".");
    return {
      paneId: f[1],
      windowIndex: num(windowIndex),
      paneIndex: num(paneIndex),
      command: f[2] ?? "",
      active: f[3] === "1",
      windowName: f[4] ?? "",
      currentPath: f[5] || undefined,
    };
  });
  return { name, panes };
}
async function agentOutput(name: string, lines: number, pane?: string) {
  if (isCmuxAgent(name)) return cmuxOutput(name, lines, pane);
  const has = await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`);
  if (!has.trim().endsWith("0")) return null;
  const target = pane ? shq(pane) : shq(name);
  const out = await sh(`${MUX} capture-pane -p -t ${target} 2>/dev/null`);
  const arr = out.replace(/\n+$/, "").split("\n");
  return { name, lines: arr.slice(-lines) };
}
async function cmuxPanes(name: string) {
  const surface = cmuxSurfaceRef(name);
  if (!surface) return null;
  return {
    name,
    panes: [{
      paneId: surface,
      windowIndex: 0,
      paneIndex: 0,
      command: "cmux",
      active: true,
      windowName: "cmux",
      currentPath: undefined,
    }],
  };
}
async function cmuxOutput(name: string, lines: number, pane?: string) {
  const surface = cmuxSurfaceRef(pane) ?? cmuxSurfaceRef(name);
  if (!surface) return null;
  const out = await sh(`CMUX_QUIET=1 cmux read-screen --surface ${shq(surface)} --scrollback --lines ${Math.max(1, Math.min(lines, 200))} 2>/dev/null`);
  return { name, lines: out.replace(/\n+$/, "").split("\n") };
}
const INFRA = new Set(["meshd", "rmux-bridge"]); // never killable over the wire
async function agentKill(name: string): Promise<{ ok: boolean; error?: string }> {
  if (INFRA.has(name)) return { ok: false, error: "infra session is protected" };
  if (isCmuxAgent(name)) return { ok: false, error: "cmux sessions are controlled from cmux/herdr" };
  if (!(await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) {
    return { ok: false, error: "no such session" };
  }
  await sh(`${MUX} kill-session -t ${shq(name)}`);
  return { ok: true };
}
async function agentKillPane(name: string, paneId: string): Promise<{ ok: boolean; error?: string }> {
  if (INFRA.has(name)) return { ok: false, error: "infra session is protected" };
  if (isCmuxAgent(name)) return { ok: false, error: "cmux panes are controlled from cmux/herdr" };
  await sh(`${MUX} kill-pane -t ${shq(paneId)}`);
  return { ok: true };
}
async function agentNewPane(name: string, dir?: string): Promise<{ ok: boolean; error?: string }> {
  if (isCmuxAgent(name)) return { ok: false, error: "cmux pane creation is not supported from MeshWatch yet" };
  if (!(await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) {
    return { ok: false, error: "no such session" };
  }
  const flag = dir === "h" ? "-h" : dir === "v" ? "-v" : "";
  await sh(`${MUX} split-window ${flag} -t ${shq(name)}`);
  return { ok: true };
}
const KEY_SEND_KEYS: Record<string, string> = {
  enter: "Enter",
  "ctrl-c": "C-c",
  "ctrl-d": "C-d",
  up: "Up",
  down: "Down",
  left: "Left",
  right: "Right",
  tab: "Tab",
  escape: "Escape",
  backspace: "BSpace",
  delete: "DC",
  home: "Home",
  end: "End",
  "page-up": "PPage",
  "page-down": "NPage",
};
const CMUX_SEND_KEYS: Record<string, string> = {
  enter: "enter",
  "ctrl-c": "ctrl+c",
  "ctrl-d": "ctrl+d",
  up: "up",
  down: "down",
  left: "left",
  right: "right",
  tab: "tab",
  escape: "escape",
  backspace: "backspace",
  delete: "delete",
  home: "home",
  end: "end",
  "page-up": "page-up",
  "page-down": "page-down",
};

async function agentSend(name: string, text?: string, key?: string, pane?: string): Promise<{ ok: boolean; error?: string }> {
  if (isCmuxAgent(name)) return cmuxSend(name, text, key, pane);
  const hasText = typeof text === "string" && text.length > 0;
  const hasKey = typeof key === "string" && key.length > 0;
  if (!hasText && !hasKey) return { ok: false, error: "text or key required" };

  const sendKey = hasKey ? KEY_SEND_KEYS[key] : undefined;
  if (hasKey && !sendKey) return { ok: false, error: `unsupported key: ${key}` };

  const target = pane ? shq(pane) : shq(name);
  if (hasText) {
    const hex = Array.from(new TextEncoder().encode(text), (b) => b.toString(16).padStart(2, "0")).join(" ");
    await sh(`${MUX} send-keys -t ${target} -H -- ${hex}`);
  }
  if (sendKey) await sh(`${MUX} send-keys -t ${target} ${sendKey}`);
  return { ok: true };
}
async function cmuxSend(name: string, text?: string, key?: string, pane?: string): Promise<{ ok: boolean; error?: string }> {
  const surface = cmuxSurfaceRef(pane) ?? cmuxSurfaceRef(name);
  if (!surface) return { ok: false, error: "bad cmux target" };
  const hasText = typeof text === "string" && text.length > 0;
  const hasKey = typeof key === "string" && key.length > 0;
  if (!hasText && !hasKey) return { ok: false, error: "text or key required" };
  if (hasText) await sh(`CMUX_QUIET=1 cmux send --surface ${shq(surface)} -- ${shq(text!)}`);
  if (hasKey) {
    const sendKey = CMUX_SEND_KEYS[key!];
    if (!sendKey) return { ok: false, error: `unsupported key: ${key}` };
    await sh(`CMUX_QUIET=1 cmux send-key --surface ${shq(surface)} -- ${shq(sendKey)}`);
  }
  return { ok: true };
}

// ---------- usage (OpenUsage) ----------
const OPENUSAGE_API = "http://127.0.0.1:6736/v1/usage";
const KNOWN_LABELS = new Set(["Today", "Yesterday", "Last 30 Days", "Account", "Credits", "Usage Trend", "Rate Limit Resets"]);

function pctFromProgress(line: any): number | null {
  const used = Number(line.used);
  const limit = Number(line.limit);
  if (!Number.isFinite(used) || !Number.isFinite(limit) || limit <= 0) return null;
  return line.format?.kind === "percent" && limit === 100 ? used : (used / limit) * 100;
}

function normalizeUsage(raw: any) {
  const snapshots = Array.isArray(raw) ? raw : Object.values(raw.snapshots ?? {});
  const providers = snapshots.map((s: any) => {
    const limits: any[] = [], topModels: any[] = [];
    let today, yesterday, last30;
    for (const line of s.lines ?? []) {
      if (line.type === "progress") {
        limits.push({ label: line.label, usedPct: pctFromProgress(line), resetsAtISO: line.resetsAt ?? null, periodDurationMs: line.periodDurationMs ?? null });
      } else if (line.type === "text") {
        if (line.label === "Today") today = line.value;
        else if (line.label === "Yesterday") yesterday = line.value;
        else if (line.label === "Last 30 Days") last30 = line.value;
        else if (!KNOWN_LABELS.has(line.label) && line.label.includes("-")) topModels.push({ label: line.label, pct: line.value });
      }
    }
    return {
      id: String(s.providerId ?? s.id ?? s.displayName ?? "unknown"),
      displayName: String(s.displayName ?? s.providerId ?? "Unknown"),
      plan: s.plan ?? null,
      limits,
      today,
      yesterday,
      last30,
      topModels,
    };
  });
  const fetchedAt = snapshots.map((s: any) => s.fetchedAt).filter(Boolean).sort().at(-1);
  return { fetchedAt, providers };
}

async function fetchOpenUsageApi() {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 1500);
  try {
    const res = await fetch(OPENUSAGE_API, { signal: ctrl.signal });
    return res.ok ? await res.json() : null;
  } finally {
    clearTimeout(timer);
  }
}

async function getUsage() {
  if (!IS_MAC) return { providers: [] };
  const live = await fetchOpenUsageApi().catch(() => null);
  if (live) return normalizeUsage(live);

  const path = join(homedir(), "Library/Application Support/com.sunstory.openusage/usage-api-cache.json");
  const file = Bun.file(path);
  if (!(await file.exists())) return { providers: [] };
  return normalizeUsage(await file.json());
}

async function screenImage(): Promise<Response> {
  if (!IS_MAC) return json({ error: "screen peek is macOS only" }, 404);
  const path = join(os.tmpdir(), `meshd-screen-${process.pid}-${Date.now()}.jpg`);
  try {
    const shot = Bun.spawn(["screencapture", "-x", "-t", "jpg", path], { stdout: "ignore", stderr: "ignore" });
    if (await shot.exited !== 0) return json({ error: "screenshot unavailable" }, 503);
    const scale = Bun.spawn(["sips", "-Z", "480", path], { stdout: "ignore", stderr: "ignore" });
    await scale.exited;
    return new Response(await readFile(path), { headers: { "content-type": "image/jpeg", "cache-control": "no-store" } });
  } finally {
    unlink(path).catch(() => {});
  }
}

// ---------- agent hook events ----------
type AgentEvent = {
  id: string;
  host?: string;
  source?: string;
  session?: string;
  level?: string;
  title: string;
  body?: string;
  createdISO: string;
};

async function readEvents(since?: string | null): Promise<AgentEvent[]> {
  const raw = await readFile(EVENTS_PATH, "utf8").catch(() => "");
  const events = raw.split("\n")
    .filter(Boolean)
    .map((line) => {
      try { return JSON.parse(line) as AgentEvent; } catch { return null; }
    })
    .filter((event): event is AgentEvent => Boolean(event));
  const filtered = since ? events.filter((event) => event.createdISO > since) : events;
  return filtered.slice(-100);
}

async function addEvent(input: any): Promise<AgentEvent> {
  const now = new Date().toISOString();
  const event: AgentEvent = {
    id: sanitize(input.id ?? `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`),
    host: os.hostname(),
    source: input.source ? String(input.source) : undefined,
    session: input.session ? String(input.session) : undefined,
    level: input.level ? String(input.level) : undefined,
    title: String(input.title ?? "Agent event").slice(0, 120),
    body: input.body ? String(input.body).slice(0, 500) : undefined,
    createdISO: input.createdISO ? String(input.createdISO) : now,
  };
  await mkdir(join(homedir(), ".mesh"), { recursive: true });
  await appendFile(EVENTS_PATH, `${JSON.stringify(event)}\n`);
  return event;
}

// ---------- tailnet discovery ----------
async function getTailnet() {
  const out = await sh(`tailscale status --json 2>&1`);
  if (!out.trim()) return { ok: false, peers: [], error: "tailscale unavailable" };
  let raw: any;
  try {
    raw = JSON.parse(out);
  } catch {
    return { ok: false, peers: [], error: out.trim().slice(0, 240) };
  }
  const self = raw.Self ? [raw.Self] : [];
  const peers = [...self, ...Object.values(raw.Peer ?? {})].map((p: any) => ({
    host: String(p.HostName ?? p.DNSName ?? "").replace(/\.$/, ""),
    dnsName: p.DNSName ? String(p.DNSName).replace(/\.$/, "") : undefined,
    ips: Array.isArray(p.TailscaleIPs) ? p.TailscaleIPs : [],
    online: Boolean(p.Online),
    os: p.OS ? String(p.OS) : undefined,
  })).filter((p) => p.host || p.ips.length);
  return { ok: true, peers };
}

// ---------- server ----------
function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}
function authed(req: Request): boolean {
  if (!TOKEN) return true;
  const h = req.headers.get("authorization") ?? "";
  const q = new URL(req.url).searchParams.get("token") ?? "";
  return h === `Bearer ${TOKEN}` || q === TOKEN;
}

function localIPs(): Set<string> {
  const set = new Set<string>();
  for (const list of Object.values(os.networkInterfaces())) {
    for (const i of list ?? []) if (i.address) set.add(i.address);
  }
  return set;
}

// Cross-machine KB search = read-federation: each machine owns its own kb.sqlite;
// we fan the same query out to online tailnet peers (federate=0 so they don't recurse),
// merge, and dedupe by (host,scope,key). No file sync, no corruption risk.
async function kbFederateSearch(local: any[], sp: URLSearchParams): Promise<any[]> {
  const tn = await getTailnet().catch(() => ({ ok: false, peers: [] as any[] }));
  const mine = localIPs();
  const qs = new URLSearchParams();
  for (const k of ["q", "scope", "kind", "limit"]) { const v = sp.get(k); if (v) qs.set(k, v); }
  qs.set("federate", "0");
  const peers = ((tn as any).peers ?? []).filter(
    (p: any) => p.online && p.ips?.length && !p.ips.some((ip: string) => mine.has(ip)),
  );
  const settled = await Promise.allSettled(peers.map((p: any) => {
    const ip = p.ips.find((x: string) => x.includes(".")) ?? p.ips[0];
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 2000);
    return fetch(`http://${ip}:${PORT}/kb/search?${qs.toString()}`, {
      headers: TOKEN ? { authorization: `Bearer ${TOKEN}` } : {},
      signal: ctrl.signal,
    }).then((r) => (r.ok ? r.json() : { results: [] })).finally(() => clearTimeout(t));
  }));
  const merged = [...local];
  for (const r of settled) if (r.status === "fulfilled") merged.push(...((r.value as any)?.results ?? []));
  const seen = new Set<string>();
  const out: any[] = [];
  for (const e of merged) {
    const k = `${e.host} ${e.scope} ${e.key}`;
    if (!seen.has(k)) { seen.add(k); out.push(e); }
  }
  return out;
}

Bun.serve({
  port: PORT,
  hostname: HOST,
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;
    if (path === "/health") {
      return json({ ok: true, host: os.hostname(), platform: process.platform, arch: process.arch, uptimeSec: Math.round(os.uptime()), meshdVersion: VERSION, capabilities: CAPABILITIES });
    }
    if (!authed(req)) return json({ error: "unauthorized" }, 401);
    try {
      if (path === "/stats") return json(await getStats());
      if (path === "/tailnet") return json(await getTailnet());
      if (path === "/agents") return json(await agentSessions());
      if (path === "/usage") return json(await getUsage());
      if (path === "/screen.jpg" && req.method === "GET") return await screenImage();
      if (path === "/events" && req.method === "GET") return json(await readEvents(url.searchParams.get("since")));
      if (path === "/events" && req.method === "POST") return json(await addEvent(await req.json().catch(() => ({}))), 201);
      if (path === "/kb" && (req.method === "PUT" || req.method === "POST")) {
        try { return json(kbPut(await req.json().catch(() => ({})), os.hostname()), 201); }
        catch (e: any) { return json({ error: String(e?.message ?? e) }, 400); }
      }
      if (path === "/kb/search" && req.method === "GET") {
        const sp = url.searchParams;
        const local = kbSearch({
          q: sp.get("q") ?? undefined, scope: sp.get("scope") ?? undefined,
          kind: sp.get("kind") ?? undefined, limit: Number(sp.get("limit") ?? "30"),
        }).map((r) => ({ ...r, host: r.host ?? os.hostname() }));
        if (sp.get("federate") === "0") return json({ results: local });
        return json({ results: await kbFederateSearch(local, sp) });
      }
      const kbGetM = path.match(/^\/kb\/([^/]+)\/([^/]+)$/);
      if (kbGetM && req.method === "GET") {
        const row = kbGet(decodeURIComponent(kbGetM[1]), decodeURIComponent(kbGetM[2]));
        return row ? json(row) : json({ error: "not found" }, 404);
      }
      const panesM = path.match(/^\/agents\/([^/]+)\/panes$/);
      if (panesM && req.method === "GET") {
        const res = await agentPanes(decodeURIComponent(panesM[1]));
        return res ? json(res) : json({ error: "no such session" }, 404);
      }
      if (panesM && req.method === "POST") {
        const body = await req.json().catch(() => ({}));
        const res = await agentNewPane(decodeURIComponent(panesM[1]), body.dir);
        return json(res, res.ok ? 201 : 404);
      }
      const outM = path.match(/^\/agents\/([^/]+)\/output$/);
      if (outM && req.method === "GET") {
        const res = await agentOutput(decodeURIComponent(outM[1]), Number(url.searchParams.get("lines") ?? "80"), url.searchParams.get("pane") ?? undefined);
        return res ? json(res) : json({ error: "no such session" }, 404);
      }
      const sendM = path.match(/^\/agents\/([^/]+)\/send$/);
      if (sendM && req.method === "POST") {
        const body = await req.json().catch(() => ({}));
        const res = await agentSend(decodeURIComponent(sendM[1]), body.text, body.key, body.pane);
        return json(res, res.ok ? 200 : 400);
      }
      const killPaneM = path.match(/^\/agents\/([^/]+)\/panes\/([^/]+)$/);
      if (killPaneM && req.method === "DELETE") {
        const res = await agentKillPane(decodeURIComponent(killPaneM[1]), decodeURIComponent(killPaneM[2]));
        return json(res, res.ok ? 200 : 400);
      }
      const killM = path.match(/^\/agents\/([^/]+)$/);
      if (killM && req.method === "DELETE") {
        const res = await agentKill(decodeURIComponent(killM[1]));
        return json(res, res.ok ? 200 : (res.error === "no such session" ? 404 : 400));
      }
      if (path === "/agents/new" && req.method === "POST") {
        const b = await req.json().catch(() => ({}));
        const name = sanitize(b.name ?? "");
        if (!name) return json({ error: "name required" }, 400);
        if ((await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) return json({ error: "exists" }, 409);
        await sh(`${MUX} new-session -d -s ${shq(name)} ${b.cwd ? `-c ${shq(b.cwd)}` : ""} ${b.cmd ? shq(b.cmd) : ""}`);
        if (b.initialText) {
          await new Promise((resolve) => setTimeout(resolve, 900));
          await agentSend(name, String(b.initialText));
        }
        return json({ ok: true, name });
      }
    } catch (e: any) {
      return json({ error: String(e?.message ?? e) }, 500);
    }
    return json({ error: "not found" }, 404);
  },
});
console.log(`meshd ${VERSION} on http://${HOST}:${PORT}  (host=${os.hostname()} platform=${process.platform})`);

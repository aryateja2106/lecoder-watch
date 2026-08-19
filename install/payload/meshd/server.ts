// meshd — one per machine. System stats + agent (rmux) control + OpenUsage, over Tailscale.
// bun + TypeScript. Auth: Bearer <MESHD_TOKEN>. Bind <MESHD_HOST>:<MESHD_PORT>.
import os from "node:os";
import { homedir } from "node:os";
import { join } from "node:path";
import { appendFile, mkdir, readFile, unlink } from "node:fs/promises";
import { kbPut, kbGet, kbSearch } from "./kb";
import { handleInput } from "./input";

const PORT = Number(process.env.MESHD_PORT ?? "8899");
const HOST = process.env.MESHD_HOST ?? "0.0.0.0";
const TOKEN = process.env.MESHD_TOKEN ?? "";
const VERSION = "0.2.2";
const CAPABILITIES = ["events", "newPane", "paneTarget", "usage", "agents", "cmux", "tailscale", "kb", "screenPeek", "input"];
const IS_MAC = process.platform === "darwin";
// Multiplexer: rmux on macOS, tmux on Linux (tmux-compatible). Override with MESH_MUX.
const MUX = process.env.MESH_MUX ?? (IS_MAC ? "rmux" : "tmux");
const CMUX = process.env.CMUX_BIN ?? "cmux";
const CMUX_SOCKET_HINT = process.env.CMUX_SOCKET_HINT ?? "/tmp/cmux-last-socket-path";
const CMUX_BRIDGE = process.env.CMUX_BRIDGE ?? "http://127.0.0.1:8901";
const EVENTS_PATH = process.env.MESHD_EVENTS_PATH ?? join(homedir(), ".mesh", "agent-events.jsonl");

async function sh(cmd: string): Promise<string> {
  const p = Bun.spawn(["/bin/sh", "-c", cmd], { stdout: "pipe", stderr: "ignore" });
  const out = await new Response(p.stdout).text();
  await p.exited;
  return out;
}

function num(x: string | number | undefined, d = 0): number {
  if (typeof x === "number") return Number.isFinite(x) ? x : d;
  const n = Number(String(x ?? "").trim());
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
  const [cpuPct, mem, dsk, procs, rmuxCount, cmuxCount] = await Promise.all([
    IS_MAC ? macCpuPct() : linuxCpuPct(),
    IS_MAC ? macMem() : linuxMem(),
    disk(),
    topProcs(),
    rmuxSessions().then((s) => s.length).catch(() => 0),
    cmuxSessions().then((s) => s.length).catch(() => 0),
  ]);
  return { host: os.hostname(), platform: process.platform, cpuPct, load: os.loadavg(), mem, disk: dsk, topProcs: procs, agentsCount: rmuxCount + cmuxCount };
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
function isCmuxAgent(name: string) { return name.startsWith("cmux:"); }
function cmuxSurfaceRef(name: string) { return name.slice("cmux:".length); }

async function cmuxEnv(): Promise<Record<string, string | undefined>> {
  const env = { ...process.env };
  if (env.CMUX_SOCKET || env.CMUX_PORT) return env;
  try {
    const sock = (await readFile(CMUX_SOCKET_HINT, "utf8")).trim();
    if (sock) env.CMUX_SOCKET = sock;
  } catch { /* fall through */ }
  if (!env.CMUX_SOCKET && !env.CMUX_PORT) {
    // LaunchAgents often cannot talk to cmux.sock; TCP port still works.
    env.CMUX_PORT = process.env.CMUX_PORT ?? "9160";
  }
  return env;
}

async function cmuxEnvPrefix(): Promise<string> {
  const env = await cmuxEnv();
  if (env.CMUX_PORT) return `CMUX_PORT=${shq(String(env.CMUX_PORT))} `;
  if (env.CMUX_SOCKET) return `CMUX_SOCKET=${shq(String(env.CMUX_SOCKET))} `;
  return "";
}

async function cmuxJson(args: string[]): Promise<any | null> {
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 3000);
    const r = await fetch(`${CMUX_BRIDGE}/cmux`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ args }),
      signal: ctrl.signal,
    }).finally(() => clearTimeout(t));
    if (r.ok) {
      const body = await r.json() as { data?: any; error?: string };
      if (body.error || body.data == null) {
        // #region agent log
        appendFile("/Users/aryateja/Projects/.cursor/debug-71ac4d.log",
          `${JSON.stringify({ sessionId: "71ac4d", hypothesisId: "H6", location: "meshd/server.ts:cmuxJson", message: "bridge cmux error", data: { args: args.join(" "), error: body.error }, timestamp: Date.now() })}\n`,
        ).catch(() => {});
        // #endregion
        return null;
      }
      // #region agent log
      appendFile("/Users/aryateja/Projects/.cursor/debug-71ac4d.log",
        `${JSON.stringify({ sessionId: "71ac4d", hypothesisId: "H3", location: "meshd/server.ts:cmuxJson", message: "cmux bridge ok", data: { args: args.join(" "), via: "bridge" }, timestamp: Date.now() })}\n`,
      ).catch(() => {});
      // #endregion
      return body.data ?? null;
    }
  } catch { /* bridge unreachable */ }

  // #region agent log
  appendFile("/Users/aryateja/Projects/.cursor/debug-71ac4d.log",
    `${JSON.stringify({ sessionId: "71ac4d", hypothesisId: "H5", location: "meshd/server.ts:cmuxJson", message: "bridge down", data: { args: args.join(" ") }, timestamp: Date.now() })}\n`,
  ).catch(() => {});
  // #endregion
  return null;
}

async function pidsForTty(tty: string | null | undefined): Promise<number[]> {
  if (!tty) return [];
  const dev = tty.startsWith("tty") ? tty.slice(3) : tty;
  const out = await sh(`ps -t ${shq(dev)} -o pid= 2>/dev/null`);
  return out.trim().split("\n").map((l) => num(l)).filter((n) => n > 0);
}

async function agentTypeForTty(tty: string | null | undefined): Promise<string | undefined> {
  if (!tty) return undefined;
  const dev = tty.startsWith("tty") ? tty.slice(3) : tty;
  const out = await sh(`ps -t ${shq(dev)} -o comm= 2>/dev/null`).then((s) => s.toLowerCase());
  if (out.includes("claude")) return "Claude";
  if (out.includes("codex")) return "Codex";
  if (out.includes("herdr")) return "shell";
  return undefined;
}

function cleanCmuxLine(line: string): string {
  const m = line.match(/[│▕](.+?)[│▕]?$/);
  return (m?.[1] ?? line).trim();
}

async function cmuxBridgeReady(): Promise<boolean> {
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 2000);
    const r = await fetch(`${CMUX_BRIDGE}/cmux`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ args: ["tree", "--all", "--json"] }),
      signal: ctrl.signal,
    }).finally(() => clearTimeout(t));
    if (!r.ok) return false;
    const body = await r.json() as { data?: { windows?: unknown[] } };
    return Array.isArray(body.data?.windows);
  } catch {
    return false;
  }
}

async function ensureCmuxBridge(): Promise<void> {
  if (!IS_MAC) return;
  const ready = await cmuxBridgeReady();
  // #region agent log
  appendFile("/Users/aryateja/Projects/.cursor/debug-71ac4d.log",
    `${JSON.stringify({ sessionId: "71ac4d", hypothesisId: "H5", location: "meshd/server.ts:ensureCmuxBridge", message: "bridge check", data: { ready, hint: ready ? null : "run ~/.mesh/bin/start-cmux-bridge from a terminal" }, timestamp: Date.now() })}\n`,
  ).catch(() => {});
  // #endregion
}

async function cmuxSessions(): Promise<any[]> {
  if (!IS_MAC) return [];
  await ensureCmuxBridge();
  const tree = await cmuxJson(["tree", "--all", "--json"]);
  const listed = await cmuxJson(["workspace", "list", "--json"]);
  // #region agent log
  appendFile("/Users/aryateja/Projects/.cursor/debug-71ac4d.log",
    `${JSON.stringify({ sessionId: "71ac4d", hypothesisId: "H2", location: "meshd/server.ts:cmuxSessions", message: "tree parsed", data: { hasTree: Boolean(tree), windows: tree?.windows?.length ?? 0, listedWs: listed?.workspaces?.length ?? 0 }, timestamp: Date.now() })}\n`,
  ).catch(() => {});
  // #endregion
  if (!tree?.windows) return [];

  const meta = new Map<string, { title?: string; cwd?: string; updated?: string }>();
  for (const ws of listed?.workspaces ?? []) {
    if (!ws?.ref) continue;
    meta.set(String(ws.ref), {
      title: ws.title ? String(ws.title) : undefined,
      cwd: ws.current_directory ? String(ws.current_directory) : undefined,
      updated: ws.latest_submitted_at ? String(ws.latest_submitted_at) : undefined,
    });
  }

  const table = await procTable();
  const sessions: any[] = [];
  for (const win of tree.windows ?? []) {
    for (const ws of win.workspaces ?? []) {
      const wsMeta = meta.get(String(ws.ref)) ?? {};
      for (const pane of ws.panes ?? []) {
        for (const surf of pane.surfaces ?? []) {
          if (surf.type !== "terminal" || !surf.ref) continue;
          const agentType = await agentTypeForTty(surf.tty);
          const title = String(surf.title || ws.title || wsMeta.title || surf.ref);
          // Skip idle shells with no agent process on the tty.
          if (!agentType && !title.includes("✳") && title.toLowerCase() === "herdr") {
            // herdr workspace host — still show if herdr process present
          } else if (!agentType && !title.includes("✳")) {
            continue;
          }
          const pids = await pidsForTty(surf.tty);
          const { memMB, cpuPct } = sumSubtrees(pids, table);
          sessions.push({
            name: `cmux:${surf.ref}`,
            title,
            windows: num(pane.surface_count, 1),
            createdISO: wsMeta.updated ?? null,
            attached: Boolean(surf.focused || surf.here || surf.active),
            agentType: agentType ?? (title.includes("Codex") ? "Codex" : title.includes("Claude") ? "Claude" : undefined),
            memMB: memMB ? Math.round(memMB) : undefined,
            cpuPct: cpuPct ? Math.round(cpuPct * 10) / 10 : undefined,
          });
        }
      }
    }
  }
  return sessions;
}

async function listAgents() {
  const [rmux, cmux] = await Promise.all([rmuxSessions(), cmuxSessions()]);
  // #region agent log
  appendFile("/Users/aryateja/Projects/.cursor/debug-71ac4d.log",
    `${JSON.stringify({ sessionId: "71ac4d", hypothesisId: "H4", location: "meshd/server.ts:listAgents", message: "agent merge", data: { rmux: rmux.length, cmux: cmux.length, cmuxNames: cmux.map((a) => a.name).join(",") }, timestamp: Date.now() })}\n`,
  ).catch(() => {});
  // #endregion
  return [...rmux, ...cmux];
}

async function cmuxPanes(name: string) {
  const ref = cmuxSurfaceRef(name);
  const meta = await cmuxJson(["workspace", "list", "--json"]);
  let cwd: string | undefined;
  outer: for (const win of (await cmuxJson(["tree", "--all", "--json"]))?.windows ?? []) {
    for (const ws of win.workspaces ?? []) {
      for (const pane of ws.panes ?? []) {
        for (const surf of pane.surfaces ?? []) {
          if (surf.ref === ref) {
            cwd = meta?.workspaces?.find((w: any) => w.ref === ws.ref)?.current_directory;
            break outer;
          }
        }
      }
    }
  }
  return {
    name,
    panes: [{
      paneId: ref,
      windowIndex: 0,
      paneIndex: 0,
      command: "cmux",
      active: true,
      windowName: name,
      currentPath: cwd,
    }],
  };
}

async function cmuxOutput(name: string, lines: number) {
  const ref = cmuxSurfaceRef(name);
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 5000);
    const r = await fetch(`${CMUX_BRIDGE}/cmux`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ args: ["read-screen", "--surface", ref, "--lines", String(Math.max(1, lines))] }),
      signal: ctrl.signal,
    }).finally(() => clearTimeout(t));
    if (r.ok) {
      const body = await r.json() as { data?: string };
      const out = typeof body.data === "string" ? body.data : "";
      const arr = out.split("\n").map(cleanCmuxLine).filter((l) => l.trim().length > 0);
      return { name, lines: arr.slice(-lines) };
    }
  } catch { /* fall through */ }
  const out = await sh(`${await cmuxEnvPrefix()}${CMUX} read-screen --surface ${shq(ref)} --lines ${Math.max(1, lines)} 2>/dev/null`);
  const arr = out.split("\n").map(cleanCmuxLine).filter((l) => l.trim().length > 0);
  return { name, lines: arr.slice(-lines) };
}

const CMUX_KEYS: Record<string, string> = {
  enter: "enter",
  "ctrl-c": "ctrl+c",
  up: "up",
  down: "down",
  left: "left",
  right: "right",
  tab: "tab",
  escape: "escape",
};

async function cmuxSend(name: string, text?: string, key?: string): Promise<{ ok: boolean; error?: string }> {
  const ref = cmuxSurfaceRef(name);
  const bridgeArgs = (args: string[]) => fetch(`${CMUX_BRIDGE}/cmux`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ args }),
  }).then((r) => r.ok);

  if (text) {
    if (await bridgeArgs(["send", "--surface", ref, text]).catch(() => false)) return { ok: true };
    await sh(`${await cmuxEnvPrefix()}${CMUX} send --surface ${shq(ref)} ${shq(text)}`);
  }
  if (key) {
    const mapped = CMUX_KEYS[key];
    if (!mapped) return { ok: false, error: `unsupported key: ${key}` };
    if (await bridgeArgs(["send-key", "--surface", ref, mapped]).catch(() => false)) return { ok: true };
    await sh(`${await cmuxEnvPrefix()}${CMUX} send-key --surface ${shq(ref)} ${mapped}`);
  }
  return { ok: true };
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
  if (isCmuxAgent(name)) return cmuxOutput(name, lines);
  const has = await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`);
  if (!has.trim().endsWith("0")) return null;
  const target = pane ? shq(pane) : shq(name);
  const out = await sh(`${MUX} capture-pane -p -t ${target} 2>/dev/null`);
  const arr = out.replace(/\n+$/, "").split("\n");
  return { name, lines: arr.slice(-lines) };
}
const INFRA = new Set(["meshd", "rmux-bridge"]); // never killable over the wire
async function agentKill(name: string): Promise<{ ok: boolean; error?: string }> {
  if (isCmuxAgent(name)) return { ok: false, error: "cmux sessions cannot be killed from meshd" };
  if (INFRA.has(name)) return { ok: false, error: "infra session is protected" };
  if (!(await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) {
    return { ok: false, error: "no such session" };
  }
  await sh(`${MUX} kill-session -t ${shq(name)}`);
  return { ok: true };
}
async function agentKillPane(name: string, paneId: string): Promise<{ ok: boolean; error?: string }> {
  if (isCmuxAgent(name)) return { ok: false, error: "cmux panes cannot be killed from meshd" };
  if (INFRA.has(name)) return { ok: false, error: "infra session is protected" };
  await sh(`${MUX} kill-pane -t ${shq(paneId)}`);
  return { ok: true };
}
async function agentNewPane(name: string, dir?: string): Promise<{ ok: boolean; error?: string }> {
  if (isCmuxAgent(name)) return { ok: false, error: "cmux sessions do not support new panes via meshd" };
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

async function agentSend(name: string, text?: string, key?: string, pane?: string): Promise<{ ok: boolean; error?: string }> {
  if (isCmuxAgent(name)) return cmuxSend(name, text, key);
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
      // Mac remote control (cursor/keys/scroll/clipboard/volume) — see input.ts.
      const remote = await handleInput(req, url);
      if (remote) return remote;
      if (path === "/stats") return json(await getStats());
      if (path === "/tailnet") return json(await getTailnet());
      if (path === "/agents") return json(await listAgents());
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

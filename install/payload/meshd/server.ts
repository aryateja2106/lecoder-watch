// meshd — one per machine. System stats + agent (rmux) control + OpenUsage, over Tailscale.
// bun + TypeScript. Auth: Bearer <MESHD_TOKEN>. Bind <MESHD_HOST>:<MESHD_PORT>.
import os from "node:os";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { appendFile, mkdir, readFile } from "node:fs/promises";
import { kbPut, kbGet, kbSearch } from "./kb";
import { handleInput } from "./input";
import { handleFiles } from "./files";
import { handlePush, pushAlert, passesPushGate, notePushDecision, pushLiveActivity } from "./push";
import { handlePair } from "./pair";
import { isAuthorized } from "./auth";
import { handleDoctor, tokenWeakness } from "./doctor";
import { sendWake, primaryMac, primaryIPv4, magicPacket } from "./wol";
import { initTelemetry } from "./telemetry";

const PORT = Number(process.env.MESHD_PORT ?? "8899");
const HOST = process.env.MESHD_HOST ?? "0.0.0.0";
const TOKEN = process.env.MESHD_TOKEN ?? "";
const VERSION = "0.5.0";
// 0.5.0 additions, all additive so a 0.4.x daemon and a 0.5 app (or the reverse)
// keep working: screenRegion (rect+quality on /screen.jpg), openUrl (POST /open),
// power (shutdown/restart on /system, results now truthful), laPush (POST /la/token
// + Live Activity pushes), sessionStatus (status fields on /agents rows), paste
// (bracketed multiline paste on /agents/<s>/send), captureJoin (join=1/plain=1 on
// the output route). Clients must gate new behavior on these strings, not on version.
const CAPABILITIES = ["events", "newPane", "paneTarget", "usage", "agents", "cmux", "tailscale", "kb", "screenPeek", "input", "files", "push", "pair", "doctor", "wake", "screenRegion", "openUrl", "power", "laPush", "sessionStatus", "paste", "captureJoin"];
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

/// sh() with nothing discarded — for the paths that must FALL BACK on failure
/// (bracketed paste, sized new-session) instead of pretending it worked.
async function shChecked(cmd: string, stdin?: string): Promise<{ out: string; err: string; code: number }> {
  const p = Bun.spawn(["/bin/sh", "-c", cmd], {
    stdin: stdin === undefined ? "ignore" : "pipe", stdout: "pipe", stderr: "pipe",
  });
  if (stdin !== undefined) { p.stdin.write(stdin); p.stdin.end(); }
  const [out, err] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text()]);
  return { out, err: err.trim(), code: await p.exited };
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
        return null;
      }
      return body.data ?? null;
    }
  } catch { /* bridge unreachable */ }

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
}

async function cmuxSessions(): Promise<any[]> {
  if (!IS_MAC) return [];
  await ensureCmuxBridge();
  const tree = await cmuxJson(["tree", "--all", "--json"]);
  const listed = await cmuxJson(["workspace", "list", "--json"]);
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
  // Additive per-row status from the event index — old clients never look at the
  // extra keys, new clients stop deriving "is it stuck?" from pane heuristics.
  const now = Date.now();
  return [...rmux, ...cmux].map((s) => ({ ...s, ...sessionStatusFields(s.name, Boolean(s.attached), now) }));
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
/// Does this mux's capture-pane understand -J (join soft-wrapped lines)? Probed once
/// at startup against a target that cannot exist: a mux that parses the flag answers
/// "can't find …", one that does not answers "unknown flag …" before ever looking.
/// rmux's flag surface is not pinned anywhere, so asking beats assuming — and the
/// fallback to bare -p is the contract either way.
let joinProbe: Promise<boolean> | null = null;
function muxSupportsJoin(): Promise<boolean> {
  if (!joinProbe) {
    joinProbe = sh(`${MUX} capture-pane -p -J -t mesh-join-probe-no-such-target 2>&1`)
      .then((out) => !/unknown flag|invalid option|illegal option|usage:/i.test(out))
      .catch(() => false);
  }
  return joinProbe;
}

/// Reader mode for a 20-column wrist: box-drawing (U+2500–257F) and braille spinners
/// (U+2800–28FF) removed, space runs collapsed. The chrome of a TUI is exactly what
/// shreds when 80 columns wrap four times on a watch.
function plainLine(line: string): string {
  return line.replace(/[\u2500-\u257F\u2800-\u28FF]/g, "").replace(/ {2,}/g, " ").trimEnd();
}

async function agentOutput(name: string, lines: number, pane?: string, join = false, plain = false) {
  if (isCmuxAgent(name)) {
    const res = await cmuxOutput(name, lines);
    // cmux read-screen has no join concept; plain still applies.
    return plain && res ? { ...res, lines: res.lines.map(plainLine) } : res;
  }
  const has = await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`);
  if (!has.trim().endsWith("0")) return null;
  const target = pane ? shq(pane) : shq(name);
  const joinFlag = join && (await muxSupportsJoin()) ? " -J" : "";
  const out = await sh(`${MUX} capture-pane -p${joinFlag} -t ${target} 2>/dev/null`);
  let arr = out.replace(/\n+$/, "").split("\n");
  if (plain) arr = arr.map(plainLine);
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
async function agentNewPane(name: string, dir?: string, cwd?: string): Promise<{ ok: boolean; error?: string }> {
  if (isCmuxAgent(name)) return { ok: false, error: "cmux sessions do not support new panes via meshd" };
  if (!(await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) {
    return { ok: false, error: "no such session" };
  }
  const flag = dir === "h" ? "-h" : dir === "v" ? "-v" : "";
  // Splitting by session name alone lands the new pane in the mux server's own
  // working directory, not the project the session is sitting in. Ask the active
  // pane where it is and start there, unless the caller named a directory.
  let start = cwd?.trim();
  if (!start) {
    start = (await sh(`${MUX} display -p -t ${shq(name)} '#{pane_current_path}' 2>/dev/null`)).trim();
  }
  const at = start ? `-c ${shq(start)} ` : "";
  const out = await sh(`${MUX} split-window ${flag} ${at}-t ${shq(name)} 2>&1; echo $?`);
  if (!out.trim().endsWith("0") && at) {
    // An unreadable or vanished directory should not cost the user their pane.
    await sh(`${MUX} split-window ${flag} -t ${shq(name)}`);
  }
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

async function agentSend(name: string, text?: string, key?: string, pane?: string, paste?: boolean): Promise<{ ok: boolean; error?: string }> {
  if (isCmuxAgent(name)) return cmuxSend(name, text, key);
  const hasText = typeof text === "string" && text.length > 0;
  const hasKey = typeof key === "string" && key.length > 0;
  if (!hasText && !hasKey) return { ok: false, error: "text or key required" };

  const sendKey = hasKey ? KEY_SEND_KEYS[key] : undefined;
  if (hasKey && !sendKey) return { ok: false, error: `unsupported key: ${key}` };

  // send-keys to a name the mux cannot resolve fails on stderr we discard, so
  // without this check the route answered ok:true for a reply that went nowhere —
  // the silent half of the dead-reply-button defect.
  if (!(await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) {
    return { ok: false, error: "session not addressable" };
  }

  const target = pane ? shq(pane) : shq(name);
  if (hasText) {
    let delivered = false;
    // paste:true and a newline in the text: send-keys types the newlines, and a TUI
    // treats each one as submit — a pasted paragraph becomes five submissions.
    // load-buffer + paste-buffer -p delivers it as one bracketed paste instead.
    // rmux's buffer commands are unverified, so ANY failure here falls through to
    // the hex send-keys path that has always worked — degraded, never dropped.
    if (paste === true && text.includes("\n")) {
      const load = await shChecked(`${MUX} load-buffer -`, text).catch(() => ({ code: 1, out: "", err: "" }));
      if (load.code === 0) {
        const pasted = await shChecked(`${MUX} paste-buffer -dpr -t ${target}`).catch(() => ({ code: 1, out: "", err: "" }));
        delivered = pasted.code === 0;
      }
    }
    if (!delivered) {
      const hex = Array.from(new TextEncoder().encode(text), (b) => b.toString(16).padStart(2, "0")).join(" ");
      await sh(`${MUX} send-keys -t ${target} -H -- ${hex}`);
    }
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

// The /screen.jpg route — with or without a display named, full frame or region —
// lives in input.ts (captureScreen) since 0.5.0, so one parser and one capture path
// serve every client. handleInput claims it before the routes below ever match.

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
  // Whether /agents/<session>/send can reach this event's sender. Absent on events
  // from producers that never said — treated as "unknown", not as false, so nothing
  // that exists today changes behavior.
  replyable?: boolean;
  // Exact mux pane (#S:#I.#P) the event came from; a reply sent with this as the
  // pane target lands in the agent's pane even when another pane is active.
  pane?: string;
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

// ---------- per-session status ----------
// The last event each session posted, in memory: /agents stamps a status on every
// row from it, so both clients read one truth over the endpoint they already poll.
// Warmed once at boot from the tail of the JSONL so a daemon restart does not blank
// every row to "idle".
type LastSessionEvent = { level?: string; title: string; iso: string; atMs: number };
const lastEventBySession = new Map<string, LastSessionEvent>();
// Sessions whose current wait was announced with a Live Activity push — the set that
// still owes the Lock Screen an "end" once the wait clears.
const laActiveSessions = new Set<string>();

/// How many sessions' worth of status we keep. Session names come from callers, so
/// without a ceiling a long-lived daemon accumulates a row per name it has ever seen.
const MAX_TRACKED_SESSIONS = 500;

function noteSessionEvent(event: AgentEvent) {
  if (!event.session) return;
  const now = Date.now();
  // A clock-skewed or hand-written future timestamp would otherwise win every
  // comparison below forever, freezing the row on whatever level it arrived with.
  const atMs = Math.min(Date.parse(event.createdISO) || now, now);
  const prev = lastEventBySession.get(event.session);
  if (prev && prev.atMs > atMs) return;
  // Re-insert so the Map's insertion order tracks recency; the oldest row leaves.
  lastEventBySession.delete(event.session);
  lastEventBySession.set(event.session, { level: event.level, title: event.title, iso: event.createdISO, atMs });
  while (lastEventBySession.size > MAX_TRACKED_SESSIONS) {
    const oldest = lastEventBySession.keys().next().value;
    if (oldest === undefined) break;
    lastEventBySession.delete(oldest);
    laActiveSessions.delete(oldest);
  }
}

const ERROR_LEVELS = new Set(["error", "failed", "failure"]);
const WAITING_LEVELS = new Set(["warning", "needs-input", "needs_input", "needsinput"]);

/// One word per session for the list rows. Precedence: a fresh error outranks a
/// fresh question outranks liveness. "waiting"/"error" age out after an hour (a
/// question nobody answered all morning is stale, not actionable); "working" means
/// someone is attached or an event landed in the last five minutes; everything
/// else — including a finished turn once its five minutes lapse — is "idle".
function sessionStatusFields(name: string, attached: boolean, nowMs: number): { status: "working" | "waiting" | "error" | "idle"; lastEventLevel?: string; lastEventISO?: string } {
  const last = lastEventBySession.get(name);
  const ageMin = last ? (nowMs - last.atMs) / 60000 : Infinity;
  const level = String(last?.level ?? "").toLowerCase();
  let status: "working" | "waiting" | "error" | "idle";
  if (last && ageMin < 60 && ERROR_LEVELS.has(level)) status = "error";
  else if (last && ageMin < 60 && (WAITING_LEVELS.has(level) || /needs[ _-](attention|input)/i.test(last.title))) status = "waiting";
  else if (attached || (last && ageMin < 5)) status = "working";
  else status = "idle";
  return { status, lastEventLevel: last?.level, lastEventISO: last?.iso };
}

/// The Live Activity card's changing half. Keys mirror ContentState in
/// Shared/SessionActivity.swift exactly; Date-typed fields stay out on purpose
/// (see pushLiveActivity in push.ts for why).
function laContentState(event: AgentEvent, stateRaw?: string): Record<string, unknown> {
  const level = String(event.level ?? "").toLowerCase();
  const source = String(event.source ?? "").toLowerCase();
  return {
    stateRaw: stateRaw ?? (ERROR_LEVELS.has(level) ? "error" : "waiting"),
    agentType: source.includes("claude") ? "claude" : source.includes("codex") ? "codex" : "shell",
    lastLine: (event.body ?? event.title).slice(0, 120),
  };
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
    replyable: typeof input.replyable === "boolean" ? input.replyable : undefined,
    pane: input.pane ? String(input.pane) : undefined,
  };
  // The directory the events actually live in — not ~/.mesh unconditionally, which
  // both touched the real home under a redirected MESHD_EVENTS_PATH and failed to
  // create the directory the append below needs.
  await mkdir(dirname(EVENTS_PATH), { recursive: true, mode: 0o700 });
  await appendFile(EVENTS_PATH, `${JSON.stringify(event)}\n`);
  noteSessionEvent(event);
  // The flood fix: every event is stored for the pollers above, but only the ones a
  // person can act on — warnings, errors, needs-input — become an APNs buzz. It used
  // to push unconditionally, which made every turn end of every session a full
  // time-insensitive interruption. All pushes stay fire-and-forget so a slow or
  // misconfigured APNs setup never blocks event ingestion.
  const worthPushing = passesPushGate(event.level, event.title);
  notePushDecision(worthPushing);
  if (worthPushing) {
    pushAlert(event.title, event.body, { level: event.level, session: event.session, host: event.host, replyable: event.replyable }).catch(() => {});
    if (event.session) {
      const session = event.session;
      const contentState = laContentState(event);
      const alert = { title: event.title, body: event.body };
      const attributes = { host: (event.host ?? os.hostname()).replace(/\.local$/i, ""), session };
      laActiveSessions.add(session);
      // Start conjures the card on a pocketed phone; the update refreshes a card
      // already live for this session. iOS treats a start for a live identity as an
      // update, so sending both is convergence, not duplication.
      pushLiveActivity("start", { attributes, contentState, alert }).catch(() => {});
      pushLiveActivity("update", { session, contentState, alert }).catch(() => {});
    }
  } else if (event.session && laActiveSessions.has(event.session)) {
    // The wait cleared (a calm event followed the alerting one): dismiss the card
    // instead of leaving "needs attention" lying on the Lock Screen.
    laActiveSessions.delete(event.session);
    pushLiveActivity("end", { session: event.session, contentState: laContentState(event, "idle") }).catch(() => {});
  }
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
// Header-only for anything off-box, fail-closed, constant-time — see auth.ts.
// An empty MESHD_TOKEN no longer means "open": it means loopback-only, because this
// daemon executes shell commands and a misconfigured unit file must not be an RCE.
//
// Loopback is the one exception, and it is not a relaxation: a process running as
// this user on this machine can already read ~/.mesh/token (mode 600) and execute
// anything, so demanding a bearer token from 127.0.0.1 protects nothing while
// blocking this Mac's own browser from /desktop. Decided from the socket peer
// address via server.requestIP — never from a header, which a remote client controls.
function isLoopback(server: any, req: Request): boolean {
  const address = server?.requestIP?.(req)?.address ?? "";
  return address === "127.0.0.1" || address === "::1" || address === "::ffff:127.0.0.1";
}
// A request a browser marks cross-site cannot be one of our clients: URLSession and
// the mesh CLI send neither header, and the /desktop page fetches same-origin. So a
// present Origin, or a cross-site Sec-Fetch-Site, is a page attacking the loopback
// interface — rejected before the exemption or the token can wave it through.
function isBrowserCrossSite(req: Request): boolean {
  const site = req.headers.get("sec-fetch-site");
  if (site && site !== "same-origin" && site !== "none") return true;
  return req.headers.get("origin") !== null;
}
function authed(req: Request, server?: any): boolean {
  if (isBrowserCrossSite(req)) return false;
  if (isLoopback(server, req)) return true;
  return isAuthorized(TOKEN, req.headers.get("authorization") ?? "");
}

const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "::1", "[::1]"]);
function hostAllowed(req: Request): boolean {
  const raw = req.headers.get("host");
  if (!raw) return true; // no Host = not a browser; the auth gate still applies
  const host = raw.replace(/:\d+$/, "").toLowerCase();
  if (LOOPBACK_HOSTS.has(host)) return true;
  if (/\.ts\.net$/.test(host)) return true;   // tailscale MagicDNS
  return localIPs().has(host);                  // this machine's own IPs (incl. tailscale)
}

function localIPs(): Set<string> {
  const set = new Set<string>();
  for (const list of Object.values(os.networkInterfaces())) {
    for (const i of list ?? []) if (i.address) set.add(i.address);
  }
  return set;
}

async function peerHosts(): Promise<Map<string, { token?: string; port?: number }>> {
  const map = new Map<string, { token?: string; port?: number }>();
  try {
    const cfg = JSON.parse(await readFile(join(homedir(), ".mesh", "hosts.json"), "utf8"));
    for (const h of Object.values<any>(cfg?.hosts ?? {})) {
      if (h?.ip) map.set(String(h.ip), { token: h.token ? String(h.token) : undefined, port: h.port ? Number(h.port) : undefined });
    }
  } catch {}
  return map;
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
  // Fan out only to hosts in ~/.mesh/hosts.json, each with its own token. Tokens are
  // per-machine since pairing, so sending OURS to arbitrary online peers both leaked
  // it to anything listening on :8899 and failed their auth anyway.
  const known = await peerHosts();
  const peers = ((tn as any).peers ?? []).filter(
    (p: any) => p.online && p.ips?.length && !p.ips.some((ip: string) => mine.has(ip))
      && p.ips.some((ip: string) => known.has(ip)),
  );
  const settled = await Promise.allSettled(peers.map((p: any) => {
    const ip = p.ips.find((x: string) => known.has(x)) ?? p.ips[0];
    const peer = known.get(ip)!;
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 2000);
    return fetch(`http://${ip}:${peer.port ?? PORT}/kb/search?${qs.toString()}`, {
      headers: peer.token ? { authorization: `Bearer ${peer.token}` } : {},
      signal: ctrl.signal,
    }).then((r) => (r.ok ? r.json() : { results: [] })).finally(() => clearTimeout(t));
  }));
  const merged = [...local];
  for (const r of settled) if (r.status === "fulfilled") merged.push(...((r.value as any)?.results ?? []));
  const seen = new Set<string>();
  const out: any[] = [];
  for (const e of merged) {
    const k = `${e.host}\u0000${e.scope}\u0000${e.key}`;
    if (!seen.has(k)) { seen.add(k); out.push(e); }
  }
  return out;
}

Bun.serve({
  port: PORT,
  hostname: HOST,
  async fetch(req, server) {
    const url = new URL(req.url);
    const path = url.pathname;
    if (!hostAllowed(req)) return json({ error: "bad host" }, 421);
    if (path === "/health") {
      // mac is here so a phone can cache it while this machine is up: once it sleeps,
      // nothing can be asked of it, and a peer needs the address to wake it. It is not
      // a secret — every frame on the LAN already carries it. ipv4+netmask travel for
      // the same reason: they let a phone compute this machine's directed broadcast
      // later and pick a wake peer that actually shares its LAN.
      const net = primaryIPv4();
      return json({ ok: true, host: os.hostname(), platform: process.platform, arch: process.arch, uptimeSec: Math.round(os.uptime()), meshdVersion: VERSION, capabilities: CAPABILITIES, mac: primaryMac(), ipv4: net?.address ?? null, netmask: net?.netmask ?? null });
    }
    // Pairing is the one route that must answer without a token — it is how the
    // phone gets one. See pair.ts for why that is safe.
    const paired = await handlePair(req, url, server, { port: PORT, token: TOKEN });
    if (paired) return paired;
    if (!authed(req, server)) return json({ error: "unauthorized" }, 401);
    try {
      // Setup truth: what this daemon can actually do right now — see doctor.ts.
      // The token is judged here and only a verdict travels on, so a doctor report can
      // never leak the thing it is reporting on.
      const doc = await handleDoctor(req, url, {
        tokenSet: Boolean(TOKEN),
        tokenWeak: TOKEN ? (tokenWeakness(TOKEN) ?? undefined) : undefined,
        bind: HOST, port: PORT, version: VERSION, mux: MUX,
      });
      if (doc) return doc;
      // Mac remote control (cursor/keys/scroll/clipboard/volume) — see input.ts.
      const remote = await handleInput(req, url);
      if (remote) return remote;
      const files = await handleFiles(req, url);
      if (files) return files;
      // APNs device registration + status + test — see push.ts.
      const pushed = await handlePush(req, url);
      if (pushed) return pushed;
      // Wake a sleeping machine on this LAN — this daemon is the phone's only way to
      // put a magic packet on the wire. See wol.ts.
      if (path === "/wake" && req.method === "POST") {
        const body = (await req.json().catch(() => ({}))) as any;
        const mac = String(body?.mac ?? "");
        // Two catches so the phone can tell "fix the request" from "retry later": a
        // malformed MAC is 400, a packet that could not leave this machine is 502.
        try { magicPacket(mac); } catch (e: any) { return json({ error: String(e?.message ?? e) }, 400); }
        try { await sendWake(mac, body?.broadcast ? String(body.broadcast) : undefined); }
        catch (e: any) { return json({ error: String(e?.message ?? e) }, 502); }
        return json({ ok: true });
      }
      if (path === "/stats") return json(await getStats());
      if (path === "/tailnet") return json(await getTailnet());
      if (path === "/agents") return json(await listAgents());
      if (path === "/usage") return json(await getUsage());
      if (path === "/events" && req.method === "GET") return json(await readEvents(url.searchParams.get("since")));
      if (path === "/events" && req.method === "POST") return json(await addEvent((await req.json().catch(() => ({}))) as any), 201);
      if (path === "/kb" && (req.method === "PUT" || req.method === "POST")) {
        try { return json(kbPut((await req.json().catch(() => ({}))) as any, os.hostname()), 201); }
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
        const body = (await req.json().catch(() => ({}))) as any;
        const res = await agentNewPane(decodeURIComponent(panesM[1]), body.dir, body.cwd);
        return json(res, res.ok ? 201 : 404);
      }
      const outM = path.match(/^\/agents\/([^/]+)\/output$/);
      if (outM && req.method === "GET") {
        const res = await agentOutput(
          decodeURIComponent(outM[1]),
          Number(url.searchParams.get("lines") ?? "80"),
          url.searchParams.get("pane") ?? undefined,
          url.searchParams.get("join") === "1",
          url.searchParams.get("plain") === "1",
        );
        return res ? json(res) : json({ error: "no such session" }, 404);
      }
      const sendM = path.match(/^\/agents\/([^/]+)\/send$/);
      if (sendM && req.method === "POST") {
        const body = (await req.json().catch(() => ({}))) as any;
        const res = await agentSend(decodeURIComponent(sendM[1]), body.text, body.key, body.pane, body.paste === true);
        return json(res, res.ok ? 200 : (res.error === "session not addressable" ? 404 : 400));
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
        const b = (await req.json().catch(() => ({}))) as any;
        const name = sanitize(b.name ?? "");
        if (!name) return json({ error: "name required" }, 400);
        if ((await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) return json({ error: "exists" }, 409);
        // Optional cols/rows so a wrist-created session can be 60×30 instead of the
        // detached default 80×24 that wraps four times on a watch. Only sessions the
        // app itself creates are sized — nothing here ever resizes a session a person
        // attached from a desk terminal.
        const colsN = Math.round(Number(b.cols));
        const rowsN = Math.round(Number(b.rows));
        const cols = Number.isFinite(colsN) && colsN > 0 ? Math.min(500, Math.max(20, colsN)) : null;
        const rows = Number.isFinite(rowsN) && rowsN > 0 ? Math.min(200, Math.max(5, rowsN)) : null;
        const size = `${cols ? `-x ${cols} ` : ""}${rows ? `-y ${rows} ` : ""}`;
        const base = `new-session -d -s ${shq(name)} ${b.cwd ? `-c ${shq(b.cwd)} ` : ""}`;
        const tail = b.cmd ? shq(b.cmd) : "";
        if (size) {
          // rmux's -x/-y support is unverified: try sized, and if the session never
          // appeared, create it plain and ask resize-window afterwards — whose own
          // failure is tolerated. A session always beats an exactly-sized nothing.
          await sh(`${MUX} ${base}${size}${tail} 2>&1`);
          if (!(await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) {
            await sh(`${MUX} ${base}${tail}`);
            await sh(`${MUX} resize-window ${size}-t ${shq(name)} 2>/dev/null`);
          }
        } else {
          await sh(`${MUX} ${base}${tail}`);
        }
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
initTelemetry(VERSION);
// Warm the per-session status index from the stored tail, and settle the capture-pane
// -J question once, before the first client asks. Both are best-effort: an empty
// index just means rows start as idle/working until events arrive.
readEvents().then((events) => { for (const e of events) noteSessionEvent(e); }).catch(() => {});
muxSupportsJoin().catch(() => {});

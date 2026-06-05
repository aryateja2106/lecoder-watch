// meshd — one per machine. System stats + agent (rmux) control + OpenUsage, over Tailscale.
// bun + TypeScript. Auth: Bearer <MESHD_TOKEN>. Bind 0.0.0.0:<MESHD_PORT> (tailnet-private).
import os from "node:os";
import { homedir } from "node:os";
import { join } from "node:path";

const PORT = Number(process.env.MESHD_PORT ?? "8899");
const TOKEN = process.env.MESHD_TOKEN ?? "";
const VERSION = "0.1.0";
const IS_MAC = process.platform === "darwin";
// Multiplexer: rmux on macOS, tmux on Linux (tmux-compatible). Override with MESH_MUX.
const MUX = process.env.MESH_MUX ?? (IS_MAC ? "rmux" : "tmux");

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
    rmuxSessions().then((s) => s.length).catch(() => 0),
  ]);
  return { host: os.hostname(), platform: process.platform, cpuPct, load: os.loadavg(), mem, disk: dsk, topProcs: procs, agentsCount };
}

// ---------- agents (rmux) ----------
async function rmuxSessions(): Promise<any[]> {
  const out = await sh(`${MUX} list-sessions -F '#{session_name}|#{session_windows}|#{session_created}|#{session_attached}' 2>/dev/null`);
  if (!out.trim()) return [];
  const rows = out.trim().split("\n").map((l) => l.split("|"));
  const sessions = [] as any[];
  const HIDDEN = new Set(["meshd", "rmux-bridge"]); // infra, not user agents
  for (const r of rows) {
    const name = r[0];
    if (HIDDEN.has(name)) continue;
    let agentType: string | undefined;
    const cmd = (await sh(`${MUX} list-panes -t ${shq(name)} -F '#{pane_current_command}' 2>/dev/null | head -1`)).trim();
    if (cmd) agentType = mapAgent(cmd);
    sessions.push({
      name,
      windows: num(r[1]),
      createdISO: r[2] ? new Date(num(r[2]) * 1000).toISOString() : null,
      attached: r[3] === "1",
      agentType,
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

async function agentPanes(name: string) {
  const has = await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`);
  if (!has.trim().endsWith("0")) return null;
  const out = await sh(`${MUX} list-panes -s -t ${shq(name)} -F '#{window_index}.#{pane_index}|#{pane_id}|#{pane_current_command}|#{pane_active}|#{window_name}' 2>/dev/null`);
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
    };
  });
  return { name, panes };
}
async function agentOutput(name: string, lines: number, pane?: string) {
  const has = await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`);
  if (!has.trim().endsWith("0")) return null;
  const target = pane ? shq(pane) : shq(name);
  const out = await sh(`${MUX} capture-pane -p -t ${target} 2>/dev/null`);
  const arr = out.replace(/\n+$/, "").split("\n");
  return { name, lines: arr.slice(-lines) };
}
async function agentSend(name: string, text?: string, key?: string, pane?: string) {
  const target = pane ? shq(pane) : shq(name);
  if (key === "enter") await sh(`${MUX} send-keys -t ${target} Enter`);
  else if (key === "ctrl-c") await sh(`${MUX} send-keys -t ${target} C-c`);
  else if (key === "up") await sh(`${MUX} send-keys -t ${target} Up`);
  else if (key === "down") await sh(`${MUX} send-keys -t ${target} Down`);
  else if (text) {
    const hex = Array.from(new TextEncoder().encode(text), (b) => b.toString(16).padStart(2, "0")).join(" ");
    await sh(`${MUX} send-keys -t ${target} -H -- ${hex}`);
  }
  return { ok: true };
}

// ---------- usage (OpenUsage) ----------
const KNOWN_LABELS = new Set(["Today", "Yesterday", "Last 30 Days", "Account", "Credits", "Usage Trend"]);
async function getUsage() {
  if (!IS_MAC) return { providers: [] };
  const path = join(homedir(), "Library/Application Support/com.sunstory.openusage/usage-api-cache.json");
  const file = Bun.file(path);
  if (!(await file.exists())) return { providers: [] };
  const raw = await file.json();
  const providers = Object.values(raw.snapshots ?? {}).map((s: any) => {
    const limits: any[] = [], topModels: any[] = [];
    let today, yesterday, last30;
    for (const line of s.lines ?? []) {
      if (line.type === "progress" && line.format?.kind === "percent") {
        limits.push({ label: line.label, usedPct: line.limit ? (line.used / line.limit) * 100 : null, resetsAtISO: line.resetsAt ?? null, periodDurationMs: line.periodDurationMs ?? null });
      } else if (line.type === "text") {
        if (line.label === "Today") today = line.value;
        else if (line.label === "Yesterday") yesterday = line.value;
        else if (line.label === "Last 30 Days") last30 = line.value;
        else if (!KNOWN_LABELS.has(line.label) && line.label.includes("-")) topModels.push({ label: line.label, pct: line.value });
      }
    }
    return { id: s.providerId, displayName: s.displayName, plan: s.plan ?? null, limits, today, yesterday, last30, topModels };
  });
  return { fetchedAt: raw.snapshots?.codex?.fetchedAt, providers };
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

Bun.serve({
  port: PORT,
  hostname: "0.0.0.0",
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;
    if (path === "/health") {
      return json({ ok: true, host: os.hostname(), platform: process.platform, arch: process.arch, uptimeSec: Math.round(os.uptime()), meshdVersion: VERSION });
    }
    if (!authed(req)) return json({ error: "unauthorized" }, 401);
    try {
      if (path === "/stats") return json(await getStats());
      if (path === "/agents") return json(await rmuxSessions());
      if (path === "/usage") return json(await getUsage());
      const panesM = path.match(/^\/agents\/([^/]+)\/panes$/);
      if (panesM && req.method === "GET") {
        const res = await agentPanes(decodeURIComponent(panesM[1]));
        return res ? json(res) : json({ error: "no such session" }, 404);
      }
      const outM = path.match(/^\/agents\/([^/]+)\/output$/);
      if (outM && req.method === "GET") {
        const res = await agentOutput(decodeURIComponent(outM[1]), Number(url.searchParams.get("lines") ?? "80"), url.searchParams.get("pane") ?? undefined);
        return res ? json(res) : json({ error: "no such session" }, 404);
      }
      const sendM = path.match(/^\/agents\/([^/]+)\/send$/);
      if (sendM && req.method === "POST") {
        const body = await req.json().catch(() => ({}));
        return json(await agentSend(decodeURIComponent(sendM[1]), body.text, body.key, body.pane));
      }
      if (path === "/agents/new" && req.method === "POST") {
        const b = await req.json().catch(() => ({}));
        const name = sanitize(b.name ?? "");
        if (!name) return json({ error: "name required" }, 400);
        if ((await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) return json({ error: "exists" }, 409);
        await sh(`${MUX} new-session -d -s ${shq(name)} ${b.cwd ? `-c ${shq(b.cwd)}` : ""} ${b.cmd ? shq(b.cmd) : ""}`);
        return json({ ok: true, name });
      }
    } catch (e: any) {
      return json({ error: String(e?.message ?? e) }, 500);
    }
    return json({ error: "not found" }, 404);
  },
});
console.log(`meshd ${VERSION} on http://0.0.0.0:${PORT}  (host=${os.hostname()} platform=${process.platform})`);

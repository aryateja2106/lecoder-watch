// meshd — one per machine. System stats + agent (rmux) control + OpenUsage, over Tailscale.
// bun + TypeScript. Auth: Bearer <MESHD_TOKEN>. Bind <MESHD_HOST>:<MESHD_PORT>.
import os from "node:os";
import { homedir } from "node:os";
import { join } from "node:path";
import { appendFile, mkdir, readFile } from "node:fs/promises";
import { kbPut, kbGet, kbSearch } from "./kb";

const PORT = Number(process.env.MESHD_PORT ?? "8899");
const HOST = process.env.MESHD_HOST ?? "0.0.0.0";
const TOKEN = process.env.MESHD_TOKEN ?? "";
const VERSION = "0.2.0";
const CAPABILITIES = ["events", "newPane", "paneTarget", "usage", "agents", "tailscale", "kb"];
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
    rmuxSessions().then((s) => s.length).catch(() => 0),
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

async function agentPanes(name: string) {
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
  const has = await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`);
  if (!has.trim().endsWith("0")) return null;
  const target = pane ? shq(pane) : shq(name);
  const out = await sh(`${MUX} capture-pane -p -t ${target} 2>/dev/null`);
  const arr = out.replace(/\n+$/, "").split("\n");
  return { name, lines: arr.slice(-lines) };
}
const INFRA = new Set(["meshd", "rmux-bridge"]); // never killable over the wire
async function agentKill(name: string): Promise<{ ok: boolean; error?: string }> {
  if (INFRA.has(name)) return { ok: false, error: "infra session is protected" };
  if (!(await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) {
    return { ok: false, error: "no such session" };
  }
  await sh(`${MUX} kill-session -t ${shq(name)}`);
  return { ok: true };
}
async function agentKillPane(name: string, paneId: string): Promise<{ ok: boolean; error?: string }> {
  if (INFRA.has(name)) return { ok: false, error: "infra session is protected" };
  await sh(`${MUX} kill-pane -t ${shq(paneId)}`);
  return { ok: true };
}
async function agentNewPane(name: string, dir?: string): Promise<{ ok: boolean; error?: string }> {
  if (!(await sh(`${MUX} has-session -t ${shq(name)} 2>&1; echo $?`)).trim().endsWith("0")) {
    return { ok: false, error: "no such session" };
  }
  const flag = dir === "h" ? "-h" : dir === "v" ? "-v" : "";
  await sh(`${MUX} split-window ${flag} -t ${shq(name)}`);
  return { ok: true };
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
      if (path === "/agents") return json(await rmuxSessions());
      if (path === "/usage") return json(await getUsage());
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
        return json(await agentSend(decodeURIComponent(sendM[1]), body.text, body.key, body.pane));
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

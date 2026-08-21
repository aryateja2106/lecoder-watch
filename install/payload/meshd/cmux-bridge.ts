// cmux-bridge — user-session proxy for cmux CLI (meshd LaunchAgent cannot call cmux directly).
import { readFile } from "node:fs/promises";

const PORT = Number(process.env.CMUX_BRIDGE_PORT ?? "8901");
const HOST = process.env.CMUX_BRIDGE_HOST ?? "127.0.0.1";
const CMUX_SOCKET_HINT = process.env.CMUX_SOCKET_HINT ?? "/tmp/cmux-last-socket-path";

let cmuxChain: Promise<unknown> = Promise.resolve();
async function withCmuxLock<T>(fn: () => Promise<T>): Promise<T> {
  const run = cmuxChain.then(fn, fn);
  cmuxChain = run.then(() => undefined, () => undefined);
  return run;
}

async function cmuxPrefix(): Promise<string> {
  if (process.env.CMUX_PORT) return `CMUX_PORT=${shq(process.env.CMUX_PORT)} `;
  if (process.env.CMUX_SOCKET) return `CMUX_SOCKET=${shq(process.env.CMUX_SOCKET)} `;
  try {
    const sock = (await readFile(CMUX_SOCKET_HINT, "utf8")).trim();
    if (sock) return `CMUX_SOCKET=${shq(sock)} `;
  } catch { /* cmux not running */ }
  return "CMUX_PORT='9160' ";
}

function shq(s: string) { return `'${s.replace(/'/g, `'\\''`)}'`; }

async function sh(cmd: string): Promise<{ out: string; err: string; code: number }> {
  const p = Bun.spawn(["/bin/sh", "-c", cmd], { stdout: "pipe", stderr: "pipe", env: process.env });
  const out = await new Response(p.stdout).text();
  const err = await new Response(p.stderr).text();
  await p.exited;
  return { out, err, code: p.exitCode ?? 1 };
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

async function peerHealthy(): Promise<boolean> {
  try {
    const r = await fetch(`http://${HOST}:${PORT}/cmux`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ args: ["tree", "--all", "--json"] }),
      signal: AbortSignal.timeout(2000),
    });
    if (!r.ok) return false;
    const body = await r.json() as { data?: { windows?: unknown[] } };
    return Array.isArray(body.data?.windows) && body.data!.windows!.length > 0;
  } catch {
    return false;
  }
}

async function startServer() {
  try {
    const server = Bun.serve({
      port: PORT,
      hostname: HOST,
      async fetch(req) {
        const url = new URL(req.url);
        if (url.pathname === "/health") return json({ ok: true, port: PORT });

        if (url.pathname === "/cmux" && req.method === "POST") {
          const body = await req.json().catch(() => ({})) as { args?: string[] };
          const args = body.args ?? [];
          if (!args.length) return json({ error: "args required" }, 400);
          const quoted = args.map((a) => `'${String(a).replace(/'/g, `'\\''`)}'`).join(" ");
          const prefix = await cmuxPrefix();
          const r = await withCmuxLock(() => sh(`${prefix}cmux ${quoted}`));
          if (r.code !== 0) return json({ error: r.err.trim() || "cmux failed", code: r.code }, 502);
          const wantsJson = args[0] === "tree" || (args[0] === "workspace" && args[1] === "list");
          if (wantsJson) {
            try { return json({ data: JSON.parse(r.out) }); } catch { /* fall through */ }
          }
          return json({ data: r.out, text: true });
        }

        return json({ error: "not found" }, 404);
      },
    });
    (globalThis as { __cmuxBridgeServer?: typeof server }).__cmuxBridgeServer = server;
    console.log(`cmux-bridge on http://${HOST}:${PORT}`);

    const prefix = await cmuxPrefix();
    const probe = await withCmuxLock(() => sh(`${prefix}cmux tree --all --json`));
    if (probe.code !== 0 || probe.err.includes("Broken pipe")) {
      process.exit(1);
    }
    try {
      const tree = JSON.parse(probe.out) as { windows?: unknown[] };
      if (!Array.isArray(tree.windows) || tree.windows.length === 0) {
        process.exit(1);
      }
    } catch {
      process.exit(1);
    }
  } catch (e: any) {
    if (e?.code === "EADDRINUSE") {
      if (await peerHealthy()) {
        process.exit(0);
      }
    }
    throw e;
  }
}

await startServer();

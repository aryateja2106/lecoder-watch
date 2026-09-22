// pty.ts — GET /agents/:name/pty (WebSocket): attaches the session in a real pty and streams its bytes both ways, so a phone can run a terminal emulator instead of polling capture-pane text.
//
// One attach per socket: `tmux attach-session -t <name>` under a `Bun.Terminal` sized to the
// client (the mux resizes the window to its latest client), binary frames carry raw pty bytes
// in both directions, text frames carry the little control protocol below. Closing the socket
// kills the attach, never the session. Bun.Terminal is built into bun ≥ 1.3, so this adds no
// dependency to the payload.
//
//   client → server  binary            keystrokes / paste, exactly as an emulator emits them
//   client → server  {"t":"resize","cols":N,"rows":N}
//   client → server  {"t":"ping"}      answered {"t":"pong"}
//   server → client  binary            pty output, redacted line-wise like every other byte path
//   server → client  {"t":"exit","code":N}   the attach ended (session gone, mux died)
//   server → client  {"t":"error","msg":"…"}
// Findings land on the "bridge" channel: this route is what the bridge page streamed before.
import { redact, record, type Finding } from "./redact";

const PTY_DEDUPE_MS = 10 * 60_000;

/// `mux` is the same string server.ts splices into shell lines ("rmux", "tmux",
/// "tmux -L sock" in the checks), so it is split into argv here.
export type PtyOpts = { mux: string; shq: (s: string) => string };
const argv = (opts: PtyOpts) => opts.mux.trim().split(/\s+/);

type Conn = {
  name: string;
  pane?: string;
  cols: number;
  rows: number;
  term?: InstanceType<typeof Bun.Terminal>;
  proc?: ReturnType<typeof Bun.spawn>;
  decoder: TextDecoder;
};

function clamp(n: number, lo: number, hi: number, dflt: number) {
  return Number.isFinite(n) ? Math.min(hi, Math.max(lo, Math.round(n))) : dflt;
}

/// Upgrade the request, or answer why not. Auth has already passed in server.ts. Returns
/// `undefined` when the socket was taken over (Bun's contract for a completed upgrade).
export async function handlePtyUpgrade(req: Request, url: URL, server: any, opts: PtyOpts): Promise<Response | undefined | null> {
  const m = url.pathname.match(/^\/agents\/([^/]+)\/pty$/);
  if (!m || req.method !== "GET") return null;
  const name = decodeURIComponent(m[1]);
  if (name.includes(":")) return Response.json({ error: "only tmux/rmux sessions attach" }, { status: 400 });
  const has = Bun.spawnSync([...argv(opts), "has-session", "-t", name]);
  if (has.exitCode !== 0) return Response.json({ error: "no such session" }, { status: 404 });
  const data: Conn = {
    name,
    pane: url.searchParams.get("pane") ?? undefined,
    cols: clamp(Number(url.searchParams.get("cols")), 20, 400, 80),
    rows: clamp(Number(url.searchParams.get("rows")), 5, 200, 24),
    decoder: new TextDecoder("utf-8", { fatal: false }),
  };
  if (server.upgrade(req, { data })) return undefined;
  return Response.json({ error: "websocket upgrade required" }, { status: 426 });
}

/// The handlers Bun.serve mounts under `websocket:`. Every socket this daemon accepts is a pty
/// attach, so there is no per-route dispatch here.
export function ptyWebSocket(opts: PtyOpts) {
  return {
    open(ws: any) {
      const c = ws.data as Conn;
      const encoder = new TextEncoder();
      const term = new Bun.Terminal({
        cols: c.cols,
        rows: c.rows,
        data(_t: unknown, chunk: Uint8Array) {
          // Same rule as /output and the bridge: nothing leaves this machine unredacted. The
          // stream is decoded so a multi-byte glyph split across chunks survives, and only
          // re-encoded when something was actually replaced.
          const text = c.decoder.decode(chunk, { stream: true });
          const r = redact(text);
          if (r.findings.length) {
            record(r.findings as Finding[], "bridge", PTY_DEDUPE_MS).catch(() => {});
            ws.sendBinary(encoder.encode(r.text));
          } else {
            ws.sendBinary(chunk);
          }
        },
      });
      c.term = term;
      // A pane target focuses that window/pane first; the attach that follows shows it.
      if (c.pane) {
        Bun.spawnSync([...argv(opts), "select-window", "-t", c.pane]);
        Bun.spawnSync([...argv(opts), "select-pane", "-t", c.pane]);
      }
      try {
        c.proc = Bun.spawn([...argv(opts), "attach-session", "-t", c.name], {
          terminal: term,
          env: { ...process.env, TERM: "xterm-256color", COLORTERM: "truecolor", LANG: process.env.LANG ?? "en_US.UTF-8" },
          onExit(_p: unknown, code: number | null) {
            try { ws.send(JSON.stringify({ t: "exit", code })); ws.close(); } catch {}
          },
        });
      } catch (e: any) {
        ws.send(JSON.stringify({ t: "error", msg: String(e?.message ?? e) }));
        ws.close();
      }
    },
    message(ws: any, message: string | Buffer | Uint8Array) {
      const c = ws.data as Conn;
      if (typeof message === "string") {
        let msg: any;
        try { msg = JSON.parse(message); } catch { return; }
        if (msg?.t === "ping") ws.send(JSON.stringify({ t: "pong" }));
        else if (msg?.t === "resize" && c.term && c.proc) {
          c.cols = clamp(Number(msg.cols), 20, 400, c.cols);
          c.rows = clamp(Number(msg.rows), 5, 200, c.rows);
          c.term.resize(c.cols, c.rows);
          // Bun sets the new window size on the pty but the mux only re-reads it on
          // SIGWINCH — measured on bun 1.3.14: resize alone left tmux at the old size.
          c.proc.kill("SIGWINCH");
        }
        return;
      }
      c.term?.write(message);
    },
    close(ws: any) {
      const c = ws.data as Conn;
      // Detach: the mux keeps the session; only this client's attach ends.
      try { c.proc?.kill(); } catch {}
      try { c.term?.close(); } catch {}
    },
  };
}

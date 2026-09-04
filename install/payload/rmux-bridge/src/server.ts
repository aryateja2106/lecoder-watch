import { unlink } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { timingSafeEqual } from "node:crypto";
import { join } from "node:path";
import { homedir, tmpdir } from "node:os";
// Redaction lives in meshd's tree; ../../meshd resolves in the repo (install/payload/)
// and in the installed layout (~/.mesh/) alike, so the bridge stays a sibling that
// needs nothing but bun.
import { createLineRedactor, type Finding } from "../../meshd/redact";

type WsData = { session: string; pane?: string };

// What to attach/stream/send to: a specific pane id (e.g. "%2") if given,
// else the whole session. tmux/rmux accept a pane id directly as a -t target.
function wsTarget(data: WsData): string {
  return data.pane && data.pane.length > 0 ? data.pane : data.session;
}

type InputMessage = { type: "input"; data: string };
type ResizeMessage = { type: "resize"; cols: number; rows: number };
type SplitMessage = { type: "split"; dir: "h" | "v" };
type NewPaneMessage = { type: "new-pane" };
type ClientMessage = InputMessage | ResizeMessage | SplitMessage | NewPaneMessage;

type SessionRuntime = {
  clients: Set<ServerWebSocket<WsData>>;
  // Streamed output is redacted a line at a time: bytes after the last newline wait
  // here until the newline arrives or 40 ms pass, so a token split across two PTY
  // reads is still seen whole.
  pending: string;
  decoder: TextDecoder;
  redactLine: (line: string) => { text: string; findings: Finding[] };
  flushTimer: ReturnType<typeof setTimeout> | null;
  listener: ReturnType<typeof Bun.listen> | null;
  socketPath: string | null;
  ensuring: Promise<void> | null;
  tearingDown: Promise<void> | null;
};

const port = Number.parseInt(process.env.PORT ?? "7820", 10);
// Bind the tailnet by default (parity with meshd). The tailnet (WireGuard) is the
// trust boundary; override with BRIDGE_HOST=127.0.0.1 to restrict to localhost.
const host = process.env.BRIDGE_HOST ?? "0.0.0.0";
// Self-contained: xterm assets are vendored under public/vendor so the bridge
// runs anywhere with just bun (no repo node_modules needed).
const indexFile = Bun.file(new URL("../public/index.html", import.meta.url));
const xtermCssFile = Bun.file(new URL("../public/vendor/xterm.css", import.meta.url));
const xtermJsFile = Bun.file(new URL("../public/vendor/xterm.js", import.meta.url));
const fitAddonFile = Bun.file(new URL("../public/vendor/addon-fit.js", import.meta.url));
const sessions = new Map<string, SessionRuntime>();
const textDecoder = new TextDecoder();

function getRuntime(session: string): SessionRuntime {
  const existing = sessions.get(session);
  if (existing) {
    return existing;
  }
  const created: SessionRuntime = {
    clients: new Set(),
    pending: "",
    decoder: new TextDecoder("utf-8"),
    redactLine: createLineRedactor(),
    flushTimer: null,
    listener: null,
    socketPath: null,
    ensuring: null,
    tearingDown: null,
  };
  sessions.set(session, created);
  return created;
}

// Multiplexer binary: rmux on macOS, tmux on Linux (rmux is a tmux-compatible fork,
// so every command below is identical). Override with MUX=<binary>.
const MUX = process.env.MUX ?? (process.platform === "linux" ? "tmux" : "rmux");

async function runRmux(args: string[]): Promise<{ code: number; stdout: string; stderr: string }> {
  const proc = Bun.spawn([MUX, ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  if (code !== 0) {
    console.error(`[rmux] ${args.join(" ")} failed: ${stderr.trim() || "(no stderr)"}`);
  }
  return { code, stdout, stderr };
}

function sanitizeSession(session: string): string {
  const sanitized = session.replace(/[^a-zA-Z0-9._-]+/g, "-");
  return sanitized || "session";
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

async function unlinkIfPresent(path: string): Promise<void> {
  try {
    await unlink(path);
  } catch (error) {
    if (!(error instanceof Error) || !("code" in error) || error.code !== "ENOENT") {
      throw error;
    }
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function decodeWsText(message: string | ArrayBuffer | Uint8Array): string | null {
  if (typeof message === "string") {
    return message;
  }
  if (message instanceof ArrayBuffer) {
    return textDecoder.decode(new Uint8Array(message));
  }
  if (message instanceof Uint8Array) {
    return textDecoder.decode(message);
  }
  return null;
}

function parseClientMessage(message: string | ArrayBuffer | Uint8Array): ClientMessage | null {
  const text = decodeWsText(message);
  if (text === null) {
    return null;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isRecord(parsed) || typeof parsed.type !== "string") {
    return null;
  }
  if (parsed.type === "input" && typeof parsed.data === "string") {
    return { type: "input", data: parsed.data };
  }
  if (
    parsed.type === "resize" &&
    typeof parsed.cols === "number" &&
    Number.isFinite(parsed.cols) &&
    typeof parsed.rows === "number" &&
    Number.isFinite(parsed.rows)
  ) {
    return {
      type: "resize",
      cols: Math.max(1, Math.floor(parsed.cols)),
      rows: Math.max(1, Math.floor(parsed.rows)),
    };
  }
  if (parsed.type === "split" && (parsed.dir === "h" || parsed.dir === "v")) {
    return { type: "split", dir: parsed.dir };
  }
  if (parsed.type === "new-pane") {
    return { type: "new-pane" };
  }
  return null;
}

// rmux/tmux `send-keys -H` expects each hex byte as its own argv element,
// not a single space-joined string. Return the bytes so the caller can spread them.
function toHexBytes(input: string): string[] {
  const bytes = new TextEncoder().encode(input);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0"));
}

let server: ReturnType<typeof Bun.serve<WsData>>;

// ---------- auth ----------
// This process can type into any tmux/rmux session on the machine, so it is gated like
// meshd: the same bearer token, exact and constant-time, and a peer on loopback (the
// Mac's own browser, the CLI) is trusted. Browsers cannot put a header on a WebSocket
// upgrade, so the token may also arrive as the `mesh_token` cookie the phone app sets
// for this origin. Never from the URL. Fail closed: no token configured → nothing but
// loopback gets in.
function readToken(): string {
  const fromEnv = process.env.MESHD_TOKEN?.trim();
  if (fromEnv) return fromEnv;
  try {
    return readFileSync(join(process.env.MESH_HOME ?? join(homedir(), ".mesh"), "token"), "utf8").trim();
  } catch {
    return "";
  }
}
const TOKEN = readToken();
// Set BRIDGE_TRUST_LOOPBACK=0 when a reverse proxy on this host fronts the bridge (the
// proxy's peers would otherwise all look local). The self-check uses it too.
const TRUST_LOOPBACK = process.env.BRIDGE_TRUST_LOOPBACK !== "0";
const MESHD_URL = `http://127.0.0.1:${process.env.MESHD_PORT ?? "8899"}`;

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a, "utf8");
  const bb = Buffer.from(b, "utf8");
  if (ab.length !== bb.length) return false;
  return timingSafeEqual(ab, bb);
}

function cookieValue(header: string | null, name: string): string {
  if (!header) return "";
  for (const part of header.split(";")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    if (part.slice(0, eq).trim() === name) return decodeURIComponent(part.slice(eq + 1).trim());
  }
  return "";
}

function authorized(req: Request): boolean {
  if (TRUST_LOOPBACK) {
    const ip = server.requestIP(req)?.address ?? "";
    if (ip === "127.0.0.1" || ip === "::1" || ip === "::ffff:127.0.0.1") return true;
  }
  if (!TOKEN) return false;
  const auth = req.headers.get("authorization") ?? "";
  if (auth.startsWith("Bearer ") && safeEqual(auth.slice("Bearer ".length), TOKEN)) return true;
  const cookie = cookieValue(req.headers.get("cookie"), "mesh_token");
  return Boolean(cookie) && safeEqual(cookie, TOKEN);
}

// ---------- redacted fan-out ----------
// Findings go to meshd, which owns the exposure ledger; the same fingerprint is
// reported at most once per ten minutes from here so a key left on screen is one
// exposure, not one per redraw.
const reported = new Map<string, number>();
function report(findings: Finding[]): void {
  const now = Date.now();
  const fresh = findings.filter((f) => {
    const seen = reported.get(f.fp);
    if (seen !== undefined && now - seen < 10 * 60_000) return false;
    reported.set(f.fp, now);
    return true;
  });
  if (!fresh.length) return;
  fetch(`${MESHD_URL}/exposures/record`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ channel: "bridge", findings: fresh }),
  }).catch(() => {});
}

const textEncoder = new TextEncoder();
function publishRedacted(session: string, runtime: SessionRuntime, text: string): void {
  if (!text) return;
  const findings: Finding[] = [];
  // Terminal lines end in \r\n; keep every terminator exactly as the PTY sent it.
  const out = text.split(/(?<=\n)/).map((line) => {
    const r = runtime.redactLine(line.replace(/\r?\n$/, ""));
    findings.push(...r.findings);
    const end = line.endsWith("\r\n") ? "\r\n" : line.endsWith("\n") ? "\n" : "";
    return r.text + end;
  }).join("");
  if (findings.length) report(findings);
  server.publish(session, textEncoder.encode(out));
}

/// Redact the whole snapshot a fresh client receives; it is complete lines already.
function redactSnapshot(runtime: SessionRuntime, text: string): string {
  const findings: Finding[] = [];
  const out = text.split("\n").map((line) => { const r = runtime.redactLine(line); findings.push(...r.findings); return r.text; }).join("\n");
  if (findings.length) report(findings);
  return out;
}

// Pane output and WS traffic stay unbounded on purpose to preserve terminal semantics;
// the only buffering is the partial last line held for redaction (≤ 40 ms).
function fanout(session: string, data: Uint8Array): void {
  const runtime = getRuntime(session);
  runtime.pending += runtime.decoder.decode(data, { stream: true });
  const cut = runtime.pending.lastIndexOf("\n");
  if (cut >= 0) {
    publishRedacted(session, runtime, runtime.pending.slice(0, cut + 1));
    runtime.pending = runtime.pending.slice(cut + 1);
  }
  if (runtime.flushTimer) clearTimeout(runtime.flushTimer);
  if (runtime.pending) {
    runtime.flushTimer = setTimeout(() => {
      runtime.flushTimer = null;
      const tail = runtime.pending;
      runtime.pending = "";
      publishRedacted(session, runtime, tail);
    }, 40);
  }
}

async function ensureSession(session: string): Promise<void> {
  const runtime = getRuntime(session);
  if (runtime.listener) {
    return;
  }
  if (runtime.ensuring) {
    await runtime.ensuring;
    return;
  }
  runtime.ensuring = (async () => {
    const socketPath = join(tmpdir(), `rmux-bridge-${sanitizeSession(session)}-${process.pid}.sock`);
    await unlinkIfPresent(socketPath);
    const listener = Bun.listen({
      unix: socketPath,
      socket: {
        data(_socket, buffer) {
          fanout(session, buffer);
        },
      },
    });
    runtime.listener = listener;
    runtime.socketPath = socketPath;
    const command = `nc -U ${shellQuote(socketPath)}`;
    const piped = await runRmux(["pipe-pane", "-O", "-t", session, command]);
    if (piped.code !== 0) {
      listener.stop(true);
      runtime.listener = null;
      runtime.socketPath = null;
      await unlinkIfPresent(socketPath);
      throw new Error(`failed to attach pane pipe for ${session}`);
    }
  })();
  try {
    await runtime.ensuring;
  } finally {
    runtime.ensuring = null;
  }
}

async function teardownSession(session: string): Promise<void> {
  const runtime = sessions.get(session);
  if (!runtime) {
    return;
  }
  if (runtime.clients.size > 0) {
    return;
  }
  if (runtime.tearingDown) {
    await runtime.tearingDown;
    return;
  }
  runtime.tearingDown = (async () => {
    await runRmux(["pipe-pane", "-t", session]);
    runtime.listener?.stop(true);
    runtime.listener = null;
    if (runtime.socketPath) {
      await unlinkIfPresent(runtime.socketPath);
      runtime.socketPath = null;
    }
    if (runtime.clients.size === 0) {
      sessions.delete(session);
    }
  })();
  try {
    await runtime.tearingDown;
  } finally {
    runtime.tearingDown = null;
  }
}

async function handleOpen(ws: ServerWebSocket<WsData>): Promise<void> {
  const session = ws.data.session;
  const target = wsTarget(ws.data);
  const exists = await runRmux(["has-session", "-t", session]);
  if (exists.code !== 0) {
    ws.close(1008, "no such session");
    return;
  }
  const snapshot = await runRmux(["capture-pane", "-p", "-e", "-t", target]);
  if (snapshot.code !== 0) {
    ws.close(1011, "snapshot failed");
    return;
  }
  ws.send(redactSnapshot(getRuntime(target), snapshot.stdout));
  try {
    await ensureSession(target);
  } catch (error) {
    console.error(error);
    ws.close(1011, "attach failed");
    return;
  }
  ws.subscribe(target);
  getRuntime(target).clients.add(ws);
}

async function handleMessage(
  ws: ServerWebSocket<WsData>,
  message: string | ArrayBuffer | Uint8Array,
): Promise<void> {
  const parsed = parseClientMessage(message);
  if (!parsed) {
    return;
  }
  const session = ws.data.session;
  const target = wsTarget(ws.data);
  if (parsed.type === "input") {
    const hexBytes = toHexBytes(parsed.data);
    if (hexBytes.length === 0) {
      return;
    }
    await runRmux(["send-keys", "-t", target, "-H", "--", ...hexBytes]);
    return;
  }
  if (parsed.type === "resize") {
    // Resize the window (panes share the window geometry).
    await runRmux(["resize-window", "-t", session, "-x", String(parsed.cols), "-y", String(parsed.rows)]);
    return;
  }
  if (parsed.type === "split") {
    const flag = parsed.dir === "h" ? "-h" : "-v";
    await runRmux(["split-window", flag, "-t", target]);
    return;
  }
  await runRmux(["split-window", "-t", target]);
}

function serveStatic(file: Bun.BunFile, contentType: string): Response {
  return new Response(file, {
    headers: {
      "content-type": contentType,
      "cache-control": "no-store",
    },
  });
}

server = Bun.serve<WsData>({
  port,
  hostname: host,
  fetch(req) {
    const url = new URL(req.url);
    if (req.method !== "GET") {
      return new Response("Method Not Allowed", { status: 405 });
    }
    if (url.pathname === "/health") {
      return new Response(JSON.stringify({ ok: true, auth: TOKEN ? "token" : "loopback-only" }), { headers: { "content-type": "application/json" } });
    }
    // Everything else — the page, its assets, and above all /attach — needs the token.
    if (!authorized(req)) {
      return new Response("Unauthorized: pair the phone app, or open this page on the Mac itself", { status: 401 });
    }
    if (url.pathname === "/") {
      return serveStatic(indexFile, "text/html; charset=utf-8");
    }
    if (url.pathname === "/xterm/xterm.css") {
      return serveStatic(xtermCssFile, "text/css; charset=utf-8");
    }
    if (url.pathname === "/xterm/xterm.js") {
      return serveStatic(xtermJsFile, "application/javascript; charset=utf-8");
    }
    if (url.pathname === "/xterm/addon-fit.js") {
      return serveStatic(fitAddonFile, "application/javascript; charset=utf-8");
    }
    if (url.pathname === "/attach") {
      const session = url.searchParams.get("session") || "spine-test";
      const pane = url.searchParams.get("pane") || undefined;
      const upgraded = server.upgrade(req, {
        data: { session, pane },
      });
      return upgraded ? undefined : new Response("WebSocket upgrade failed", { status: 400 });
    }
    return new Response("Not Found", { status: 404 });
  },
  websocket: {
    open(ws) {
      void handleOpen(ws);
    },
    message(ws, message) {
      void handleMessage(ws, message);
    },
    close(ws) {
      const target = wsTarget(ws.data);
      ws.unsubscribe(target);
      const runtime = sessions.get(target);
      if (!runtime) {
        return;
      }
      runtime.clients.delete(ws);
      if (runtime.clients.size === 0) {
        void teardownSession(target);
      }
    },
  },
});

console.log(
  `rmux-bridge listening at http://${host}:${port}/  (attach: ws://${host}:${port}/attach?session=spine-test)`,
);

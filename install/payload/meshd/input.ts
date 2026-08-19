// Mac remote control for meshd — cursor, keyboard, scroll, clipboard, volume.
// macOS only: the watch/phone POST high-level input events, a long-lived Swift
// helper (bin/mesh-input) turns them into real HID events via Quartz.
//
//   GET  /input            -> { ok, trusted, helper, hint }   (?prompt=1 shows the TCC dialog)
//   POST /input            <- { events: [ {t:"move",dx,dy}, {t:"click"}, ... ] }
//   GET  /clipboard        -> { text }
//   POST /clipboard        <- { text }
//   POST /volume           <- { level } | { delta } | { muted }   (GET reads current)
//
// ponytail: its own module, not inlined into server.ts, because three meshd
// lineages (repo, payload, deployed) have drifted — this keeps the patch each of
// them needs down to an import plus one route line.
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { stat, mkdir } from "node:fs/promises";

const IS_MAC = process.platform === "darwin";
const MAX_EVENTS = 200;
const HELPER_BIN = join(homedir(), ".mesh", "bin", "mesh-input");
// Deployed layout is ~/.mesh/{meshd,bin}; a repo checkout is install/payload/{meshd,bin}.
const HELPER_SRC = [
  join(homedir(), ".mesh", "bin", "mesh-input.swift"),
  join(import.meta.dir, "..", "bin", "mesh-input.swift"),
];

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

async function run(cmd: string[], stdin?: string): Promise<string> {
  const p = Bun.spawn(cmd, { stdin: stdin === undefined ? "ignore" : "pipe", stdout: "pipe", stderr: "ignore" });
  if (stdin !== undefined) { p.stdin.write(stdin); p.stdin.end(); }
  const out = await new Response(p.stdout).text();
  await p.exited;
  return out;
}

// ---------- helper lifecycle ----------
let buildError = "";
let ensuring: Promise<string | null> | null = null;
let helper: ReturnType<typeof Bun.spawn> | null = null;

async function buildHelper(): Promise<string | null> {
  let src: string | null = null;
  for (const candidate of HELPER_SRC) {
    if (await Bun.file(candidate).exists()) { src = candidate; break; }
  }
  if (!src) { buildError = "mesh-input.swift not found (reinstall the mesh payload)"; return null; }

  const [bin, source] = await Promise.all([stat(HELPER_BIN).catch(() => null), stat(src)]);
  if (bin && bin.mtimeMs >= source.mtimeMs) return HELPER_BIN;

  await mkdir(dirname(HELPER_BIN), { recursive: true });
  const build = Bun.spawn(["/usr/bin/swiftc", "-O", "-o", HELPER_BIN, src], { stdout: "ignore", stderr: "pipe" });
  if ((await build.exited) !== 0) {
    buildError = (await new Response(build.stderr).text()).trim().slice(0, 400) || "swiftc failed";
    return null;
  }
  buildError = "";
  return HELPER_BIN;
}

function ensureHelper(): Promise<string | null> {
  if (!ensuring) {
    ensuring = buildHelper();
    // Let a later request retry once the user fixes swiftc / reinstalls the payload.
    ensuring.then((path) => { if (!path) ensuring = null; });
  }
  return ensuring;
}

// macOS decides a process's Accessibility trust when it starts, so a helper spawned
// before the user granted permission stays deaf forever. Remember what it was born
// with and recycle it the moment a status check sees the grant land.
let helperWasTrusted = false;

async function stream(trusted: boolean): Promise<any> {
  if (helper && helper.exitCode === null && helperWasTrusted === trusted) return helper;
  if (helper && helper.exitCode === null) helper.kill();
  const bin = await ensureHelper();
  if (!bin) return null;
  helper = Bun.spawn([bin], { stdin: "pipe", stdout: "ignore", stderr: "ignore" });
  helperWasTrusted = trusted;
  return helper;
}

/// Cached so the injection path never pays a process spawn per request; only a
/// status check (which the watch runs on open, and after "Ask the Mac now") moves it.
let trustedCache = false;

// ---------- actions ----------
export async function injectEvents(events: any[]): Promise<{ ok: boolean; count?: number; error?: string }> {
  if (!IS_MAC) return { ok: false, error: "input injection is macOS only" };
  if (!Array.isArray(events) || events.length === 0) return { ok: false, error: "events required" };
  const batch = events.slice(0, MAX_EVENTS).filter((e) => e && typeof e.t === "string");
  if (batch.length === 0) return { ok: false, error: "no valid events" };
  const proc = await stream(trustedCache);
  if (!proc) return { ok: false, error: buildError || "mesh-input unavailable" };
  proc.stdin.write(batch.map((e) => JSON.stringify(e)).join("\n") + "\n");
  proc.stdin.flush();
  return { ok: true, count: batch.length };
}

export async function inputStatus(prompt = false) {
  if (!IS_MAC) return { ok: false, trusted: false, error: "input injection is macOS only" };
  const bin = await ensureHelper();
  if (!bin) return { ok: false, trusted: false, helper: HELPER_BIN, error: buildError };
  const out = await run(prompt ? [bin, "--check", "--prompt"] : [bin, "--check"]);
  const trusted = /"trusted"\s*:\s*true/.test(out);
  trustedCache = trusted;
  return {
    ok: true,
    trusted,
    helper: HELPER_BIN,
    // Quartz silently drops every event until this binary is trusted — say so plainly.
    hint: trusted ? undefined : `Add ${HELPER_BIN} to System Settings › Privacy & Security › Accessibility`,
  };
}

async function volume(body: any) {
  if (!IS_MAC) return { ok: false, error: "volume control is macOS only" };
  const read = async () => ({
    level: Math.round(Number(await run(["/usr/bin/osascript", "-e", "output volume of (get volume settings)"])) || 0),
    muted: (await run(["/usr/bin/osascript", "-e", "output muted of (get volume settings)"])).trim() === "true",
  });

  const current = await read();
  const script: string[] = [];
  if (typeof body?.muted === "boolean") script.push(`set volume output muted ${body.muted}`);
  const target = typeof body?.level === "number" ? body.level
    : typeof body?.delta === "number" ? current.level + body.delta
      : null;
  if (target !== null) {
    script.push(`set volume output volume ${Math.round(Math.min(100, Math.max(0, target)))}`);
    if (typeof body?.muted !== "boolean") script.push("set volume output muted false");
  }
  if (script.length === 0) return { ok: true, ...current };
  await run(["/usr/bin/osascript", ...script.flatMap((s) => ["-e", s])]);
  return { ok: true, ...(await read()) };
}

// ---------- routing ----------
/// Returns a Response for the routes this module owns, or null so server.ts keeps matching.
export async function handleInput(req: Request, url: URL): Promise<Response | null> {
  const path = url.pathname;

  if (path === "/input" && req.method === "GET") {
    return json(await inputStatus(url.searchParams.get("prompt") === "1"));
  }
  if (path === "/input" && req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    const events = Array.isArray(body) ? body : Array.isArray(body?.events) ? body.events : body?.t ? [body] : [];
    const result = await injectEvents(events);
    return json(result, result.ok ? 200 : 400);
  }
  if (path === "/clipboard" && req.method === "GET") {
    if (!IS_MAC) return json({ error: "clipboard is macOS only" }, 404);
    return json({ text: await run(["/usr/bin/pbpaste"]) });
  }
  if (path === "/clipboard" && req.method === "POST") {
    if (!IS_MAC) return json({ error: "clipboard is macOS only" }, 404);
    const body = await req.json().catch(() => ({}));
    if (typeof body?.text !== "string") return json({ error: "text required" }, 400);
    await run(["/usr/bin/pbcopy"], body.text);
    return json({ ok: true });
  }
  if (path === "/volume" && (req.method === "POST" || req.method === "GET")) {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const result = await volume(body);
    return json(result, result.ok ? 200 : 404);
  }
  return null;
}

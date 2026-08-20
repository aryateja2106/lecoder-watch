// Mac remote control for meshd — cursor, keyboard, scroll, clipboard, volume.
// macOS only: the watch/phone POST high-level input events, a long-lived Swift
// helper (bin/mesh-input) turns them into real HID events via Quartz.
//
//   GET  /input            -> { ok, trusted, helper, hint }   (?prompt=1 shows the TCC dialog)
//   POST /input            <- { events: [ {t:"move",dx,dy}, {t:"click"}, ... ] }
//   GET  /clipboard        -> { text }
//   POST /clipboard        <- { text }
//   POST /volume           <- { level } | { delta } | { muted }   (GET reads current)
//   POST /system           <- { action: "displaysleep" | "lock" | "screensaver" | "sleep" }
//   GET  /apps             -> { front, running: [{name,bundleID,front}], installed: [name] }
//   POST /apps             <- { activate: "Safari" }
//   GET  /displays         -> { displays: [{index,id,x,y,width,height,main,name}] }
//   GET  /screen.jpg?display=2[&width=1400]  capture one display (no display: server.ts)
//   GET  /desktop?token=…   remote desktop page (polls /screen.jpg, posts /input)
//
// ponytail: its own module, not inlined into server.ts, because three meshd
// lineages (repo, payload, deployed) have drifted — this keeps the patch each of
// them needs down to an import plus one route line.
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { stat, mkdir, readFile, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import {
  linuxInjectEvents, linuxInputStatus, linuxClipboard, linuxVolume, linuxSystemAction,
} from "./input-linux";

const IS_MAC = process.platform === "darwin";
const MAX_EVENTS = 200;
const HELPER_BIN = join(homedir(), ".mesh", "bin", "mesh-input");
// Deployed layout is ~/.mesh/{meshd,bin}; a repo checkout is install/payload/{meshd,bin}.
// Co-located source first: a meshd run straight from a checkout must build ITS helper,
// not silently keep using whatever was deployed last. Both paths are the same file
// once installed.
const HELPER_SRC = [
  join(import.meta.dir, "..", "bin", "mesh-input.swift"),
  join(homedir(), ".mesh", "bin", "mesh-input.swift"),
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
  if (!Array.isArray(events) || events.length === 0) return { ok: false, error: "events required" };
  const batch = events.slice(0, MAX_EVENTS).filter((e) => e && typeof e.t === "string");
  if (batch.length === 0) return { ok: false, error: "no valid events" };
  if (!IS_MAC) return linuxInjectEvents(batch);
  const proc = await stream(trustedCache);
  if (!proc) return { ok: false, error: buildError || "mesh-input unavailable" };
  proc.stdin.write(batch.map((e) => JSON.stringify(e)).join("\n") + "\n");
  proc.stdin.flush();
  return { ok: true, count: batch.length };
}

export async function inputStatus(prompt = false) {
  if (!IS_MAC) return linuxInputStatus();
  const bin = await ensureHelper();
  if (!bin) return { ok: false, trusted: false, helper: HELPER_BIN, error: buildError };
  const out = await run(prompt ? [bin, "--check", "--prompt"] : [bin, "--check"]);
  const trusted = /"trusted"\s*:\s*true/.test(out);
  const screen = /"screen"\s*:\s*true/.test(out);
  trustedCache = trusted;
  return {
    ok: true,
    trusted,
    screen,
    helper: HELPER_BIN,
    // Quartz silently drops every event until this binary is trusted — say so plainly.
    hint: trusted ? undefined : `Add ${HELPER_BIN} to System Settings › Privacy & Security › Accessibility`,
    screenHint: screen ? undefined : "Allow Screen Recording in System Settings › Privacy & Security, or screenshots show only the wallpaper",
  };
}

async function volume(body: any) {
  if (!IS_MAC) return linuxVolume(body);
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

/// Power/session actions that have no HID equivalent. Allowlisted by name — the
/// watch never gets to name a command. Deliberately no restart/shutdown: those kill
/// every running agent session, and a wrist tap is too cheap for that.
const SYSTEM_ACTIONS: Record<string, string[]> = {
  displaysleep: ["/usr/bin/pmset", "displaysleepnow"],
  sleep: ["/usr/bin/pmset", "sleepnow"],
  lock: ["/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", "-suspend"],
  screensaver: ["/usr/bin/open", "-a", "ScreenSaverEngine"],
};

async function systemAction(action: string) {
  if (!IS_MAC) return linuxSystemAction(action);
  const cmd = SYSTEM_ACTIONS[action];
  if (!cmd) return { ok: false, error: `unknown action: ${action}` };
  await run(cmd);
  return { ok: true, action };
}

// lsappinfo, not AppleScript: `tell application "System Events"` would make meshd
// ask for Automation permission on top of Accessibility, and the watch only needs
// names. One shell pass so a dozen apps cost one spawn, not a dozen.
const RUNNING_APPS_SH =
  `/usr/bin/lsappinfo visibleProcessList | tr ' ' '\\n' | sed 's/:$//' | ` +
  `while read -r a; do [ -n "$a" ] && /usr/bin/lsappinfo info -only name,bundleID "$a" 2>/dev/null | tr '\\n' ' ' && echo; done`;
const INSTALLED_APPS_SH =
  `ls -1 /Applications /Applications/Utilities /System/Applications /System/Applications/Utilities ` +
  `"$HOME/Applications" 2>/dev/null | sed -n 's/\\.app$//p' | sort -u`;

async function listApps() {
  if (!IS_MAC) return { ok: false, error: "app control is macOS only" };
  const [rawRunning, rawFront, rawInstalled] = await Promise.all([
    run(["/bin/sh", "-c", RUNNING_APPS_SH]),
    run(["/bin/sh", "-c", `/usr/bin/lsappinfo info -only name "$(/usr/bin/lsappinfo front)" 2>/dev/null`]),
    run(["/bin/sh", "-c", INSTALLED_APPS_SH]),
  ]);
  const front = rawFront.match(/"name"="([^"]+)"/)?.[1] ?? rawFront.match(/^"([^"]+)"/)?.[1];
  const running = rawRunning.split("\n").flatMap((line) => {
    const m = line.match(/^"([^"]+)".*?bundleID="([^"]+)"/);
    return m ? [{ name: m[1], bundleID: m[2], front: m[1] === front }] : [];
  });
  const installed = rawInstalled.split("\n").map((x) => x.trim()).filter(Boolean);
  return { ok: true, front, running, installed };
}

/// `open -a` via argv, never a shell string — the name comes from the watch.
async function activateApp(name: string) {
  if (!IS_MAC) return { ok: false, error: "app control is macOS only" };
  if (!name.trim()) return { ok: false, error: "app name required" };
  const p = Bun.spawn(["/usr/bin/open", "-a", name], { stdout: "ignore", stderr: "pipe" });
  if ((await p.exited) !== 0) {
    return { ok: false, error: (await new Response(p.stderr).text()).trim().slice(0, 200) || "could not open" };
  }
  return { ok: true, activated: name };
}

async function listDisplays() {
  if (!IS_MAC) return { ok: false, error: "displays are macOS only" };
  const bin = await ensureHelper();
  if (!bin) return { ok: false, error: buildError || "mesh-input unavailable" };
  const out = await run([bin, "--displays"]);
  try {
    return JSON.parse(out);
  } catch {
    return { ok: false, error: out.trim().slice(0, 200) || "could not read displays" };
  }
}

/// screencapture -D is 1-based with 1 = main, the same order mesh-input reports, so a
/// preview and a moveTo on the watch agree about which screen "2" is.
async function captureDisplay(index: number, width = 480): Promise<Response> {
  const path = join(tmpdir(), `meshd-display-${index}-${process.pid}.jpg`);
  try {
    const shot = Bun.spawn(["/usr/sbin/screencapture", "-x", "-D", String(index), "-t", "jpg", path],
      { stdout: "ignore", stderr: "ignore" });
    if ((await shot.exited) !== 0) return json({ error: "screenshot unavailable" }, 503);
    const scale = Bun.spawn(["/usr/bin/sips", "-Z", String(width), path], { stdout: "ignore", stderr: "ignore" });
    await scale.exited;
    return new Response(await readFile(path), {
      headers: { "content-type": "image/jpeg", "cache-control": "no-store" },
    });
  } finally {
    unlink(path).catch(() => {});
  }
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
    if (!IS_MAC) { const r = await linuxClipboard(); return json(r, r.ok ? 200 : 404); }
    return json({ text: await run(["/usr/bin/pbpaste"]) });
  }
  if (path === "/clipboard" && req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    if (typeof body?.text !== "string") return json({ error: "text required" }, 400);
    if (!IS_MAC) { const r = await linuxClipboard(body.text); return json(r, r.ok ? 200 : 404); }
    await run(["/usr/bin/pbcopy"], body.text);
    return json({ ok: true });
  }
  // A remote desktop assembled from capture + injection: no VNC server, no
  // websockify, no Screen Sharing toggle, same bearer token as everything else.
  if (path === "/desktop" && req.method === "GET") {
    const page = Bun.file(join(import.meta.dir, "desktop.html"));
    if (!(await page.exists())) return json({ error: "desktop.html missing" }, 404);
    return new Response(page, { headers: { "content-type": "text/html; charset=utf-8" } });
  }
  if (path === "/displays" && req.method === "GET") {
    const result = await listDisplays();
    return json(result, result.ok ? 200 : 404);
  }
  // Only claim /screen.jpg when a display is named; the plain route stays in server.ts.
  if (path === "/screen.jpg" && req.method === "GET" && url.searchParams.has("display")) {
    if (!IS_MAC) return json({ error: "screen peek is macOS only" }, 404);
    const index = Number(url.searchParams.get("display"));
    if (!Number.isInteger(index) || index < 1) return json({ error: "bad display" }, 400);
    // Wider captures for reading UI, not just "did my click land"; capped so a watch
    // can never ask for a 6MB frame.
    const width = Math.min(2000, Math.max(240, Number(url.searchParams.get("width") ?? "480") || 480));
    return await captureDisplay(index, width);
  }
  if (path === "/apps" && req.method === "GET") {
    const result = await listApps();
    return json(result, result.ok ? 200 : 404);
  }
  if (path === "/apps" && req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    const result = await activateApp(String(body?.activate ?? ""));
    return json(result, result.ok ? 200 : 400);
  }
  if (path === "/system" && req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    const result = await systemAction(String(body?.action ?? ""));
    return json(result, result.ok ? 200 : 400);
  }
  if (path === "/volume" && (req.method === "POST" || req.method === "GET")) {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const result = await volume(body);
    return json(result, result.ok ? 200 : 404);
  }
  return null;
}

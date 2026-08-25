// Mac remote control for meshd — cursor, keyboard, scroll, clipboard, volume.
// macOS only: the watch/phone POST high-level input events, a long-lived Swift
// helper (bin/mesh-input) turns them into real HID events via Quartz.
//
//   GET  /input            -> { ok, trusted, helper, hint }   (?prompt=1 shows the TCC dialog)
//   POST /input            <- { events: [ {t:"move",dx,dy}, {t:"click"}, ... ] }
//   GET  /clipboard        -> { text }
//   POST /clipboard        <- { text }
//   POST /volume           <- { level } | { delta } | { muted }   (GET reads current)
//   POST /system           <- { action: "displaysleep" | "lock" | "screensaver" | "sleep"
//                                       | "shutdown" | "restart" }
//                          -> { ok, action, exitCode, stderr } — truthful, never faked
//   POST /open             <- { url }   open an http/https URL in the default browser
//   GET  /apps             -> { front, running: [{name,bundleID,front}], installed: [name] }
//   POST /apps             <- { activate: "Safari" }
//   GET  /displays         -> { displays: [{index,id,x,y,width,height,main,name}] }
//   GET  /screen.jpg[?display=2][&width=1400][&x=&y=&w=&h=][&q=70]
//        Full display by default; x/y/w/h (normalized 0..1) crop a region at NATIVE
//        pixels (no downscale unless width is asked for); q re-encodes JPEG quality.
//        A served crop is announced via x-mesh-rect / x-mesh-display headers — their
//        absence means "full frame" (an old daemon, or a crop that could not be cut).
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

/// Like run(), but nothing is thrown away: exit code and stderr come back so the
/// caller can tell the client the truth. A missing binary is a result (127), not a
/// crash — Bun.spawn throws on ENOENT and a route must not 500 over it.
async function runChecked(cmd: string[], stdin?: string): Promise<{ out: string; stderr: string; code: number }> {
  try {
    const p = Bun.spawn(cmd, { stdin: stdin === undefined ? "ignore" : "pipe", stdout: "pipe", stderr: "pipe" });
    if (stdin !== undefined) { p.stdin.write(stdin); p.stdin.end(); }
    const [out, stderr] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text()]);
    return { out, stderr: stderr.trim(), code: await p.exited };
  } catch (e: any) {
    return { out: "", stderr: String(e?.message ?? e), code: 127 };
  }
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
/// watch never gets to name a command. shutdown/restart go through System Events
/// (graceful: apps with unsaved changes can veto, and the FIRST use raises a TCC
/// Automation consent dialog on the Mac's own screen — unattended it fails with
/// -1743, which now travels back verbatim instead of a fake ok). Clients are
/// expected to arm+confirm before sending either; /sbin/shutdown is deliberately
/// not used because it needs root and meshd runs as a user LaunchAgent.
const SYSTEM_ACTIONS: Record<string, string[]> = {
  displaysleep: ["/usr/bin/pmset", "displaysleepnow"],
  sleep: ["/usr/bin/pmset", "sleepnow"],
  lock: ["/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", "-suspend"],
  screensaver: ["/usr/bin/open", "-a", "ScreenSaverEngine"],
  shutdown: ["/usr/bin/osascript", "-e", 'tell app "System Events" to shut down'],
  restart: ["/usr/bin/osascript", "-e", 'tell app "System Events" to restart'],
};

/// Every action reports its real exit code and stderr. It used to answer ok:true
/// unconditionally, so a pmset that failed or an osascript that was denied rendered
/// as success on the wrist — the fire-and-forget helper was reused for actions whose
/// failure the user genuinely needs to see.
async function systemAction(action: string) {
  if (!IS_MAC) return linuxSystemAction(action);
  // hasOwn, not a bare lookup: "constructor" and "toString" are not actions, and
  // reaching them returns something confusing instead of "unknown action".
  const cmd = Object.hasOwn(SYSTEM_ACTIONS, action) ? SYSTEM_ACTIONS[action] : undefined;
  if (!cmd) return { ok: false, error: `unknown action: ${action}` };
  const r = await runChecked(cmd);
  return {
    ok: r.code === 0,
    action,
    exitCode: r.code,
    stderr: r.stderr,
    ...(r.code === 0 ? {} : { error: r.stderr.slice(0, 300) || `exit ${r.code}` }),
  };
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

// ---------- screen capture ----------
/// Normalized to the chosen display: x/y in [0,1) from its top-left, w/h fractions
/// of its size. Normalized because the client zooms a view, not pixels — it should
/// not need to know the display's resolution to ask for "the top-right quarter".
type CaptureRect = { x: number; y: number; w: number; h: number };

type CaptureParams = {
  display: number | null;
  width: number | null;      // null = the caller never asked; regions then stay native
  rect: CaptureRect | null;
  quality: number | null;
  error?: string;
};

/// One parser for both /screen.jpg routes so they cannot disagree about what a
/// width or a rect means. Unknown params are ignored (old clients, new daemons —
/// and the reverse: an old daemon ignores these same params and serves the full
/// frame, which is why the crop is announced in a response header).
export function parseCaptureParams(url: URL): CaptureParams {
  const sp = url.searchParams;
  const display = sp.has("display") ? Number(sp.get("display")) : null;
  // Same clamp the width has always had — wider for reading, capped so a watch can
  // never ask for a 6MB frame.
  const width = sp.has("width") ? Math.min(2000, Math.max(240, Number(sp.get("width")) || 480)) : null;
  let quality: number | null = null;
  if (sp.has("q")) {
    const n = Number(sp.get("q"));
    if (Number.isFinite(n)) quality = Math.min(100, Math.max(1, Math.round(n)));
  }
  let rect: CaptureRect | null = null;
  if (["x", "y", "w", "h"].some((k) => sp.has(k))) {
    const f = (k: string, d: number) => {
      const n = Number(sp.get(k) ?? d);
      return Number.isFinite(n) ? n : d;
    };
    const x = Math.min(0.99, Math.max(0, f("x", 0)));
    const y = Math.min(0.99, Math.max(0, f("y", 0)));
    const w = Math.min(1 - x, Math.max(0, f("w", 1)));
    const h = Math.min(1 - y, Math.max(0, f("h", 1)));
    // A sliver this thin is a client bug, and screencapture would happily return a
    // one-pixel ribbon that decodes fine and reads as "the screen is blank".
    if (w <= 0.01 || h <= 0.01) return { display, width, quality, rect: null, error: "region too small (w and h must exceed 0.01)" };
    rect = { x, y, w, h };
  }
  return { display, width, quality, rect };
}

/// The chosen display's global bounds in points (screencapture -R speaks global
/// point coordinates). Null when mesh-input cannot answer — no swiftc, no window
/// server — in which case the caller crops pixels out of a full frame instead.
async function displayPointBounds(index: number | null): Promise<{ index: number; x: number; y: number; width: number; height: number } | null> {
  const d: any = await listDisplays().catch(() => null);
  if (!d?.ok || !Array.isArray(d.displays) || d.displays.length === 0) return null;
  const pick = index != null
    ? d.displays.find((dd: any) => dd.index === index)
    : (d.displays.find((dd: any) => dd.main) ?? d.displays[0]);
  if (!pick || !(pick.width > 0) || !(pick.height > 0)) return null;
  return { index: Number(pick.index) || 1, x: Number(pick.x) || 0, y: Number(pick.y) || 0, width: Number(pick.width), height: Number(pick.height) };
}

async function imagePixelWidth(path: string): Promise<number> {
  const out = await run(["/usr/bin/sips", "-g", "pixelWidth", path]);
  return Number(out.match(/pixelWidth:\s*(\d+)/)?.[1] ?? 0);
}

/// screencapture -D is 1-based with 1 = main, the same order mesh-input reports, so a
/// preview and a moveTo on the watch agree about which screen "2" is.
///
/// A rect turns this into region capture at NATIVE resolution: screencapture -R takes
/// the region in global points and hands back native (2x on Retina) pixels, which is
/// the whole fix for "zoom magnifies detail the frame never carried" — the old path
/// always shot the entire display and downsampled it before the client ever zoomed.
/// The served crop is echoed in x-mesh-rect (normalized) + x-mesh-display; a response
/// without those headers is a full frame and the client must not interpret it as a crop.
export async function captureScreen(params: CaptureParams): Promise<Response> {
  if (!IS_MAC) return json({ error: "screen peek is macOS only" }, 404);
  const { display, rect, quality } = params;
  // Full frames keep their historical default (480) so old clients see identical
  // behavior; a region defaults to native pixels — downscaling is opt-in via width.
  const width = params.width ?? (rect ? null : 480);
  const path = join(tmpdir(), `meshd-screen-${display ?? "main"}-${process.pid}-${Date.now()}.jpg`);
  const headers: Record<string, string> = { "content-type": "image/jpeg", "cache-control": "no-store" };
  const fullShotArgs = display != null
    ? ["-x", "-D", String(display), "-t", "jpg", path]
    : ["-x", "-t", "jpg", path];
  try {
    let cropped = false;
    if (rect) {
      const bounds = await displayPointBounds(display);
      if (bounds) {
        const rx = Math.round(bounds.x + rect.x * bounds.width);
        const ry = Math.round(bounds.y + rect.y * bounds.height);
        const rw = Math.max(1, Math.round(rect.w * bounds.width));
        const rh = Math.max(1, Math.round(rect.h * bounds.height));
        const shot = Bun.spawn(["/usr/sbin/screencapture", "-x", "-R", `${rx},${ry},${rw},${rh}`, "-t", "jpg", path], { stdout: "ignore", stderr: "ignore" });
        if ((await shot.exited) === 0) {
          cropped = true;
          headers["x-mesh-display"] = String(bounds.index);
        }
      }
      if (!cropped) {
        // No display geometry (helper unavailable) — shoot the whole frame at native
        // pixels and cut the same normalized rect out in pixel space. Same result,
        // no point math needed. If even the cut fails, the full frame is served
        // WITHOUT the rect header: the honest old-daemon shape.
        const shot = Bun.spawn(["/usr/sbin/screencapture", ...fullShotArgs], { stdout: "ignore", stderr: "ignore" });
        if ((await shot.exited) !== 0) return json({ error: "screenshot unavailable" }, 503);
        const dims = await run(["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", path]);
        const pw = Number(dims.match(/pixelWidth:\s*(\d+)/)?.[1] ?? 0);
        const ph = Number(dims.match(/pixelHeight:\s*(\d+)/)?.[1] ?? 0);
        if (pw > 0 && ph > 0) {
          const cw = Math.max(1, Math.round(rect.w * pw));
          const ch = Math.max(1, Math.round(rect.h * ph));
          const oy = Math.round(rect.y * ph);
          const ox = Math.round(rect.x * pw);
          const cut = await runChecked(["/usr/bin/sips", "-c", String(ch), String(cw), "--cropOffset", String(oy), String(ox), path]);
          if (cut.code === 0) {
            cropped = true;
            if (display != null) headers["x-mesh-display"] = String(display);
          }
        }
      }
      if (cropped) headers["x-mesh-rect"] = `${rect.x},${rect.y},${rect.w},${rect.h}`;
    } else {
      const shot = Bun.spawn(["/usr/sbin/screencapture", ...fullShotArgs], { stdout: "ignore", stderr: "ignore" });
      if ((await shot.exited) !== 0) return json({ error: "screenshot unavailable" }, 503);
    }
    if (width != null) {
      // Never upscale a crop to meet the width — that would manufacture blur out of
      // the very pixels this path exists to preserve. Full frames keep the historic
      // unconditional resample.
      const scale = !cropped || (await imagePixelWidth(path)) > width;
      if (scale) await run(["/usr/bin/sips", "-Z", String(width), path]);
    }
    if (quality != null) {
      await run(["/usr/bin/sips", "-s", "format", "jpeg", "-s", "formatOptions", String(quality), path]);
    }
    return new Response(await readFile(path), { headers });
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
    const body = (await req.json().catch(() => ({}))) as any;
    const events = Array.isArray(body) ? body : Array.isArray(body?.events) ? body.events : body?.t ? [body] : [];
    const result = await injectEvents(events);
    return json(result, result.ok ? 200 : 400);
  }
  if (path === "/clipboard" && req.method === "GET") {
    if (!IS_MAC) { const r = await linuxClipboard(); return json(r, r.ok ? 200 : 404); }
    return json({ text: await run(["/usr/bin/pbpaste"]) });
  }
  if (path === "/clipboard" && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as any;
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
  // The whole capture route lives here now — with or without a display named — so
  // rect/width/quality mean exactly one thing. server.ts no longer carries its own copy.
  if (path === "/screen.jpg" && req.method === "GET") {
    if (!IS_MAC) return json({ error: "screen peek is macOS only" }, 404);
    const params = parseCaptureParams(url);
    if (params.error) return json({ error: params.error }, 400);
    if (params.display != null && (!Number.isInteger(params.display) || params.display < 1)) {
      return json({ error: "bad display" }, 400);
    }
    return await captureScreen(params);
  }
  // Open a URL in the machine's default browser — the wrist's whole "browser" is
  // open-then-watch-through-screen-peek. http/https only: this route must never
  // become a way to launch arbitrary handlers (file:, ssh:, x-apple-*, ...).
  if (path === "/open" && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as any;
    let target: URL;
    try { target = new URL(String(body?.url ?? "")); } catch { return json({ error: "invalid url" }, 400); }
    if (target.protocol !== "http:" && target.protocol !== "https:") {
      return json({ error: "only http/https urls can be opened" }, 400);
    }
    const r = await runChecked(IS_MAC ? ["/usr/bin/open", target.toString()] : ["xdg-open", target.toString()]);
    if (r.code !== 0) return json({ ok: false, error: r.stderr.slice(0, 300) || `exit ${r.code}` }, 502);
    return json({ ok: true, opened: target.toString() });
  }
  if (path === "/apps" && req.method === "GET") {
    const result = await listApps();
    return json(result, result.ok ? 200 : 404);
  }
  if (path === "/apps" && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as any;
    const result = await activateApp(String(body?.activate ?? ""));
    return json(result, result.ok ? 200 : 400);
  }
  if (path === "/system" && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as any;
    const result = await systemAction(String(body?.action ?? ""));
    return json(result, result.ok ? 200 : 400);
  }
  if (path === "/volume" && (req.method === "POST" || req.method === "GET")) {
    const body = req.method === "POST" ? (await req.json().catch(() => ({}))) as any : {};
    const result = await volume(body);
    return json(result, result.ok ? 200 : 404);
  }
  return null;
}

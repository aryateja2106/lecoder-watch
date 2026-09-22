// Linux input backend — same wire contract as the Mac helper, delivered with
// stock desktop tools instead of a compiled helper:
//   pointer/keys/text/scroll -> xdotool   (X11; covers Xvfb/VNC sessions too)
//   clipboard                -> xclip
//   volume                   -> pactl
//   lock / displaysleep      -> loginctl / xset
// ponytail: X11 only — Wayland needs ydotool+uinput; add a ydotool branch when a
// Wayland box actually joins the mesh. Windows/displays stay unsupported here; apps are
// the X client list (xprop), activated with xdotool.
import { existsSync } from "node:fs";
import { readFile, unlink } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const DISPLAY = process.env.MESH_DISPLAY ?? process.env.DISPLAY ?? ":0";
const XAUTHORITY = process.env.XAUTHORITY ?? [
  join(homedir(), ".Xauthority"),
  process.getuid?.() == null ? "" : `/run/user/${process.getuid()}/gdm/Xauthority`,
].find((path) => path && existsSync(path));
const ENV = { ...process.env, DISPLAY, ...(XAUTHORITY ? { XAUTHORITY } : {}) };

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

async function run(cmd: string[], stdin?: string): Promise<{ out: string; stderr: string; code: number }> {
  try {
    const p = Bun.spawn(cmd, {
      env: ENV,
      stdin: stdin === undefined ? "ignore" : "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });
    if (stdin !== undefined) { p.stdin.write(stdin); p.stdin.end(); }
    const [out, stderr] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text()]);
    return { out, stderr: stderr.trim(), code: await p.exited };
  } catch (e: any) {
    // Bun.spawn throws when the binary does not exist — that is a result, not a crash.
    return { out: "", stderr: String(e?.message ?? e), code: 127 };
  }
}

async function has(bin: string): Promise<boolean> {
  return (await run(["/bin/sh", "-c", `command -v ${bin}`])).code === 0;
}

export async function linuxScreenStatus(): Promise<{ ok: boolean; tool: "scrot"; hint?: string }> {
  const tool = await has("scrot");
  const display = tool && (await run(["xdotool", "getdisplaygeometry"])).code === 0;
  return {
    ok: tool && display,
    tool: "scrot",
    hint: !tool ? "apt install scrot"
      : !display ? `no X display at ${DISPLAY} (set MESH_DISPLAY if X is not on :0)` : undefined,
  };
}

export async function linuxCaptureScreen(params: {
  width?: number | null;
  rect?: { x: number; y: number; w: number; h: number } | null;
  quality?: number | null;
}): Promise<Response> {
  if (!(await has("scrot"))) return json({ error: "scrot not installed (apt install scrot)" }, 503);
  const geometry = await run(["xdotool", "getdisplaygeometry"]);
  const [screenWidth, screenHeight] = geometry.out.trim().split(/\s+/).map(Number);
  if (geometry.code !== 0 || !(screenWidth > 0) || !(screenHeight > 0)) {
    return json({ error: "screen geometry unavailable" }, 503);
  }

  const path = join(tmpdir(), `meshd-screen-linux-${process.pid}-${Date.now()}.jpg`);
  const headers: Record<string, string> = { "content-type": "image/jpeg", "cache-control": "no-store" };
  const args = ["scrot", "-o", "-q", String(params.quality ?? 70)];
  if (params.rect) {
    const { x, y, w, h } = params.rect;
    args.push("-a", `${Math.round(x * screenWidth)},${Math.round(y * screenHeight)},${Math.max(1, Math.round(w * screenWidth))},${Math.max(1, Math.round(h * screenHeight))}`);
  }
  args.push("--pointer", path);

  try {
    let shot = await run(args);
    if (shot.code !== 0 && /pointer/i.test(shot.stderr)) {
      shot = await run(args.filter((arg) => arg !== "--pointer"));
    }
    if (shot.code !== 0) return json({ error: shot.stderr || "screenshot unavailable" }, 503);
    const bytes = await readFile(path).catch(() => null);
    // scrot can exit 0 and leave nothing behind (X gone mid-shot); an empty 200 would read as a black screen.
    if (!bytes || bytes.byteLength === 0) return json({ error: "screenshot empty" }, 503);
    if (params.rect) headers["x-mesh-rect"] = `${params.rect.x},${params.rect.y},${params.rect.w},${params.rect.h}`;
    // width is honoured when a resizer is around: a 3440-wide JPEG measured 78 KB per frame
    // whatever the watch asked for, and the watch decodes every pixel of it.
    const width = params.width && params.width > 0 && params.width < screenWidth ? Math.round(params.width) : 0;
    if (width) {
      const q = String(params.quality ?? 70);
      const small = path.replace(/\.jpg$/, "-small.jpg");
      const resized = (await has("convert"))
        ? await run(["convert", path, "-resize", `${width}x`, "-quality", q, small])
        : (await has("ffmpeg"))
          ? await run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-vf", `scale=${width}:-2`, "-q:v", String(Math.max(2, Math.round(31 - (Number(q) / 100) * 29))), small])
          : { code: 1, out: "", stderr: "" };
      if (resized.code === 0) {
        const smallBytes = await readFile(small).catch(() => null);
        await unlink(small).catch(() => {});
        if (smallBytes && smallBytes.byteLength > 0) return new Response(smallBytes, { headers });
      }
    }
    return new Response(bytes, { headers });
  } finally {
    await unlink(path).catch(() => {});
  }
}

// Watch key names -> X keysyms. Letters/digits pass through untouched.
const KEYSYMS: Record<string, string> = {
  return: "Return", enter: "Return", tab: "Tab", space: "space", esc: "Escape", escape: "Escape",
  backspace: "BackSpace", delete: "BackSpace", forwarddelete: "Delete",
  up: "Up", down: "Down", left: "Left", right: "Right",
  home: "Home", end: "End", pageup: "Prior", pagedown: "Next", grave: "grave",
  f1: "F1", f2: "F2", f3: "F3", f4: "F4", f5: "F5", f6: "F6",
  f7: "F7", f8: "F8", f9: "F9", f10: "F10", f11: "F11", f12: "F12",
  // Digits explicitly, not only via keysym()'s [a-z0-9] pass-through — the coverage
  // check reads this map literally (unquoted keys only), and the chord chips
  // (cmd-shift-2, cmd-shift-4) made digits part of the key bar's vocabulary.
  0: "0", 1: "1", 2: "2", 3: "3", 4: "4",
  5: "5", 6: "6", 7: "7", 8: "8", 9: "9",
};
// cmd from the watch means "the primary shortcut modifier" — on Linux that is ctrl.
const MODS: Record<string, string> = {
  cmd: "ctrl", command: "ctrl", meta: "super",
  ctrl: "ctrl", control: "ctrl",
  opt: "alt", option: "alt", alt: "alt",
  shift: "shift", fn: "",
};
const MEDIA: Record<string, string> = {
  playpause: "XF86AudioPlay", play: "XF86AudioPlay", pause: "XF86AudioPause",
  next: "XF86AudioNext", fastforward: "XF86AudioNext",
  prev: "XF86AudioPrev", previous: "XF86AudioPrev", rewind: "XF86AudioPrev",
  volumeup: "XF86AudioRaiseVolume", volumedown: "XF86AudioLowerVolume", mute: "XF86AudioMute",
};
const BUTTONS: Record<string, string> = { left: "1", middle: "2", right: "3" };

function keysym(key: string): string | null {
  const k = key.toLowerCase();
  if (KEYSYMS[k]) return KEYSYMS[k];
  if (/^[a-z0-9]$/.test(k)) return k;
  return null;
}

/// One xdotool argv per event; unknown events are skipped, not fatal.
export function eventToArgs(e: any): string[] | null {
  switch (e.t) {
    case "move": return ["mousemove_relative", "--", String(Math.round(e.dx ?? 0)), String(Math.round(e.dy ?? 0))];
    case "moveto": case "moveTo": return null; // needs per-display geometry; watch falls back to relative
    case "click": {
      const btn = BUTTONS[String(e.button ?? "left")] ?? "1";
      const count = Math.min(3, Math.max(1, Number(e.count ?? 1)));
      return ["click", "--repeat", String(count), btn];
    }
    case "down": return ["mousedown", "1"];
    case "up": return ["mouseup", "1"];
    case "scroll": {
      // pixel deltas -> wheel clicks; 4/5 vertical, 6/7 horizontal
      const vy = Math.round((e.dy ?? 0) / 40), vx = Math.round((e.dx ?? 0) / 40);
      const btn = Math.abs(vy) >= Math.abs(vx) ? (vy > 0 ? "5" : "4") : (vx > 0 ? "7" : "6");
      const reps = Math.min(20, Math.max(1, Math.abs(vy) || Math.abs(vx)));
      return vy === 0 && vx === 0 ? null : ["click", "--repeat", String(reps), btn];
    }
    case "key": {
      const sym = keysym(String(e.key ?? ""));
      if (!sym) return null;
      const mods = (Array.isArray(e.mods) ? e.mods : [])
        .map((m: any) => MODS[String(m).toLowerCase()])
        .filter(Boolean);
      return ["key", "--clearmodifiers", [...mods, sym].join("+")];
    }
    case "text": {
      const s = String(e.s ?? "");
      return s ? ["type", "--clearmodifiers", "--", s] : null;
    }
    case "media": {
      const sym = MEDIA[String(e.key ?? "").toLowerCase()];
      return sym ? ["key", sym] : null;
    }
    default: return null;
  }
}

export async function linuxInjectEvents(events: any[]): Promise<{ ok: boolean; count?: number; error?: string }> {
  if (!(await has("xdotool"))) return { ok: false, error: "xdotool not installed (apt install xdotool)" };
  let count = 0;
  for (const e of events) {
    const args = eventToArgs(e);
    if (!args) continue;
    await run(["xdotool", ...args]);
    count++;
  }
  return count > 0 ? { ok: true, count } : { ok: false, error: "no injectable events" };
}

export async function linuxInputStatus() {
  const tool = await has("xdotool");
  const display = tool && (await run(["xdotool", "getdisplaygeometry"])).code === 0;
  return {
    ok: tool && display,
    trusted: tool && display, // the watch UI keys off `trusted`; no TCC on Linux
    helper: "xdotool",
    display: DISPLAY,
    hint: !tool ? "apt install xdotool xclip"
      : !display ? `no X display at ${DISPLAY} (set MESH_DISPLAY, or start Xvfb/VNC)` : undefined,
  };
}

export async function linuxClipboard(text?: string): Promise<{ ok: boolean; text?: string; error?: string }> {
  if (!(await has("xclip"))) return { ok: false, error: "xclip not installed (apt install xclip)" };
  if (typeof text === "string") {
    // xclip forks a child that keeps serving the selection, and that child inherits our
    // stdout pipe: run() waited on it and the route hung until the client's timeout
    // (measured 15 s on the Pi while the text had landed instantly). Nothing to read here.
    const p = Bun.spawn(["xclip", "-selection", "clipboard", "-in"], { env: ENV, stdin: "pipe", stdout: "ignore", stderr: "ignore" });
    p.stdin.write(text);
    await p.stdin.end();
    return (await p.exited) === 0 ? { ok: true } : { ok: false, error: "xclip failed" };
  }
  return { ok: true, text: (await run(["xclip", "-selection", "clipboard", "-out"])).out };
}

export async function linuxVolume(body: any) {
  if (!(await has("pactl"))) return { ok: false, error: "pactl not installed" };
  const read = async () => {
    const vol = (await run(["/bin/sh", "-c", "pactl get-sink-volume @DEFAULT_SINK@"])).out;
    const mut = (await run(["/bin/sh", "-c", "pactl get-sink-mute @DEFAULT_SINK@"])).out;
    return { level: Number(vol.match(/(\d+)%/)?.[1] ?? 0), muted: /yes/.test(mut) };
  };
  const current = await read();
  if (typeof body?.muted === "boolean") await run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", body.muted ? "1" : "0"]);
  const target = typeof body?.level === "number" ? body.level
    : typeof body?.delta === "number" ? current.level + body.delta : null;
  if (target !== null) {
    await run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", `${Math.round(Math.min(100, Math.max(0, target)))}%`]);
    if (typeof body?.muted !== "boolean") await run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "0"]);
  }
  return { ok: true, ...(await read()) };
}

const LINUX_SYSTEM: Record<string, string[]> = {
  lock: ["loginctl", "lock-session"],
  displaysleep: ["xset", "dpms", "force", "off"],
  sleep: ["systemctl", "suspend"],
  screensaver: ["xdg-screensaver", "activate"],
  // A full-screen PNG into the clipboard — the thing a person hands to an agent next.
  // xclip forks to keep serving the selection and would hold our stdout pipe open forever.
  screenshot: ["/bin/sh", "-c", 'f=$(mktemp --suffix=.png) && scrot -o "$f" && xclip -selection clipboard -t image/png -i "$f" >/dev/null 2>&1; s=$?; rm -f "$f"; exit $s'],
  shutdown: ["systemctl", "poweroff"],
  restart: ["systemctl", "reboot"],
};

/// Truthful by contract: exit code and stderr travel back to the client, so a
/// loginctl that is not there (or a systemctl that wants polkit auth) reads as the
/// failure it is instead of a silent "ok".
export async function linuxSystemAction(action: string) {
  // hasOwn, not a bare lookup — see the note in input.ts systemAction().
  const cmd = Object.hasOwn(LINUX_SYSTEM, action) ? LINUX_SYSTEM[action] : undefined;
  if (!cmd) return { ok: false, error: `unsupported on linux: ${action}` };
  const r = await run(cmd);
  return {
    ok: r.code === 0,
    action,
    exitCode: r.code,
    stderr: r.stderr,
    ...(r.code === 0 ? {} : { error: r.stderr.slice(0, 300) || `exit ${r.code}` }),
  };
}

/// Running apps = the window manager's client list, read with xprop (present on every X desktop;
/// wmctrl is not). One spawn for the list, one per window for its class and title, one for the
/// active window. Same wire shape as the Mac's lsappinfo pass: `bundleID` carries the WM_CLASS so
/// the watch can group and activate by it. `installed` stays empty — launching by .desktop id is
/// a different verb and nobody has asked for it from the wrist yet.
export async function linuxListApps() {
  if (!(await has("xprop"))) return { ok: false, error: "xprop not installed (apt install x11-utils)" };
  const list = await run(["xprop", "-root", "_NET_CLIENT_LIST_STACKING"]);
  if (list.code !== 0) return { ok: false, error: list.stderr.trim() || "no window manager on the display" };
  const ids = (list.out.split("#")[1] ?? "").split(",").map((x) => x.trim()).filter((x) => /^0x[0-9a-f]+$/i.test(x)).slice(-40);
  const active = (await run(["xprop", "-root", "_NET_ACTIVE_WINDOW"])).out.match(/0x[0-9a-f]+/i)?.[0]?.toLowerCase();
  const seen = new Map<string, { name: string; bundleID: string; front: boolean; windowID: string }>();
  for (const id of ids) {
    const props = (await run(["xprop", "-id", id, "WM_CLASS", "_NET_WM_NAME", "WM_NAME"])).out;
    const cls = props.match(/WM_CLASS\(STRING\) = "[^"]*", "([^"]*)"/)?.[1];
    const title = props.match(/_NET_WM_NAME\([^)]*\) = "((?:[^"\\]|\\.)*)"/)?.[1] ?? props.match(/WM_NAME\([^)]*\) = "((?:[^"\\]|\\.)*)"/)?.[1];
    if (!cls) continue;
    const front = id.toLowerCase() === active;
    const prev = seen.get(cls);
    // One row per app, the frontmost window's title winning; the stacking list is bottom-up.
    if (!prev || front || !prev.front) seen.set(cls, { name: cls, bundleID: cls, front: prev?.front || front, windowID: id });
    if (title && seen.get(cls)) seen.get(cls)!.name = `${cls} — ${title}`.slice(0, 80);
  }
  const running = [...seen.values()];
  return { ok: true, front: running.find((a) => a.front)?.bundleID, running, installed: [] as string[] };
}

/// Bring a running app's window to the front by class (what linuxListApps reports as
/// bundleID) or by title; argv only, the name comes from the watch.
export async function linuxActivateApp(name: string) {
  if (!name.trim()) return { ok: false, error: "app name required" };
  if (!(await has("xdotool"))) return { ok: false, error: "xdotool not installed" };
  const query = name.split(" — ")[0].trim();
  let found = "";
  for (const by of ["--class", "--classname", "--name"]) {
    found = (await run(["xdotool", "search", "--onlyvisible", by, query])).out.trim().split("\n")[0];
    if (found) break;
  }
  if (!found) return { ok: false, error: `no window for ${query}` };
  const r = await run(["xdotool", "windowactivate", "--sync", found]);
  return r.code === 0 ? { ok: true, activated: query } : { ok: false, error: r.stderr.trim() || "could not activate" };
}

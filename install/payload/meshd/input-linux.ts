// Linux input backend — same wire contract as the Mac helper, delivered with
// stock desktop tools instead of a compiled helper:
//   pointer/keys/text/scroll -> xdotool   (X11; covers Xvfb/VNC sessions too)
//   clipboard                -> xclip
//   volume                   -> pactl
//   lock / displaysleep      -> loginctl / xset
// ponytail: X11 only — Wayland needs ydotool+uinput; add a ydotool branch when a
// Wayland box actually joins the mesh. Apps/windows/displays stay unsupported here.
const DISPLAY = process.env.MESH_DISPLAY ?? process.env.DISPLAY ?? ":0";
const ENV = { ...process.env, DISPLAY };

async function run(cmd: string[], stdin?: string): Promise<{ out: string; code: number }> {
  const p = Bun.spawn(cmd, {
    env: ENV,
    stdin: stdin === undefined ? "ignore" : "pipe",
    stdout: "pipe",
    stderr: "ignore",
  });
  if (stdin !== undefined) { p.stdin.write(stdin); p.stdin.end(); }
  const out = await new Response(p.stdout).text();
  return { out, code: await p.exited };
}

async function has(bin: string): Promise<boolean> {
  return (await run(["/bin/sh", "-c", `command -v ${bin}`])).code === 0;
}

// Watch key names -> X keysyms. Letters/digits pass through untouched.
const KEYSYMS: Record<string, string> = {
  return: "Return", enter: "Return", tab: "Tab", space: "space", esc: "Escape", escape: "Escape",
  backspace: "BackSpace", delete: "BackSpace", forwarddelete: "Delete",
  up: "Up", down: "Down", left: "Left", right: "Right",
  home: "Home", end: "End", pageup: "Prior", pagedown: "Next", grave: "grave",
  f1: "F1", f2: "F2", f3: "F3", f4: "F4", f5: "F5", f6: "F6",
  f7: "F7", f8: "F8", f9: "F9", f10: "F10", f11: "F11", f12: "F12",
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
    await run(["xclip", "-selection", "clipboard", "-in"], text);
    return { ok: true };
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
};

export async function linuxSystemAction(action: string) {
  const cmd = LINUX_SYSTEM[action];
  if (!cmd) return { ok: false, error: `unsupported on linux: ${action}` };
  await run(cmd);
  return { ok: true, action };
}

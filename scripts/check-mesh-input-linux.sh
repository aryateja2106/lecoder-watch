#!/bin/sh
# Linux input self-check: every event the watch sends maps to a sane xdotool argv.
# Pure mapping test — runs anywhere, needs no X server.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-input-linux: SKIP (bun not installed)"; exit 0; }
cd "$ROOT/install/payload/meshd"

bun -e '
import { eventToArgs } from "./input-linux.ts";
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const cases = [
  [{ t: "move", dx: 10, dy: -5 }, ["mousemove_relative", "--", "10", "-5"]],
  [{ t: "click" }, ["click", "--repeat", "1", "1"]],
  [{ t: "click", button: "right", count: 2 }, ["click", "--repeat", "2", "3"]],
  [{ t: "down" }, ["mousedown", "1"]],
  [{ t: "up" }, ["mouseup", "1"]],
  [{ t: "scroll", dy: 120 }, ["click", "--repeat", "3", "5"]],
  [{ t: "scroll", dy: -80 }, ["click", "--repeat", "2", "4"]],
  [{ t: "key", key: "return" }, ["key", "--clearmodifiers", "Return"]],
  [{ t: "key", key: "c", mods: ["cmd"] }, ["key", "--clearmodifiers", "ctrl+c"]],
  [{ t: "key", key: "tab", mods: ["opt", "shift"] }, ["key", "--clearmodifiers", "alt+shift+Tab"]],
  [{ t: "text", s: "hello" }, ["type", "--clearmodifiers", "--", "hello"]],
  [{ t: "media", key: "playpause" }, ["key", "XF86AudioPlay"]],
  [{ t: "scroll", dy: 0, dx: 0 }, null],   // no-op scroll skipped
  [{ t: "window", place: "left" }, null],  // unsupported on linux
];
for (const [ev, want] of cases) {
  const got = eventToArgs(ev);
  if (!eq(got, want)) throw new Error(`map(${JSON.stringify(ev)}) = ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
}
// every named key + every media key must map
const keys = "return enter tab space esc escape backspace delete forwarddelete up down left right home end pageup pagedown grave f1 f12 a z 0 9".split(" ");
for (const k of keys) if (!eventToArgs({ t: "key", key: k })) throw new Error(`key ${k} unmapped`);
const media = "playpause play pause next prev previous fastforward rewind volumeup volumedown mute".split(" ");
for (const m of media) if (!eventToArgs({ t: "media", key: m })) throw new Error(`media ${m} unmapped`);
console.log("check-mesh-input-linux: OK — all watch events map to xdotool");
'

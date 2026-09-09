// capabilities.ts — what /health advertises must match what the daemon can actually do.
// The CAPABILITIES array is the macOS superset (what check-daemon-gaps.sh compares
// against DaemonCapabilities.expected). advertisedCapabilities() is the honest list
// for this process: Linux drops screen routes; containers drop desktop input too.
import { existsSync } from "node:fs";

const IS_MAC = process.platform === "darwin";

/** Full superset a current macOS daemon can advertise. Linux/container subsets derive from this. */
export const CAPABILITIES = [
  "events", "newPane", "paneTarget", "usage", "agents", "cmux", "tailscale", "kb",
  "screenPeek", "input", "files", "push", "pair", "doctor", "wake",
  "screenRegion", "openUrl", "power", "laPush", "sessionStatus", "paste", "captureJoin",
];

const MAC_SCREEN = new Set(["screenPeek", "screenRegion"]);
/** Host desktop integration — meaningless inside a default container (no X11, no polkit). */
const CONTAINER_DESKTOP = new Set(["input", "openUrl", "power"]);

export function inContainer(): boolean {
  const v = (process.env.MESHD_CONTAINER ?? "").trim().toLowerCase();
  if (v === "1" || v === "true" || v === "yes") return true;
  if (v === "0" || v === "false" || v === "no") return false;
  try { return existsSync("/.dockerenv"); } catch { return false; }
}

function hasXdotool(): boolean {
  return Boolean(Bun.which("xdotool"));
}

/** Capabilities this process should advertise on GET /health. */
export function advertisedCapabilities(): string[] {
  if (IS_MAC) return [...CAPABILITIES];

  let caps = CAPABILITIES.filter((c) => !MAC_SCREEN.has(c));
  if (inContainer()) {
    caps = caps.filter((c) => !CONTAINER_DESKTOP.has(c));
  } else if (!hasXdotool()) {
    caps = caps.filter((c) => c !== "input");
  }
  return caps;
}

// Self-check: `bun capabilities.ts --check`
if (import.meta.main && process.argv.includes("--check")) {
  const orig = process.env.MESHD_CONTAINER;
  const assert = (cond: boolean, msg: string) => { if (!cond) { console.error(`check-mesh-capabilities: FAIL ${msg}`); process.exit(1); } };

  assert(IS_MAC || !advertisedCapabilities().includes("screenPeek"), "linux must not advertise screenPeek");
  assert(IS_MAC || !advertisedCapabilities().includes("screenRegion"), "linux must not advertise screenRegion");

  process.env.MESHD_CONTAINER = "1";
  if (!IS_MAC) {
    const docker = advertisedCapabilities();
    assert(!docker.includes("input"), "container must not advertise input");
    assert(!docker.includes("openUrl"), "container must not advertise openUrl");
    assert(!docker.includes("power"), "container must not advertise power");
    assert(docker.includes("agents"), "container must still advertise agents");
  }

  if (orig === undefined) delete process.env.MESHD_CONTAINER;
  else process.env.MESHD_CONTAINER = orig;

  assert(CAPABILITIES.includes("screenRegion"), "CAPABILITIES must remain the macOS superset");
  console.log("check-mesh-capabilities: ok");
}

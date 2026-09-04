// doctor.ts — one route that answers "is this machine actually usable?" by testing,
// not by listing intentions. /health advertises static capabilities; TCC grants are
// per-binary and per-launch, so anything short of exercising the real path lies
// (a denied screencapture still exits 0 and hands back a wallpaper-only image).
//
//   GET  /doctor      -> { ok, checks: {...} }   read-only, safe to poll
//   POST /doctor/fix  -> same, after showing the real macOS permission dialogs
//                        (Accessibility + Screen Recording), so the user gets a
//                        button to click instead of a Settings scavenger hunt.
//
// ponytail: its own module + a two-line server.ts patch, same as input.ts/push.ts,
// because three meshd lineages have drifted and this keeps the patch portable.
import os from "node:os";
import { inputStatus } from "./input";
import { pushStatus } from "./push";

const IS_MAC = process.platform === "darwin";

type Check = { ok: boolean; detail: string; fix?: string };
/// `tokenWeak` is the REASON a token is weak, or undefined when it is fine. The token
/// itself deliberately never reaches this module: the caller judges it and passes a
/// verdict, so a doctor report can never leak the thing it is reporting on.
export type DoctorInfo = { tokenSet: boolean; tokenWeak?: string; bind: string; port: number; version: string; mux: string; exposuresOpen?: number };

/// Placeholder tokens that have actually been found in a live fleet, plus the obvious
/// neighbours. `testtoken` was a hardcoded fallback that got copied into a doc and from
/// there back into running daemons, where nothing ever complained about it.
const PLACEHOLDER_TOKENS = new Set(["testtoken", "token", "changeme", "secret", "password", "mesh", "meshd"]);

/// Why this token is not good enough, or null.
///
/// A guessable bearer token on a daemon that can move the mouse and read the screen is a
/// full compromise of the machine, and until now `doctor` called any non-empty string a
/// pass — which is exactly how one stayed in a live fleet for months.
export function tokenWeakness(token: string): string | null {
  if (PLACEHOLDER_TOKENS.has(token.toLowerCase())) return "it is a well-known placeholder";
  if (token.length < 32) return `it is only ${token.length} characters (want 32 or more)`;
  if (new Set(token).size < 8) return "it repeats too few distinct characters";
  return null;
}

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

/// The coding-agent CLIs a session can be started with, in the order the phone lists them.
export const AGENT_CLIS = ["claude", "codex", "cursor-agent", "agy", "hermes", "openclaw"] as const;
export function installedAgents(): Array<{ name: string; path: string }> {
  const out: Array<{ name: string; path: string }> = [];
  for (const name of AGENT_CLIS) {
    const path = Bun.which(name);
    if (path) out.push({ name, path });
  }
  return out;
}

export async function doctorReport(prompt: boolean, info: DoctorInfo) {
  const agents = installedAgents();
  const input: any = await inputStatus(prompt).catch((e) => ({ ok: false, error: String(e?.message ?? e) }));
  const push = await pushStatus().catch(() => ({ configured: false, devices: 0 }));
  const muxPath = Bun.which(info.mux);

  const checks: Record<string, Check> = {
    token: !info.tokenSet
      ? {
          ok: false,
          detail: "no token configured — the daemon answers loopback only",
          fix: "reinstall (the installer mints one): curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh",
        }
      : info.tokenWeak
        ? {
            ok: false,
            // Anyone who can guess this can move the mouse and read the screen.
            detail: `bearer token is guessable — ${info.tokenWeak}`,
            fix: "mesh token rotate   (then re-pair the phone)",
          }
        : { ok: true, detail: "bearer token set; off-box requests must present it" },
    input: input?.trusted
      ? { ok: true, detail: "input trusted; clicks and keys reach the OS" }
      : {
          ok: false,
          detail: input?.error ?? "input not trusted — every click and key is silently dropped",
          fix: input?.hint ?? (IS_MAC ? "mesh doctor --fix, then toggle mesh-input on in System Settings › Privacy & Security › Accessibility" : "install xdotool/xclip"),
        },
    screen: !IS_MAC
      ? { ok: true, detail: "screen capture not supported on Linux yet" }
      : input?.screen
        ? { ok: true, detail: "Screen Recording granted; /screen.jpg shows real windows" }
        : {
            ok: false,
            // The silent failure mode is the whole reason this check exists.
            detail: "Screen Recording not granted — screenshots show only the wallpaper, with no error",
            fix: "mesh doctor --fix, then toggle the daemon on in System Settings › Privacy & Security › Screen Recording",
          },
    mux: muxPath
      ? { ok: true, detail: `${info.mux} at ${muxPath}` }
      : { ok: false, detail: `${info.mux} not on PATH — agent sessions unavailable`, fix: IS_MAC ? "reinstall the mesh payload" : `apt install ${info.mux}` },
    // Push is optional by design (the product works without APNs), so it can only
    // report, never fail the machine.
    push: {
      ok: true,
      detail: push.configured ? `APNs key ${(push as any).keyId ?? ""} · ${push.devices} device(s) registered` : "APNs not configured (optional — alerts arrive only while the app polls)",
    },
    // Informational, like push: the daemon redacted these before they left the Mac, but
    // a secret that was printed at all should be rotated at its provider.
    exposures: (info.exposuresOpen ?? 0) > 0
      ? { ok: true, detail: `${info.exposuresOpen} secret(s) seen in agent/terminal output and redacted — rotate them`, fix: "mesh exposures   (then mark each one rotated)" }
      : { ok: true, detail: "no secrets seen in agent/terminal output" },
    // Informational: which coding-agent CLIs this machine can launch into a session. The
    // phone shows a launcher only for what is actually here.
    agents: agents.length
      ? { ok: true, detail: `agent CLIs on PATH: ${agents.map((a) => a.name).join(", ")}` }
      : { ok: true, detail: "no coding-agent CLI (claude, codex, cursor-agent, agy, hermes, openclaw) found on PATH" },
  };

  const ok = Object.values(checks).every((c) => c.ok);
  return { ok, host: os.hostname(), platform: process.platform, version: info.version, bind: `${info.bind}:${info.port}`, prompted: prompt, checks, agents };
}

export async function handleDoctor(req: Request, url: URL, info: DoctorInfo): Promise<Response | null> {
  if (url.pathname === "/doctor" && req.method === "GET") return json(await doctorReport(false, info));
  if (url.pathname === "/doctor/fix" && req.method === "POST") return json(await doctorReport(true, info));
  return null;
}

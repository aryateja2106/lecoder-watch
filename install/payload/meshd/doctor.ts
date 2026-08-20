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
export type DoctorInfo = { tokenSet: boolean; bind: string; port: number; version: string; mux: string };

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

export async function doctorReport(prompt: boolean, info: DoctorInfo) {
  const input: any = await inputStatus(prompt).catch((e) => ({ ok: false, error: String(e?.message ?? e) }));
  const push = await pushStatus().catch(() => ({ configured: false, devices: 0 }));
  const muxPath = Bun.which(info.mux);

  const checks: Record<string, Check> = {
    token: info.tokenSet
      ? { ok: true, detail: "bearer token set; off-box requests must present it" }
      : {
          ok: false,
          detail: "no token configured — the daemon answers loopback only",
          fix: "reinstall (the installer mints one): curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh",
        },
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
  };

  const ok = Object.values(checks).every((c) => c.ok);
  return { ok, host: os.hostname(), platform: process.platform, version: info.version, bind: `${info.bind}:${info.port}`, prompted: prompt, checks };
}

export async function handleDoctor(req: Request, url: URL, info: DoctorInfo): Promise<Response | null> {
  if (url.pathname === "/doctor" && req.method === "GET") return json(await doctorReport(false, info));
  if (url.pathname === "/doctor/fix" && req.method === "POST") return json(await doctorReport(true, info));
  return null;
}

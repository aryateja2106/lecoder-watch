# MeshWatch

Control and monitor your Tailscale-mesh machines and AI agents from your **Apple Watch + iPhone**.

- **htop on your wrist** — CPU / memory / disk / load / top processes for every machine, live.
- **Agents across the mesh** — list rmux/agent sessions per machine; send commands by voice, Scribble, quick-keys, or presets.
- **Usage glance** — OpenUsage limits (Codex / Claude / Cursor / Gemini), % used and reset times — built for overnight loops.
- **Notifications** — usage thresholds (>85%) and machine offline/online transitions.

## Architecture (option A — iPhone relay)

```
Apple Watch (SwiftUI) ──WatchConnectivity── iPhone relay ──HTTP/Tailscale──┬─ Mac:      meshd
  Machines · Usage · Agents                  (on the tailnet, polls all)   ├─ arya-pi:  meshd
  Crown scroll · dictation · Scribble                                      └─ dataflow: meshd
```

The watch never touches the mesh directly — the paired iPhone (a tailnet node) polls every machine's `meshd` and relays the latest snapshot to the watch. "One bot per machine" = one `meshd` per machine.

## Setup — one command per machine

Run this on every Mac or Linux box you want to reach:

```bash
curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh
```

It installs bun if missing, starts `meshd` (launchd on macOS, systemd on Linux),
and prints an address and a generated token. In the iPhone app, tap **Paste
installer output** during setup and it reads both out for you — no transcribing.

Install Tailscale on the machine and the iPhone to reach it from anywhere; on the
same Wi-Fi you can skip it.

## meshd — the per-machine agent

bun + TypeScript. `GET /stats` (htop-style), `GET /agents` + `/agents/:name/{output,send}`, `GET /usage` (OpenUsage, macOS). Bearer-token auth, binds `0.0.0.0:8899` on the private tailnet.

Sessions come from three sources, merged into one list: **rmux/tmux**, **cmux**, and
**[Orca](https://github.com/stablyai/orca)** (via its `orca` CLI, when the Orca runtime
is reachable — this is what gives Orca users a watch client). Orca terminals appear as
`orca:<handle>` and support read and send; they are closed from Orca itself.

```bash
MESHD_TOKEN=yourtoken ./meshd/deploy.sh   # dev-only: maintainer's fleet over tmux
```

## App (Xcode)

```bash
xcodegen generate
open MeshWatch.xcodeproj
# Watch: scheme "MeshWatch Watch App"  ·  iPhone: scheme "MeshWatch"
```

First launch walks through setup: what the app is → the install command → connect a
machine → notifications. Nothing polls and no permission is requested before that.
The app ships with **no** machines; add yours in onboarding or the **Settings** tab.

## Status

- ✅ Watch app + iOS relay build clean; watch runs in simulator.
- ✅ meshd live on Mac + pi + dataflow over Tailscale, serving real data.
- ✅ iPhone relay shows the full mesh live (3 machines, htop stats + agents + usage).
- ⏳ Watch live-data leg verifies on real paired devices (sim WCSession handoff is unreliable — an Apple simulator limitation, not a code issue).
- ⏳ Next: terminal output streaming to the watch; native watch complication.

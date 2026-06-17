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

## meshd — the per-machine agent

bun + TypeScript. `GET /stats` (htop-style), `GET /agents` + `/agents/:name/{output,send}` (rmux), `GET /usage` (OpenUsage, macOS). Bearer-token auth, binds `0.0.0.0:8899` on the private tailnet.

```bash
MESHD_TOKEN=yourtoken ./meshd/deploy.sh   # starts on Mac + pi + dataflow (tmux)
MESHD_TOKEN=yourtoken ./meshd/mesh-self-check --require-screen
```

## App (Xcode)

```bash
xcodegen generate
open MeshWatch.xcodeproj
# Watch: scheme "MeshWatch Watch App"  ·  iPhone: scheme "MeshWatch"
```

Build/run verified on iPhone 17 + Apple Watch Series 11 simulators (watchOS 26.5). Set each machine's token in the iPhone **Settings** tab (default `testtoken` is a dev placeholder).

## Status

- ✅ Watch app + iOS relay build clean; watch runs in simulator.
- ✅ meshd live on Mac + pi + dataflow over Tailscale, serving real data.
- ✅ iPhone relay shows the full mesh live (3 machines, htop stats + agents + usage).
- ⏳ Watch live-data leg verifies on real paired devices (sim WCSession handoff is unreliable — an Apple simulator limitation, not a code issue).
- ⏳ Next: terminal output streaming to the watch; native watch complication.

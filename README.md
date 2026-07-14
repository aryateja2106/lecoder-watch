# MeshWatch

Control and monitor your Tailscale-mesh machines and AI agents from your **Apple Watch + iPhone**.

- **htop on your wrist** — CPU / memory / disk / load / top processes for every machine, live.
- **Agents across the mesh** — list rmux/agent sessions per machine; send commands by voice, Scribble, quick-keys, or presets.
- **Usage glance** — OpenUsage limits (Codex / Claude / Cursor / Gemini), % used and reset times — built for overnight loops.
- **Notifications** — usage thresholds (>85%), machine offline/online transitions, and per-source/per-type agent-event alerts (needs-input / finished / error) with tap-to-open.
- **Widgets & Live Activity** — Dynamic Island / Lock Screen Live Activity for the pinned session (`meshwatch://` deep link).

## Architecture (option A — iPhone relay)

```
Apple Watch (SwiftUI) ──WatchConnectivity── iPhone relay ──HTTP/Tailscale──┬─ Mac:      meshd
  Machines · Usage · Agents                  (on the tailnet, polls all)   ├─ arya-pi:  meshd
  Crown scroll · dictation · Scribble                                      └─ dataflow: meshd
```

The watch never touches the mesh directly — the paired iPhone (a tailnet node) polls every machine's `meshd` and relays the latest snapshot to the watch. "One bot per machine" = one `meshd` per machine.

## meshd — the per-machine agent

bun + TypeScript. `GET /stats` (htop-style), `GET /agents` + `/agents/:name/{output,send}` (rmux), `GET /usage` (OpenUsage, macOS). Bearer-token auth — header-only (`Authorization: Bearer`, no `?token=`), fail-closed, constant-time compare — binds `0.0.0.0:8899` on the private tailnet. `output?lines=N` captures full pane history (`tmux capture-pane -S -`) before slicing, so it returns real scrollback, not just the visible viewport. Deployed daemons keep running the old code until `install.sh` is rerun on that machine — that's a deliberate, explicit step (it clobbers the live install), not automatic.

```bash
MESHD_TOKEN=yourtoken ./meshd/deploy.sh   # starts on Mac + pi + dataflow (tmux)
```

## App (Xcode)

```bash
xcodegen generate
open MeshWatch.xcodeproj
# Watch: scheme "MeshWatch Watch App"  ·  iPhone: scheme "MeshWatch"
```

Build/run verified on iPhone 17 + Apple Watch Series 11 simulators (watchOS 26.5). Ships with iOS + watchOS app icons. Set each machine's token in the iPhone **Settings** tab — the dogfood default `testtoken` on every `Machine` in `Shared/Models.swift` must become a strong, unique per-machine token before any Tailscale Funnel or other public exposure (meshd fails closed, but a guessable shared token defeats that).

## Status

- ✅ Watch app + iOS relay build clean; watch runs in simulator — simulator builds are approved for testing (supersedes the earlier real-device-only stance).
- ✅ meshd live on Mac + pi + dataflow over Tailscale, serving real data; `aryateja-jetson` is now in the `Machine` defaults list too.
- ✅ iPhone relay shows the full mesh live (3 machines, htop stats + agents + usage).
- ⏳ Watch live-data leg verifies on real paired devices (sim WCSession handoff is unreliable — an Apple simulator limitation, not a code issue).
- ⏳ Known gap: watch terminal output is 1.5s poll-based (`WatchMeshStore.watch`), not push.
- ⏳ Next: terminal output streaming to the watch; native watch complication.

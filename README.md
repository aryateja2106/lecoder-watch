# MeshWatch

**Control and monitor your machines and AI coding agents from your Apple Watch and iPhone — over your own private Tailscale network.**

MeshWatch is the native watchOS + iOS client for [LeCoder](https://lecoder.lesearch.ai). As AI agents go local and multi-machine, you need one place to run, watch, and steer them — without being chained to a laptop. MeshWatch puts that command surface on your wrist.

- **Agent terminal on your wrist** — list the agent/shell sessions on each machine, send commands (dictation, Scribble, quick-key presets, or a natural-language phrase), and watch output stream back.
- **htop, glanceable** — CPU / memory / disk / load / top processes per machine, live.
- **Screen peek** — a periodically-refreshed screenshot of a machine, VNC-style, where a full remote desktop won't fit (e.g. the watch).
- **Usage** — coding-agent quota (Claude / Codex / Cursor / Gemini): % used and reset times, built for overnight loops.
- **Notifications** — agent events, usage thresholds, and machine offline/online transitions, with actionable categories, a Live Activity / Dynamic Island session pin, and a Home/Lock-Screen widget.

Everything runs on infrastructure you own. No cloud relay, no phone-home.

## Architecture

```
Apple Watch (SwiftUI) ──WatchConnectivity── iPhone (tailnet node) ──HTTP/Tailscale──┬─ mac:     meshd
  terminal · stats · usage · screen          relays snapshots, forwards commands     ├─ pi:      meshd
  Crown scroll · dictation · Scribble                                                └─ server:  meshd
```

The paired iPhone is a Tailscale node: it polls every machine's `meshd` and relays the latest snapshot to the watch, and forwards the watch's commands back to `meshd`. When the watch can reach the tailnet itself, it talks to `meshd` directly; otherwise it falls back to the iPhone relay. One `meshd` per machine.

## meshd — the per-machine daemon

A single-file [Bun](https://bun.sh) + TypeScript HTTP daemon. Bearer-token auth, binds `0.0.0.0:8899` on your private tailnet (`/health` is unauthenticated).

| Route | Purpose |
|---|---|
| `GET /health` · `GET /stats` | host info + capabilities; htop-style system stats |
| `GET /agents` · `GET /agents/:name/output` | list rmux/tmux sessions; tail a session's output |
| `POST /agents/:name/send` | send text or a control key (`enter`/`ctrl-c`/`up`/`down`) to a session |
| `GET/POST /agents/:name/panes` · `POST /agents/new` · `DELETE …` | pane + session lifecycle |
| `GET /screen.jpg` | a resized JPEG screenshot of the machine (macOS `screencapture`+`sips`; Linux `grim`/`scrot`) |
| `GET /usage` · `GET /events` · `GET /tailnet` | quota; agent hook events; tailnet peers |
| `PUT/GET /kb` · `GET /kb/search` | a SQLite-FTS5 knowledge base, with read-federation across tailnet peers |

```bash
MESHD_TOKEN=<a-strong-secret> bun run meshd/server.ts     # one machine
MESHD_TOKEN=<a-strong-secret> ./meshd/deploy.sh           # fan out to your tailnet (edit hosts/IPs first)
```

## Build the app

```bash
brew install xcodegen          # once
xcodegen generate
open MeshWatch.xcodeproj
# Watch scheme: "MeshWatch Watch App"   ·   iPhone scheme: "MeshWatch"
```

Set your own Apple Developer Team ID in `project.yml` (`DEVELOPMENT_TEAM`) to run on a device. Builds verified against the watchOS / iOS 26 simulators. In the iPhone **Settings** tab, set each machine's Tailscale IP and the token printed by `install.sh`.

## Install meshd on a machine

```bash
./install/install.sh --token <a-strong-secret>
```

This drops `meshd` plus the helper tools (`mesh-event`, `mesh-hook`, `mesh-self-check`, …) under `~/.mesh` and prints the token to paste into the app.

## Security

- The Bearer token gates **remote keystroke injection** into your sessions — treat it like an SSH key. Use a strong, unique `MESHD_TOKEN` per deployment and never commit it.
- Keep machines reachable only over Tailscale, with tight tailnet ACLs. `meshd` binds the tailnet interface, not the public internet.

## Status

- ✅ Watch + iOS apps build clean; the watch agent-terminal loop (pick session → send → see output) works.
- ✅ `meshd` serves stats, agents, usage, screen, and the KB over Tailscale.
- ✅ Notifications, Live Activity, and the lock-screen widget.
- ⏳ True output streaming (currently ~1.5s polling) and a watch complication.

## License

Apache-2.0.

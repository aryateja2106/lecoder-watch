# INDEX — Start here

Read [context.md](context.md) first (the map and the shape), then [memory.md](memory.md)
(the reasoning). `CHANGELOG.md` tells you what shipped. `git log` traces the path.

## Top files

| Path | Purpose |
|---|---|
| `context.md` | Overall shape, where things live, things that cost hours |
| `memory.md` | Why things are the way they are; settled decisions and dead ends |
| `CHANGELOG.md` | What shipped, in user words; 0.3.0 section is the current state |
| `install/payload/meshd/server.ts` | The daemon; routes, auth, Host/browser defenses |
| `install/payload/meshd/auth.ts` | Fail-closed bearer auth; header-only, constant-time |
| `install/payload/meshd/doctor.ts` | GET/POST /doctor; tests token/input/screen/mux/push |
| `install/payload/meshd/input.ts` | `/input` endpoint; injects CGEvent/xdotool, also `/screen.jpg` |
| `install/payload/meshd/push.ts` | APNs push; dedupe on alertKey, 10-min window |
| `install/payload/meshd/pair.ts` | `/pair/claim` endpoint; the one unauthenticated route |
| `install/payload/meshd/qr.ts` | Vendored QR encoder (no deps); `mesh pair` renders it; `--check` decodes itself |
| `install/payload/meshd/wol.ts` | Wake-on-LAN: magic packet, `POST /wake`, `primaryMac()` for /health |
| `install/payload/meshd/files.ts` | `/files` and `/fs` endpoints; filesystem browser |
| `install/payload/meshd/kb.ts` | Knowledge base (SQLite FTS5); `/kb/*` endpoints |
| `install/payload/bin/mesh-input.swift` | CGEvent helper; recompiled on demand, long-lived on stdin |
| `install/payload/bin/mesh` | CLI: `setup` (first run), `shellenv` (PATH), `pair` (QR), `hooks install`, `doctor [--fix]`, `upgrade`, `token rotate`, `status` |
| `Shared/Models.swift` | Wire types, `sessionsNeedingAttention`, pairing logic |
| `Shared/AlertGating.swift` | Pure notification gates: reachability throttle + event dedupe |
| `docs/VOICE-INPUT-SPEC.md` | Local-first ASR plan (three lanes); addendum: watchOS has NO Speech.framework |
| `docs/CLI-FIRST-ROADMAP.md` | CLI-first stance, command surface, the user scenarios as TDD anchors |
| `Shared/RiskClassifier.swift` | Grades a question safe vs destructive; names the verb ("Force push") |
| `Shared/MeshClient.swift` | HTTP client; bearer auth, URLSession, timeout/retry |
| `iOS/RemoteScreenView.swift`, `Watch/RemoteView.swift` | Native remote: pointer, zoom, keyboard, screen |
| `MeshWatchWidgets/` | Live Activity (Lock Screen, Dynamic Island, Smart Stack) |
| `WatchWidgets/` | Watch complication; renders attention count/session/question |
| `web/` | Landing page; redirect to install.sh |

## Daemon routes

**No token required:**
- `GET  /health` → capabilities, version, host, uptime
- `POST /pair/claim` → mint 8-char code + redeem it → token + fleet

**Loopback-only (empty token) or any authenticated request (non-loopback):**
- `GET  /doctor` → test all systems (read-only)
- `POST /doctor/fix` → same, after showing macOS dialogs
- `GET  /stats` → CPU/mem/disk/processes
- `GET  /tailnet` → Tailscale peers
- `GET  /agents` → rmux/tmux session list
- `GET  /usage` → agent resource usage
- `GET  /events` → agent event log (with `?since=...`)
- `POST /events` → add event (from hook)
- `GET  /screen.jpg?display=N&width=W` → capture one display
- `GET  /input` → input status (trusted, screen grant, hint)
- `POST /input` → inject CGEvent/xdotool + scroll + clipboard + volume
- `POST /wake` → broadcast a Wake-on-LAN magic packet for a sleeping LAN peer ({mac})
- `GET  /kb/search?q=...` → cross-machine KB search
- `POST /kb` or `PUT /kb` → save to KB
- `GET  /files`, `/fs` → filesystem browser
- `GET  /agents/:name/output`, `POST /agents/:name/send` → session I/O
- `GET  /agents/:name/panes`, `POST /agents/:name/panes` → pane list and create
- `DELETE /agents/:name/panes/:id` → kill pane
- `DELETE /agents/:name` → kill session
- `POST /agents/new` → create session
- `GET  /push` → APNs config + registered device count
- `POST /push/register` → save APNs device token
- `POST /push/test` → send a test alert (never deduped)

## Check suite

```sh
sh scripts/check-all.sh    # runs every self-check in one command
```

Globs `check-*.sh` automatically. Includes: auth, CSRF, doctor, hooks, input,
input-linux, pair, push, mesh CLI, package, and any pure-Swift checks compiled
with `-Onone` (asserts are not stripped).

## Build gate

```sh
xcodegen generate                                              # regenerate project
xcodebuild ... -scheme MeshWatch -destination generic/platform=iOS\ Simulator build
xcodebuild ... -scheme "MeshWatch Watch App" -destination generic/platform=watchOS\ Simulator build
sh scripts/check-all.sh                                        # full check suite
```

Never commit unless all three pass. A green build proves very little; run the app
against a real daemon before believing it.

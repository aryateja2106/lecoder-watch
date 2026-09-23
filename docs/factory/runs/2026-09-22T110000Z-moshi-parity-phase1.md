---
run_id: 2026-09-22T110000Z-moshi-parity-phase1
stage: implement
started_at: 2026-09-22T11:00:00Z
finished_at: 2026-09-22T13:00:00Z
status: succeeded
issue: none (Arya's ask in-session: "make our mobile terminal UI look and work like Moshi")
pull_request: https://github.com/aryateja2106/lecoder-watch/pull/133
gate_level: full
gate_status: RED on test — three reds, none of them this work (see below)
verifier: not-run (orchestrator drove every slice on the simulator against a side-port daemon; a fresh-context verify is the next step)
human_required: true
---

# Moshi parity, phase 1 — the phone terminal is a terminal

Six slices from `docs/product/moshi-parity-2026-09-22.md` §4: SwiftTerm on the phone
(`iOS/NativeTerminalScreen.swift`), `GET /agents/:name/pty` on meshd
(`install/payload/meshd/pty.ts`, `Bun.Terminal`, no new dependency), `Shared/PtyClient.swift`
streaming into it, a key bar with lockable modifiers and a d-pad, four themes, scrollback
replay, and the native terminal as the session screen's Terminal mode with the xterm.js
WKWebView and the polled text card deleted. Details and proofs in
`docs/overnight/2026-09-21/REPORT.md` ("Evening, fourth pass").

New checks: `scripts/check-native-terminal-keys.sh` (+ `native-terminal-keys-test.swift`),
`scripts/check-pty-route.sh`. No existing `scripts/check-*` or test edited. `project.yml`
gained the SwiftTerm package (pinned 1.18.0; ≥ 1.19 needs plugin validation).

**Human required:** redeploy the fleet daemons so the real phone gets `pty` (`mesh upgrade
--src` on the Mac, `mesh upgrade -H pi|jetson --src <tgz>`), then judge the terminal on the real
iPhone — gestures, the keyboard, latency over Tailscale; the Metal toolchain was installed
into Xcode on this Mac (`xcodebuild -downloadComponent MetalToolchain`).

## Gate

```
FACTORY_GATES: level=full status=RED passed=3 failed=1 failing=test skipped=none misconfigured=none
```

Full log: `docs/overnight/2026-09-21/gate-full-moshi-parity.txt`. Every check this pass touches
is green in it — `check-native-terminal-keys`, `check-pty-route`, `check-daemon-gaps`,
`check-approve-path`, `check-phone-input-and-wake`, and `check-ios-smoke: OK — the app
launches, every tab renders, and a text field can appear · iPhone 18 Pro · iOS 27.0`.

The three reds belong to the publish lane a second session is landing on the same branch
(`check-web-docs`: five `web/product/shots/iphone-*.png` its `docs/getting-started.md` embeds
do not exist yet; `check-docs-index`: that file is not in the index; `check-published`:
`PUBLISHED.md` carries `Gate SHA: pending` and names an uncommitted gate log). Reported to
that session rather than edited from here.

An earlier run of the same gate was RED on three of ours, all fixed in this pass: the two new
`DaemonCapabilities.expected` rows (that list is pinned against a literal 0.5.0 snapshot),
`ctrl-z` newly accepted by the ctrl-/alt-letter pattern, and a `check-ios-smoke` that two
sessions' `xcodebuild` runs kept killing on the one simulator it picks.

## Live fleet

The Mac and the Pi run this build: `/health` advertises `pty` and `captureAnsi` on both, no
session was lost (`pi-claude` is 18 h old and still there), and the stream was driven from a
WebSocket client against each — scrollback replay, the pane resized to the client, 38 ms
round trip to the Pi over Tailscale and 6 ms to rmux on the Mac. The Jetson was upgraded the
same way afterwards (tmux 3.2a, bun 1.4.2) and streams too — replay, 18×57, 6 ms — so all
three machines advertise `pty`. One trap for anyone writing a probe: `tmux send-keys` 0.3 s
after `new-session` is eaten by a shell that has not finished starting, which looks exactly
like "replay is broken" and is not.


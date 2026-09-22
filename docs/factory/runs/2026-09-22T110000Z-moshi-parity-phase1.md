---
run_id: 2026-09-22T110000Z-moshi-parity-phase1
stage: implement
started_at: 2026-09-22T11:00:00Z
finished_at: 2026-09-22T13:00:00Z
status: succeeded
issue: none (Arya's ask in-session: "make our mobile terminal UI look and work like Moshi")
pull_request: https://github.com/aryateja2106/lecoder-watch/pull/133
gate_level: full
gate_status: see the log line appended below
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

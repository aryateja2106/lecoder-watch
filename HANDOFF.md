# MeshWatch — Mission Control Handoff

Status snapshot + prioritized fix-list from Arya's on-device testing (2026-06-05).
The watch↔phone↔meshd loop **works** (send + receive confirmed). This doc tracks
making it genuinely usable for orchestrating terminals + coding agents.

## Architecture (current, working)
- **meshd** (per machine, bun): stats + sessions (`/agents`) + per-session `/output`,`/send`,`/new`. rmux on macOS, tmux on Linux. 0.0.0.0:8899, Bearer token.
- **rmux-bridge** (per machine, bun): live xterm WS stream. 0.0.0.0:7820.
- **iPhone app**: Machines / Terminal (WKWebView→bridge) / Usage / Settings. Polls meshd, relays to watch.
- **Watch app**: direct meshd client + iPhone-relay fallback (carries agent output). Machines→Sessions→live view + send.

## DONE this round
- [x] Terminology: "agents" → **sessions** (card shows "N sess"; list "Sessions (N)" with pane count + live badge).
- [x] Watch live view: bigger mono font (14pt), max output area, **useful commands** (ls, git status, pwd, clear, cd, mkdir, yes, continue), **tap-to-zoom** full-screen non-wrapping output with font +/- (read TUIs/diffs).
- [x] Cross-machine (Mac+pi+dataflow), curl installer (`install/`), git repo.

## FIX-LIST (prioritized)

### P0 — broken / blocks daily use
1. **Phone terminal is broken/unresponsive.** `rmux-bridge/public/index.html` xterm wraps badly, doesn't fit device width, not touch-smooth. Needs: proper viewport, fit-addon on load/resize/rotate, correct cols→tmux resize, readable font, smooth touch scroll. → owner: bridge agent.
2. **Pane navigation missing.** Splitting (split h/v, +pane) creates panes but you can't switch back/among them. Need: meshd lists *panes* per session (`list-panes`), app shows pane switcher, `select-pane`. Splits also seem to shrink/collapse the view. → owner: meshd + app.
3. **Coding-agent (claude/codex) view is unreadable on phone**; can't give instructions. Tied to #1 + needs an agent-aware output mode (last N lines, prompt detection).

### P1 — usability
4. **Phone↔watch sync** not always reliable; make relay push agent output promptly when watching (currently 6s) + show sync state.
5. **"Only the signal-icon session works."** Verify non-attached sessions stream too; attaching on open if needed.
6. **Readability everywhere**: font/real-estate pass on phone terminal + agent chat-style view (high-level messages, interrupt/redirect).
7. **Watch real-estate / TUI goal**: progressively render more of the screen; investigate horizontal-scroll TUI view (zoom sheet is step 1).

### P2 — mission control
8. Better orchestration UI: quick "new session + launch agent", session persistence visible, watch-what-agent-is-doing, human-in-loop approvals surfaced as notifications.
9. Notification sink: agent activity / waiting-for-input → push to one place.
10. On-device: real iPhone+Watch run guide; verify relay leg on hardware.

## Verify commands
- meshd: `curl -s -H 'Authorization: Bearer testtoken' http://<ip>:8899/agents`
- bridge page: `curl -s http://<ip>:7820/ | grep -i xterm`
- build: `xcodebuild -scheme MeshWatch -destination 'platform=iOS Simulator,id=<id>' CODE_SIGNING_ALLOWED=NO build` (use **scheme + destination, never -sdk** — -sdk breaks the embedded watch target)
- watch deep nav in sim needs the Digital Crown (cliclick can't scroll there) — verify deepest screens on device.

## Build gotchas (cost time, don't repeat)
- Build via **scheme + -destination**, never `-sdk iphonesimulator` (forces embedded watch → iOS SDK → WCSessionDelegate fails).
- DerivedData fragments across `-target`/`-scheme`/hash dirs → stale embedded watch. Use one `-derivedDataPath` and clean when in doubt.
- Watch sim runs the **companion-embedded** watch app; uninstall iOS app first to test a standalone watch build.
- `strings | grep` can't see Swift small-string literals (≤15 bytes) — not a valid build check.

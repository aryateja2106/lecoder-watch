# LeSearch AI vs Moshi — parity map (2026-09-22)

Legend. Ours: **W** works, **P** partial, **D** dead (exists, never reaches the user), **M** missing. Phase: 1 terminal UI on phone · 2 input/voice/clipboard · 3 sessions/home · 4 agents/chat/inbox · 5 extras/desktop/pricing/docs. Paths relative to the worktree root (`iOS/`, `Shared/`, `install/payload/`).

## 1. Gap matrix

| Area · Moshi feature | Moshi behavior | Ours today | Gap | Eff | Ph |
|---|---|---|---|---|---|
| **rendering** · Real terminal emulator | Own renderer, true colour, cursor, alt-screen | **P** xterm.js in WKWebView only (`rmux-bridge/public/index.html:195-219`, `iOS/TerminalView.swift:1467`); default peek = polled `capture-pane -p` into a SwiftUI `Text` (`TerminalView.swift:875-895`) — not an emulator | Native emulator fed by a PTY stream | L | 1 |
| rendering · Colours/ANSI | Always | **P** bridge only; meshd `/output` never passes `-e` (`meshd/server.ts:586`) | Default path is monochrome | (in L) | 1 |
| rendering · Cursor | Always | **P** bridge blinks but position wrong until redraw; peek none | Need real attach | (in L) | 1 |
| scrolling · Drag to scroll back, fixed buffer | Drag up = history, drag down = tail | **P** xterm 10k buffer wiped on every reload (`index.html:416-427`); peek = visible rows only (`TerminalView.swift:1125`) | Persistent scrollback on the phone | M | 1 |
| scrolling · Scroll past bottom dismisses keyboard | Default on, Settings→Gestures | **W** chat only (`AgentChatView.swift:262`) | Wire into terminal surface | S | 1 |
| scrolling · tmux wheel passthrough | `mouse on` → wheel events to tmux | **M** | SGR mouse encoding from emulator | S | 2 |
| personalization · Built-in themes (6 dark/4 light) | One theme recolors terminal + chrome | **M** one hard-coded palette (`index.html:212-218`) | Theme struct + picker | M | 1 |
| personalization · Custom theme import (QR/paste/deeplink JSON v1) | | **M** | JSON→theme, QR scan | M | 5 |
| personalization · Fonts (JetBrains Mono, on-demand) | | **M** system monospaced | Bundle 1 font, picker later | S | 1 |
| personalization · Custom font import (Pro) | | **M** | UIFont from .ttf | S | 5 |
| personalization · Cursor style/blink | Block/Underline/Bar | **M** | Emulator setting | S | 1 |
| personalization · Glass effect, alt icons, UI language, session layout pref | | **M** | Cosmetic | S | 5 |
| gestures · Pinch = font size | | **W** (`TerminalView.swift:900-908`, `index.html:390-409`) | Port to native emulator | S | 1 |
| gestures · Tap/double/triple-tap bindings | Default: double-tap = paste | **M** | UIGestureRecognizers on emulator | S | 2 |
| gestures · 1-finger horizontal swipe = tmux window | prefix+n/p | **M** | Send `select-window -n/-p` via daemon | S | 2 |
| gestures · 2-finger h-swipe = pane, 2-finger v-swipe = session | | **M** | Same, `select-pane`/`switch-client` | S | 2 |
| gestures · Header soft/hard drag → switcher / minimize | | **M** | Sheet + dismiss gestures | M | 3 |
| gestures · Ctrl double-tap lock, Shortcuts double-tap lock, Mic long-press PTT | | **P** sticky mods only in HTML bar (`index.html:231-272`); no PTT | Native key bar state | S | 2 |
| gestures · Gesture settings screen + Reset all | | **M** | Settings form | M | 2 |
| keyboard · Terminal toolbar (Enter/BSpace/Paste/Kbd/Shortcuts/History/D-pad) | Reorderable, Settings→Input | **P** fixed native rows (`TerminalView.swift:982-1006`, `AgentChatView.swift:559-573`); HTML bar in bridge | One native key bar: [Ctrl][Alt][Esc][Tab][Up] + mic + kbd toggle | M | 1 |
| keyboard · Ctrl/Alt/Shift sticky modifiers on any key | | **P** bridge only; native has only ctrl-c/ctrl-d (`meshd/server.ts:631-650`, 17 named keys) | Raw bytes from the emulator, drop the named-key map on the new path | S | 1 |
| keyboard · Custom shortcuts (free: 3 slots) + simple builder + advanced binding syntax (`C-b, S-t`, `text:/clear`) | | **P** quick-send strings only (`TerminalView.swift:1037-1047`) | Key-sequence parser + editor | M | 2 |
| keyboard · D-pad + corner slots | | **P** arrow buttons, no d-pad | Native view | S | 2 |
| keyboard · Hardware keyboard: Cmd+K/1-9/O/N/W/V, Option-as-Meta, auto-hide toolbar | | **P** only inside WKWebView (`index.html:411`); native surfaces have none | `UIKeyCommand` + `pressesBegan` on the emulator view (pattern in `iOS/RemoteScreenView.swift:1336`) | M | 2 |
| cjk · IME composition, chat-mode fallback, UTF-8 locale docs | | **P** native TextField composes; emulator path untested | `UITextInput` marked-text handling | M | 2 |
| voice · Engines: Parakeet, Apple SpeechAnalyzer, Whisper.cpp, Cloud | On-device, quotas | **P** SFSpeechRecognizer on-device only (`iOS/VoiceTranscriber.swift:178,259`); chat composer only (`AgentChatView.swift:515`) | Mic in terminal key bar; "Dictating…" pill; engines later | S→L | 2 |
| voice · Chat mode toggle, Auto-send, Language pin, Transcription history, Model storage | | **P** composer sheet exists (`iOS/VoiceInput.swift`); no toggle/history | Composer bubble over keyboard (screenshot) + toggle | M | 2 |
| voice · Image attachments in composer | | **M** | Needs upload path (below) | M | 4 |
| clipboard · Double-tap paste, toolbar paste, long-press selection with handles, Copy/Open link | | **P** paste button (`TerminalView.swift:955-960`); selection = SwiftUI `.textSelection` on a blob (`:881`); bridge none | Emulator selection API | M | 2 |
| clipboard · OSC 52 remote→phone clipboard | `set-clipboard on` | **M** (pipe-pane strips nothing but page ignores OSC 52) | Handle OSC 52 in emulator | S | 2 |
| security · Biometric gate on key copy / credential use | | **M** tokens in Keychain (`CredentialVault.swift`) no biometric | LAContext before reveal | S | 5 |
| media · Image paste → agent gets URL; Attach sheet (Camera/Photo/Files/Clipboard); SCP to `~/.moshi/uploads`; Files screen; short HTTPS URLs | | **M** | `POST /agents/:n/upload` → `~/.mesh/uploads/`, paste path; no cloud URL needed (tailnet) | M | 4 |
| navigation · Home / Terminal / Inbox / Settings | | **P** Machines / Terminal / Apps / Settings (`iOS/ContentView.swift:25-30`) | Home = Active sessions cards + Saved connections; Inbox tab | M | 3 |
| sessions · Session picker (tmux/Zellij/Herdr tabs) + Recent dirs | | **P** flat list by machine (`TerminalView.swift:58-96`); `/resumable` exists (`MeshClient.swift:590`) | Grouped picker; recent cwd from agent history | M | 3 |
| sessions · Session cards with thumbnails, mux badge, "just now" | | **M** only machine desktop JPEG (`ContentView.swift:1774`) | Render last `capture-pane -e` into a mini emulator snapshot | M | 3 |
| sessions · Session switcher (Cmd+O, header drag), resume last on launch | | **P** deep link only (`ContentView.swift:37-48`) | Switcher sheet + last-session restore | M | 3 |
| sessions · Auto-reattach after reconnect (Pro) | | **P** page reload loses buffer (`TerminalView.swift:1355-1359`) | New route reattaches with replay | (in P1) | 1 |
| sessions · Kill / new / split pane | | **W** (`TerminalView.swift:961-1019`) | none | – | – |
| connection · Profiles (host/port/user/auth), SSH/mosh/ET transport, Easy Pair, ≤2 saved free | | **W** different model: pairing + meshd over Tailscale (`Shared/Models.swift:28-91`) | Not a gap; we do not ship SSH. Saved-connections UI only | S | 3 |
| settings · `MOSHI_CLIENT=1` env | | **M** | `MESH_CLIENT=1` on `/agents/new` | S | 5 |
| settings · Prefix key config, hide selector | | **M** | Setting + use in swipe gestures | S | 2 |
| multiplexer · tmux/Herdr deep integration, Zellij partial | | **P** tmux/rmux full on both paths; herdr/cmux polling only (`meshd/herdr.ts`, `cmux-bridge.ts`); bridge closes 1008 on colon names (`bridge/src/server.ts:369-372`); zellij **M** | herdr live stream needs its own PTY (herdr has no pipe-pane) | L | 3 |
| multiplexer · Tab/Window 1-20 rows, tmux shortcut panel, Next/Prev buttons | | **M** | Shortcut panel view | S | 2 |
| multiplexer · `moshi .` launcher, `moshi context`, live tmux detection | | **W** `mesh` CLI (`install/payload/bin/mesh`), process-tree detection (`meshd/server.ts:196-231`) | Add `mesh .` alias | S | 5 |
| multiplexer · Deep links `moshi://tmux?session=` | | **W** `meshwatch://session` (`ContentView.swift:37`) | Add window/pane params | S | 3 |
| jump-to · Jump sheet (list/accordion/grid), tap to switch, status dots | | **P** pane Picker (`TerminalView.swift:823-832`), Needs-you rows | Sessions→windows tree from `/agents` + `list-windows` | M | 3 |
| agents · Supported agents + brand glyphs, tiers A/B/C | | **W** detection + brand colours (`AgentChatView.swift:7-52`) | none | – | – |
| approvals · One-tap allow/deny in Inbox, lock screen, Live Activity | | **W** DecisionCard + notification actions (`AgentChatView.swift:651-704`, `Shared/AgentNotifications.swift:118`) | Inbox surface | M | 4 |
| agents · Kanban (Needs you / Working / Done), decay rules, context ring, Keep Screen On | | **P** attention rows + status badges (`ContentView.swift:1023`, `SessionCard.swift`) | Inbox tab with 3 columns; context ring needs transcript stats | M | 4 |
| usages · Rate-limit rings (5h/7d), refresh, background collection, watch sync | | **P** session-limit hand-off banner only (`TerminalView.swift:1558`) | Poll `~/.claude` usage → `/usage` | M | 4 |
| chat-view · Transcript as messages, tool cards, working/stop, jump-to-bottom, composer, approval bar | Pro | **W** `AgentChatView` polled `/agents/:n/chat` (`meshd/chat.ts`) — this is our default screen | Make it the *secondary* view (agent icon in header) | S | 4 |
| hooks · Host daemon, Unix socket + WS, event categories, hook status, data boundary | | **W** meshd + `agent-events.jsonl` (`meshd/server.ts:814-826`), APNs from meshd | Add `/events` SSE later; hook status per host in Settings | S | 4 |
| live-activity · Lock screen/Dynamic Island, settings toggles, test button, event rules, API override | | **W** (`iOS/LiveActivityController.swift`) | Test button, "open inbox on tap" | S | 4 |
| hook-settings · always-on-discovery, usage-collection, suppress-nested, suppress-while-unlocked, scan-ports, `moshi-hook set` | | **P** `mesh doctor`, no settings CLI | `mesh set k v` → `~/.mesh/config` | S | 5 |
| watch · Inbox, Usage rings, mirrored push, complication, refresh, non-capabilities | View free / act Pro | **W+** we exceed: watch reads terminal text, sends keys, approves (`Watch/WatchViews.swift:895`) | Usage rings only | S | 4 |
| diff-viewer · Branch button, side-by-side, local HTTP, `moshi diff` | Pro | **M** | `GET /agents/:n/diff` → native diff view | M | 4 |
| browser-preview · Dev-server detection, picker, SSH forward | Pro | **P** Apps tab serves built apps; no dev-server probe | Port probe + in-app WKWebView over tailnet (no forward needed) | M | 5 |
| notifications · Push toggle, unified push, suppress-while-unlocked, test buttons, webhook, events endpoint, rate limits, deep links, image upload | | **W** APNs direct from meshd; **M** webhook/test/unified | Test button, generic webhook | S | 5 |
| subscription · Free/Pro tiers, App Store/Play/Stripe, 3-device license | | **M** no paywall, no StoreKit | StoreKit 2 + tier flags | L | 5 |
| cli · `moshi pair/install/serve/status/logs` | | **W** `mesh` covers all (`install/payload/bin/mesh`, `mesh-self-check`) | none | – | – |
| skill · Agent skill package (`npx skills add`) | | **W** `.agents/skills/` in repo, not published | Publish `mesh-skill` | S | 5 |
| docs · Docs site, Learn, Compare, Themes, Pricing | | **M** landing only (`web/`) | Docs from `docs/` | M | 5 |

Honest summary: of ~120 Moshi features, we are W on ~22, P on ~30, M on the rest. Every P in rendering/input shares one root cause: the phone has no terminal emulator and no PTY stream; it has a polled text blob and a web page.

## 2. Our differentiators Moshi lacks (keep)

- Remote screen control: full Mac/Linux desktop peek + pointer/keyboard from phone and watch (`iOS/RemoteScreenView.swift`, meshd `screenPeek`, Linux xdotool).
- Watch as a first-class client: read output, send keys, approve, dictate, complication + relay over WatchConnectivity.
- Mesh Apps: OTA install of dev-signed apps to the phone over Tailscale Serve (`/built-apps`, `mesh apps`).
- Knowledge base: meshd SQLite-FTS5 KB + `mesh kb` + `/search`.
- Feedback reporting, stats, power/battery, launcher presets (`/doctor` launchables), session-limit hand-off between agents (`/handoff`).
- Secret redaction + exposure ledger on every byte path (`meshd/redact.ts`).
- No SSH, no accounts, no cloud relay: pairing + tailnet is the whole setup. Moshi needs SSH keys and their server for push/uploads.

## 3. Phase-1 architecture decision

**What Moshi does:** native SSH/mosh client in the app, its own terminal renderer (Swift), bytes flow PTY→mosh→renderer. No polling, no web view.

**Options:**
- (a) **Native emulator + real PTY stream.** SwiftTerm via SPM in `project.yml` (`TerminalView`, UIKit, ~5 years mature, handles VT100/xterm, OSC 52, SGR mouse, selection, hardware keys). Daemon side: new WebSocket route that runs `tmux attach -t <s>` inside a real PTY sized per client. Verified today: bun 1.3.14 has `Bun.spawn({terminal:{cols,rows,data}})` + `proc.terminal.resize()` (probe gave `/dev/ttys005`). Zero new payload deps.
- (b) Keep xterm.js in WKWebView and skin it. Cheapest visually, but keeps every structural fault: iOS keyboard owns text entry, HTML buttons steal focus, page reload on every sleep loses history, colon-named sessions unattachable, no native gestures, no hardware-key commands, one `send-keys` subprocess per key.
- (c) Keep polling. Never becomes a terminal (no cursor, no colour, 0.5–2 s echo).

**Recommendation: (a).** It removes the two dead ends (WKWebView, capture-pane text) in one move and is the only option that reaches the screenshots.

Concrete route:
- **Route:** `GET /agents/:name/pty?pane=%N&cols=&rows=` on meshd :8899 (not the :7820 bridge — the bridge's `nc -U` + pipe-pane stays for now, retired in slice 6). Bun.serve `upgrade`. Capability flag `"pty"` in `/health` so old daemons fall back to polling.
- **Auth:** `Authorization: Bearer <MESHD_TOKEN>` on the upgrade request — `URLSessionWebSocketTask` can set headers, so the `mesh_token` cookie hack dies. Reuse the existing bearer check; loopback trust rule unchanged.
- **PTY:** per client `Bun.spawn(["tmux","attach-session","-t",target], {terminal:{cols,rows,data:(_,buf)=>ws.sendBinary(buf)}, env:{TERM:"xterm-256color", COLORTERM:"truecolor"}})`. Per-client size means the desktop window is no longer resized (tmux `window-size latest` or `aggressive-resize on` set on attach). rmux on macOS: verify it accepts `attach-session` under a PTY the same way; otherwise use tmux on Mac too (installed).
- **Wire protocol:** binary frames = raw PTY bytes both directions (phone→daemon: keystrokes, paste, OSC responses). Text frames = JSON control: `{"t":"resize","cols":..,"rows":..}`, `{"t":"ping"}`/`{"t":"pong"}` every 15 s, `{"t":"error","msg"}`. Redaction: run the existing line-wise redactor on the output stream (same 40 ms hold as the bridge).
- **Reconnect:** phone reconnects with backoff (0.5→8 s) on close or foreground; SwiftTerm buffer is kept, daemon sends `capture-pane -p -e -S -2000` once on attach as a replay, then live bytes. Attach is cheap, so no server-side session cache in phase 1 (`ponytail:` add ring buffer + `?since=` if replay flicker is visible).
- **Existing paths:** `/output` polling and `/send` stay untouched — the watch keeps capture-pane text (no emulator on watchOS), chat view keeps `/chat`, Live Activity keeps last-line. SessionPeekScreen's default mode becomes the native terminal; chat is the header-icon secondary view. BridgeTerminalScreen and ManualBridgeScreen are deleted once slice 6 lands.
- **Constraints met:** no `bun install` change (Bun.Terminal is built in); SwiftTerm added as one `packages:` entry in `project.yml`, xcodegen regenerates.

## 4. Phase-1 build order (each ≤400 lines, each with a proof)

1. **Native terminal screen, static.** Add SwiftTerm SPM to `project.yml`; new `iOS/NativeTerminalScreen.swift`: full-bleed dark `TerminalView`, header (session name · agent glyph · mux badge), bottom key bar [Ctrl][Alt][Esc][Tab][Up] + mic + kbd toggle, JetBrains Mono-ish font, feed it the existing `/output` lines with `-e` (one-line meshd change: pass `-e` when `?ansi=1`). Proof: `scripts/check-native-terminal-smoke.sh` boots the sim, opens a session, screenshots, asserts SwiftTerm view present and coloured glyphs rendered (pixel sample ≠ white). Visibly Moshi-like on day one.
2. **meshd `/agents/:name/pty` route.** Bun.Terminal attach, bearer auth, resize/ping JSON, capability `"pty"`. Proof: `scripts/check-pty-route.sh` — `bun` websocket client sends `echo $COLUMNS x $LINES`, asserts echoed size equals requested, asserts 401 without bearer, asserts colour SGR bytes present.
3. **Phone WebSocket client → emulator.** `Shared/PtyClient.swift` (`URLSessionWebSocketTask`, bearer header, backoff reconnect, ping) feeding `TerminalView.feed`; `TerminalViewDelegate.send` → binary frames; resize on layout. Proof: sim test types `ls` via key bar and asserts the listing appears within 300 ms (latency gate), plus airplane-mode toggle in `check-pty-reconnect.sh` asserting buffer survives.
4. **Key bar semantics.** Sticky Ctrl/Alt (double-tap lock), Esc/Tab/arrows, kbd toggle, pinch font size, scroll-past-bottom dismiss. Proof: sim test sends Ctrl+C to a `sleep 100` and asserts the prompt returns.
5. **Replay + scrollback + themes.** `capture-pane -e -S -2000` replay on attach, 5000-line SwiftTerm scrollback, `Theme` struct with Moshi/Dracula/Nord + cursor style, `@AppStorage`. Proof: `check-pty-route.sh` asserts replay contains lines older than the screen; sim screenshot per theme.
6. **Make it the default and delete the old.** SessionPeekScreen opens native terminal; chat behind header icon; remove BridgeTerminalScreen/ManualBridgeScreen/BridgeWebView; keep watch untouched. Proof: `scripts/check-ios-smoke.sh` still green, `grep -c WKWebView iOS/TerminalView.swift == 0`, `check-bridge-*.sh` retargeted or retired with the human's OK (they are existing check-* scripts — do not edit unattended).

## 5. Verify before coding

- SwiftTerm: latest tag, builds against Xcode 26 / iOS 26.0 target; project is `SWIFT_VERSION 5.0` (not Swift 6 strict) so concurrency warnings will not block — confirm no `Sendable` errors when wrapped in `UIViewRepresentable`; check it exposes selection, OSC 52, SGR mouse, `feed(byteArray:)` and `resize`.
- Bun: `Bun.Terminal` present on the *installed* bun of pi and jetson (aarch64 Linux), not only this Mac; verify `proc.terminal.resize()` delivers SIGWINCH to tmux; verify PTY data callback back-pressure with a `yes` flood.
- tmux/rmux: tmux version on pi, jetson, Mac (need ≥3.2 for `capture-pane -e`, `-S -N`, `window-size latest`); whether rmux 0.3.1 supports `attach-session` under a PTY and `window-size`; decide tmux-on-Mac vs rmux for the attach path.
- herdr/cmux: whether `herdr` can hand out a PTY attach (else herdr stays polling in phase 1).
- iOS: `URLSessionWebSocketTask` header set on upgrade works against Bun's `server.upgrade` (Sec-WebSocket-Protocol not required); ATS `NSAllowsArbitraryLoads` still covers `ws://` on iOS 26.
- Redactor throughput at PTY byte rates (currently line-wise on the bridge).
- Installer: launchd/systemd meshd unit passes `TERM`; `Bun.spawn` under launchd has a controlling-tty-free environment (openpty still works headless — verify on jetson).
- Fonts: license for JetBrains Mono bundle (OFL, fine) and size impact.

## 6. Verified on 2026-09-22 (this session, before the map was written)

- `Bun.Terminal` pty: bun 1.3.14 on Mac and pi, 1.4.2 on jetson. Probe: `new Bun.Terminal({cols:60,rows:12,data})` + `Bun.spawn([...], {terminal})` → `stty size` printed `12 60`, SGR colour bytes passed through, `terminal.resize(80,24)` returned. Zero new payload deps.
- tmux: 3.6a Mac, 3.4 pi, 3.2a jetson (all ≥ 3.2 → `capture-pane -e`, `-S -N`, `window-size latest`).
- `Bun.serve` already hosts meshd (`install/payload/meshd/server.ts:1273`) → ws upgrade is a handler addition, not a new server.
- SwiftTerm: v1.19.0 (2026-08-18), MIT, swift-tools 6.2, iOS sources present, repo pushed 2026-09-19 (1.7k stars). Still to verify: builds under our Xcode 27 / iOS 26 target when added through `project.yml` `packages:` (xcodegen).
- Moshi docs read: 41 pages, 163 features extracted; our stack: 55 capabilities located with file:line.

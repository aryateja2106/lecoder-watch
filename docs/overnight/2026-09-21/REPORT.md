# Overnight 2026-09-21 → 22 — report for the morning

*Branch `feat/lesearch-ai-overnight-2026-09-21` (worktree `.claude/worktrees/lesearch-ai-overnight`, cut from
`chore/codebase-map-and-regression` + PRODUCT.md from PR #128). Nothing merged, nothing pushed to main. Plan:
`~/.claude/plans/check-the-devices-we-prancy-yeti.md`; resume state: `STATE.md` beside this file; one run record per slice
under `docs/factory/runs/2026-09-21T*-overnight-*`.*

## The fleet, this morning

| Machine | Before | Now |
|---|---|---|
| Mac | meshd 0.6.0 live (release build) | **branch build** on :8899 (`mesh upgrade --src`, backup at `~/.mesh/backups/meshd-0.6.0-1790020360`, auto-rollback armed); `mesh cp` / `mesh kb` in the installed CLI; edge0-8b served on :8001 |
| Raspberry Pi 5 (`pi`, user `arya`) | meshd **0.2.0**, weak default token | **0.6.0 branch build**, token rotated (re-pair the phone), systemd unit enabled, screen peek works, ollama qwen3:1.7b |
| Jetson Orin Nano (`jetson`, user `aryateja`) | **no meshd** | **0.6.0 branch build**, systemd unit enabled + linger, screen peek works (3440×1440), `claude` on the service PATH, ollama qwen3:4b (CUDA) |

`mesh status` → mac / pi / jetson all `meshd 0.6.0`, doctor 7/7 on each. From the Mac CLI: an Antigravity agent on the Pi did a
task inside a mesh session, posted Started/Completed events (the notify path), and `mesh cp` brought its file to
`~/Downloads/hello-from-pi.txt` on the Mac and to the Jetson.

## What landed (each with a new check, each committed only when green)

| # | Slice | Commit | Check | Proof |
|---|---|---|---|---|
| S1 | Fleet online; **Linux screen peek** (scrot); service PATH fix | 4a2a151 | `check-fleet.sh` | `mac/pi/jetson … screen ok`; `shots/jetson-screen.jpg`, `pi-screen.jpg` |
| S2 | iPhone + iPad (compat) + paired Watch + MeshDesktop alive at once; watch smoke (T26) | 4a2a151 | `check-sim-fleet.sh`, `check-watch-smoke.sh` | `shots/iphone*.png`, `ipad.jpg`, `watch*.png`, `mac-menubar.png` |
| S3 | **Rename to LeSearch AI**; app version 0.6.0 = daemon (T02, T15) | c7a3011 | `check-brand.sh` | built plists say LeSearch AI / 0.6.0 on all three targets |
| S4 | Remote agent loop on a Linux host | 4a2a151 | `check-remote-agent-loop.sh` | green on jetson and pi; real agy task on the Pi |
| S5 | **`mesh cp host:path host:path`**, `POST /fs/write`, `/fs/read?raw=1` | 86ae97e | `check-cross-host-cp.sh` | live on jetson and pi, sha256 verified |
| S6 | **Relay receiver + honest acks** (ARCH-01/02, T06/T07) | 473d40e | `check-relay-receiver.sh`, `check-relay-ack.swift` | builds green; physical pair needed to see it live |
| S7 | Harness picker reads the machine's real CLIs; one catalogue in the daemon | b6ddc7e | `check-harness-picker.sh`, `check-launchable.swift` | Pi shows claude/cursor-agent/agy/hermes, Jetson claude |
| S8 | **`mesh kb` + `/search` `/remember` skill**; federation proven | 912c966 | `check-kb-federation.sh` | note on the Jetson found from the Mac |
| S9 | `/brain` route; ollama on both Linux boxes; **edge0-8b tool calling** (our patch); **Needle 2 measured** | 86ae97e, 1cc9681 | `check-brain.sh`, `check-intent.sh` | table in the ADR |
| S10 | `loopback-trust.ts` + `MESHD_TRUST_LOOPBACK=0` kill switch covering `/pair/new` (SEC-03, **opt-in** — default kept because `check-token-rotate.sh` mints tokenless) | 95d6406 | `check-pair-auth.sh` | trust off: tokenless mint 401, `mesh pair` still works |
| S11 | Aggregate `check-overnight.sh` (all live halves green); codemap; **`FACTORY_GATES: level=full status=GREEN passed=4 failed=0 failing=none skipped=none misconfigured=none`** | e3f737a, 4a17d9d | `check-overnight.sh` | `check-overnight-run1.txt` |

## Numbers worth knowing

- **Needle 2** (14 MB, on-device intent): 26/28 wrist phrases → right daemon call after description tuning (20/28 cold), 22/28 with every argument, ~0.7 s, 34 MB RAM on the Mac; 224 tok/s on the Pi. Remaining misses = argument extraction → fine-tune is the next slice (`intent/cases.jsonl` is the suite, `check-intent.sh` the floor).
- **edge0-8b** on the Mac: ~11 tok/s warm, 3.8–4.1 GB RSS, a correct OpenAI tool call in 3.8 s — **only with our patch** (`references/patches/0002-edge0-openai-tool-calls.patch`; upstream ignores `tools`). edge0-35b not run (23 GB, 13 GB free).
- **ollama**: Jetson qwen3:4b tool call in 12 s (~11 tok/s, needs `OLLAMA_CONTEXT_LENGTH=2048` on 8 GB and `/no_think`); Pi qwen3:1.7b 23–40 s.
- Decision proposed in `docs/adr-2026-09-22-local-brains-and-streaming-moe.md`: Needle for intent everywhere; edge0/ollama fronted by `/brain`; **no own streaming-MoE engine before launch**.

## Found tonight, not fixed (honest list)

1. **`claude` is not logged in on the Jetson or the Pi** (OAuth expired) — `claude /login` needs a browser. `agy` and `cursor-agent` on the Pi are authenticated and were used for the proof.
2. **`mesh new --task` loses the task when the agent starts slowly** — the daemon types it after a 1.2 s readiness poll; bash on the Jetson and Claude Code's trust prompt both take longer, so the typeahead is discarded. Re-sending with `mesh send` works. Fix belongs in `server.ts` `/agents/new` (wait for a prompt); serialized file, deferred.
3. **The simulator loses paired machines on every `simctl install`** of an unsigned build (Keychain items become inaccessible). Simulator/unsigned artefact — on a real iPhone the Keychain survives even delete-and-reinstall (measured 2026-08-28). Re-pair the sim with `xcrun simctl openurl <udid> "$(mesh pair --json | jq -r .url)"`.
4. **The watch simulator is stuck on the notifications permission alert** (still titled "LeSearch Mesh" — the system caches the name) and Claude has no tap access to that device. Tap Allow once, or grant the device in the simulator panel.
5. `agy --print` writes into its own scratch workspace unless `--add-dir <cwd>` is passed; and `--print` must be the last flag.
6. `mesh` over a non-interactive ssh fails with `/usr/bin/env: 'bun': No such file` until `~/.bun/bin` is on PATH (the installer only edits the interactive rc).
7. `check-mesh-skills.sh` hardcodes **4** skills, so the new `mesh-knowledge` skill is staged under `share/skills-staged/` (README there) — promoting it is a one-line test edit that needs you.

## Morning TODO (your hands)

1. **Read this branch** — draft PR https://github.com/aryateja2106/lecoder-watch/pull/133 and the STATE.md gate line; land the stack #124 → #131 → this.
2. `claude /login` on the Jetson and the Pi (browser).
3. **Re-pair the phone to `pi`** (token rotated): `mesh pair -H pi` on the Pi or scan its QR.
4. **Physical iPhone + Watch**: confirm S6 — from the watch, with Wi-Fi off on the watch so it relays, open a screen peek and start a session; a failed command must show a reason, not a tick (T06/T07/T21).
5. Tap **Allow** on the watch simulator's notification alert (or grant Claude the device).
6. Promote `share/skills-staged/mesh-knowledge` → `share/skills` and bump the count in `scripts/check-mesh-skills.sh` to 5.
7. Decide the `/pair/new` default (flip needs a one-line edit in `check-token-rotate.sh` so it sends the bearer) and: iPad `TARGETED_DEVICE_FAMILY "1,2"` (App Store listing consequence), the Mac `.app` filename (still `MeshWatch.app`), app-icon regeneration for the new name.
8. TestFlight: `MESH_ALLOW_VERSION_DOWNGRADE=1 sh scripts/release-testflight-asc.sh --external` (Keychain dialog), then publish meshd 0.6.0 to mesh-install (`sh scripts/release-mesh-install.sh --publish`) and `mesh upgrade -H pi/jetson` from the release.
9. Wire the live halves (`scripts/check-overnight.sh`) into CI or a nightly on this Mac — CI has no fleet.
10. Telegram notify did not go out: no `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` in `~/.config/secrets.env` and no `~/.alook/bin/notify-arya` — add the two exports (vault-managed) if you want the `notify` skill to work. The report and screenshots were sent to you as files instead.
11. Turn off tonight's installer share when done: `tailscale serve --https=8890 off`; `pkill -f "http.server 8897"`; stop edge0 (`pkill -f "edge0 serve"`).

## Screens

`shots/`: `iphone-machines-paired.png` (fleet adopted via the pairing deep link), `iphone-home-lesearch-ai.png`, `ipad.jpg` (compat mode), `watch*.png`, `mac-menubar.png`, `jetson-screen.jpg`, `pi-screen.jpg`.

---

# Morning 2026-09-22 — usability pass (Arya's review of the night)

*Same branch, commits 76fb865 → 6a288d3. Fleet redeployed from the worktree (mac / pi / jetson all 0.6.0, 28 caps). Live run: `check-morning-run2.txt` beside this file.*

## Verified fixed (each measured before and after on the fleet + simulators)

| Complaint | Root cause | Fix | Proof |
|---|---|---|---|
| "I tapped Approve and Claude never got it" / "never saw Allow/Reject" | Three things. (1) `/agents` rows never carried the agent's `sessionId`, and the phone matches an event to a row by id FIRST and never by name when the event has one — so no row ever owned a Claude Code event and the *Needs you* card could not appear. (2) The phone adopted the Pi as `pi` from the Mac's hosts.json while its daemon says `arya-pi`; `hostNamesMatch` has no rule for that, so the machine lookup returned nil before the id match ran. (3) A key aimed at a pane the mux could not resolve vanished into discarded stderr and answered `ok:true`. | daemon stamps `sessionId` on rows; `snapshotMachineMatching` also matches the hostname `/stats` reports; pane sends retried on the session, real failures reported | `check-approve-path.sh`, `check-attention-hostname.swift`; live: prompt on the Pi → *Needs you* row + bell badge → Continue → `/tmp/approve-test-3.txt` written |
| Monitor full of "Claude stopped" nobody asked for | claude-mem's observer session posts a Stop per turn of every real session | dropped at ingest (cwd under `/.claude-mem/`) | `check-approve-path.sh` |
| Watch "Continue" typed `continue` into bash | sent unconditionally | only for coding-agent sessions, with "Types 'continue' into Claude" under it | build + code review (watch-sim tap-through was unreliable this morning — see below) |
| Power lists disagree phone vs watch; Linux lacked sleep / screensaver | two hand-written lists | one `Shared/PowerActions.swift`; Linux gains `sleep`, `screensaver`, `screenshot`; Mac gains `screenshot` (PNG to clipboard, for handing to an agent) | `check-linux-desktop.sh` live on pi + jetson |
| Linux: no app list; clipboard write hung 15 s | apps were macOS-only; xclip's forked child held the daemon's pipe | `/apps` from the X client list (xprop), activate via xdotool; clipboard 30–50 ms | `check-linux-desktop.sh` live |
| Web console dead | browsers stamp `Origin` on same-origin POSTs → every click 401'd; AND the phone reloaded the page on every store poll (`web.url` is nil until commit) | same-origin recognised; compare against the requested URL | console streams frames and posts clicks from the phone (Pi verified) |
| Terminal: scroll to the bottom for everything, no font size, key bar noise, keyboard pops up | read-only card stack with no scroll anchor; xterm `fontSize:12` hard-coded, `term.focus()` after every bar tap | output first + `.defaultScrollAnchor(.bottom)` + follows unless you scrolled up; A−/A+ and pinch (persisted, shared with the xterm page); keyboard toggle; rare keys under ⋯ | built, on the sim |
| No multi-line, no paste, no Shift+Tab / Shift+Enter | single-line composer; daemon key list lacked them | multi-line composer (Return = newline), paste button, one bracketed paste + Enter; daemon `shift-tab` (BTab) and `shift-enter` (M-Enter = ESC CR, verified inside Claude Code on the Pi) | `check-approve-path.sh`; `mesh key pi-claude shift-tab -H pi` cycled the mode live |
| Apps as a toolbar afterthought; Monitor in the tab bar | — | Machines · Terminal · Remote · **Apps** · Settings; Monitor = bell on every tab with the waiting count; bar minimises on scroll | on the sim |
| Machine page leads with seven green ticks | — | Screen & control + Files first, sessions tappable, Setup = one line that opens only when red, Diagnostics collapsed | on the sim |
| Which device is an app for? Is it installed? | no data | daemon reads the bundle (UIDeviceFamily / SupportedPlatforms / embedded Watch app) → iPhone/iPad/Watch/Mac/Vision glyphs; an app with a URL scheme gets **Open**, and iOS refusing the open is the honest "not installed here" | Apps tab on the sim |
| Education | — | Guides (pairing, Developer Mode on iPhone and Watch, signing team, Mac permissions, Linux desktop, overnight agents) from Settings and the empty states | on the sim |
| **Sessions vanished after an upgrade** (found this morning) | systemd's cgroup kill took the tmux server with the daemon | `KillMode=process` in the unit; applied live on both boxes | Pi: 1 session before upgrade, 1 after |
| `mesh pair -H pi` minted a code for the Mac | `-H` ignored | says where to run `mesh pair` (the daemon only mints on itself, by design) | CLI |

## Honest answers to the questions

- **Can I watch a video on the Mac from my watch?** No, and not close. Measured: the daemon produces a frame in ~135 ms on the Mac (`screencapture` + `sips`), ~170 ms on the Jetson → a hard ceiling of ~7 fps before the network; the phone polls sequentially every 350 ms (~2.5 fps), the watch every 2 s (0.5 fps), JPEG, no audio. Video needs a different pipeline: ScreenCaptureKit → H.264 (VideoToolbox) → HLS from the daemon → AVPlayer on the watch. That is a real slice (1–2 days), not a tweak; nothing of it exists yet. What DID improve: Linux frames now honour `width` (78 KB → 2 KB at 400 px), so the watch decodes 30× less.
- **fx + Jev.** `fx` 0.0.10 is installed on the Mac and listed in the harness catalogue (it appears in New Session once the doctor sees it on a machine's PATH). `AI_GATEWAY_API_KEY` is in `~/.config/secrets.env` (the key was pasted in chat — rotate it when convenient). Two blockers on your side: the gateway answers `customer_verification_required` until a card is on the Vercel team (unlocks the free credits), and **Jev is an `evaluation` model, not a chat model** — `fx` cannot drive it as its agent brain, and `typesafe-ai/jev` is absent from `fx models`. Jev's place in this product is the daemon's decisions: "is this event actionable?", "how risky is this command?" (`RiskClassifier`), "which tool does this wrist phrase mean?" (`intent/`), meeting transcript → task list. None of that is wired yet.
- **Transcripts → tasks → Google Tasks / Reminders.** Not built. The shape: `mesh kb put` the transcript, a Jev pass (Choice per segment: task / decision / question / noise; Noul: is it for me) and an `EventKit` reminder write from the phone. Post-launch.
- **Quick-action sounds on the Mac with nothing visible.** The watch's Quick grid sends chords (⌘Space, ⌃↑, F11, ⌘⌥Esc…) through `/input` and the helper has no reply channel — an unbound chord makes the frontmost app beep. Not changed; tested nothing on your live Mac, as asked.

## Needs your hands

1. **Re-pair the phone (and the watch) to `pi`** — its token was rotated again this morning because a `cat` of the unit file printed it into this session's log. `mesh pair` on the Pi, scan.
2. Vercel: add a card to the AI Gateway team if you want fx/Jev to answer at all.
3. Rotate the gateway key you pasted in chat (`vck_…`), then update `AI_GATEWAY_API_KEY` in `~/.config/secrets.env`.
4. Watch: this morning's tap-through on the watch simulator was unreliable (taps landing late or on the wrong row); the Session-screen Continue gate and the new System list are built and reviewed, not tapped. A real wrist check takes a minute.
5. The rest of the night's TODO above still stands (TestFlight, skill promotion, `/pair/new` default, CI wiring, installer share cleanup).

## Morning, second pass (63487c0 →) — after Arya's second review

| Ask | Done | Proof |
|---|---|---|
| Arrows + Enter into the agent from the phone and the watch; the trust prompt / permission list as something tappable | **Choose card** on the phone and **Choose section** on the watch: the menu is read off the pane (`AgentMenu`, fixtures from real captures), options are buttons, the highlighted one marked; a tap sends the cursor moves then Enter in order. Key strip gains Enter; watch gains ↑ ↓ Esc ⇧Tab and a prominent "Type or dictate" | `check-agent-menu.swift`; the trust prompt on the Pi answered from the phone's Choose card (claude then at its prompt in `~/trust-probe`); watch: build + parser check — sim taps still unreliable, wrist check needed |
| Zoom inside the terminal, not around it | Terminal mode is a fixed-height viewport that scrolls both ways, never wraps, pinch inside the black box | on the sim |
| Screen closes when the mouse moves right | The trackpad's pan refuses to run with the navigation edge-swipe and requires it to fail; edge drag to the right now moves the cursor | reproduced, then fixed, on the sim against the Pi |
| Web console pointless; more fps | Web console row and the Remote tab removed; frames requested back-to-back (was a 350 ms nap per frame). Daemon ceiling unchanged (~135 ms/frame Mac, ~170 Jetson); phone rate not re-measured | — |
| Screen control from Machines; preview of each machine | Every Machines row carries a live thumbnail (daemon-scaled 320 px, every 5 s while visible) that opens Screen & control; four tabs | on the sim: pi / Mac / jetson thumbnails live |
| App icons; install indication | Icons from the machine's token-free app folder; the earlier Open/"on this iPhone" stays | on the sim |
| Repeatable hook workflow for claude, fx, cursor-agent, agy, pi | `docs/agents/harnesses.md`: adapter matrix, 6-step onboarding, ranked gaps with files, prompt-detection spec. Closed today: Claude notification types (sign-in/quota no longer buzz), Stop bodies, cursor relabel + transcript slug (measured), agy Stop hook via `mesh hooks install`, fx sessions start in `ask` mode | dry-run probes in the commit; hooks installed on this Mac; fleet redeployed |
| References + local models on every device | `references/reference-projects.md` (mobilecode, Apple-Watch-Edge-AI, flash-moe, Needle 2, fx, Edge0, Jev, Desert Ant) and `docs/adr-2026-09-22-on-device-brain.md` — Needle as the on-device tool caller over the app's own functions, Jev daemon-side, llama.cpp-on-watch as a recipe; first-slice done criteria and budgets. **Not built yet.** | docs |

Not done, said plainly: configurable shortcuts/aliases fired from the watch (the Quick grid and Keyboard sheet exist; no alias editor); pi and cursor hook installers (spec'd in harnesses.md §C); fx/cursor/agy prompt regexes beyond what a captured pane proves; a real fps measurement of the new pump; the on-device brain itself.

## Afternoon, third pass (e16610b → 758a6d1) — after Arya's third review; **0.8.0 beta**

| Ask | Done | Proof |
|---|---|---|
| Linux + Mac keyboard layouts, active states, shortcuts | Key bar shows the machine's modifiers (⌘⌥⌃⇧ / Ctrl Alt Super), held key filled orange; chords menu (⌘space ⌥space ⌘tab ⌘w ⌘q ⌘⇧2 ⌘⇧4); one tap for the launcher and a terminal; a search sheet over running + installed apps (Linux lists `.desktop` apps and launches them) | Pi from the phone: Ctrl held → `l` cleared the shell; rofi opened and filtered to "Calculator"; Text Editor launched by name; sticky ⌘+q closed baobab |
| Two-finger click = right click | Was already wired; verified: context menu opened on the Pi | screenshot |
| Recenter pointer flaky | Root cause was Linux dropping absolute `moveTo` (the pointer was drawn centred, the machine's never moved) — fixed in 473eafa; Mac unaffected | `xdotool getmouselocation` = 960,540 after recenter |
| Hold-then-move selects | That is drag mode by design (long-press = mouse down). Left as is; judge on the real phone | — |
| Two repetitive ⋯ menus | Capsule ⋯ = pointer actions + terminal; title-bar ⋯ = clipboard, windows, hide | on the sim |
| Multiple displays | Two pictures, not one wide one — chips at the top switch; the daemon captures per display and a side-by-side composite halves what a phone can read | Mac (Main + Display 2) on the sim |
| System stats with charts | Gauges on the machine page (memory / disk / CPU) + "N more agents fit" (free memory ÷ 700 MB, 1 GB kept), tap → last-minute line chart, heaviest processes | on the sim, live from /stats |
| Session-limit → another agent | Banner in the session when Claude's limit blocks and another installed agent has room; one tap hands off (HANDOFF.md, existing route) | built; the limit itself was not hit during the session, so not driven live |
| Feedback / issues | Settings → Report a problem: your words + a redacted Markdown bundle you read first; share, or save to `~/.mesh/feedback/` on a machine | `check-feedback-redact.swift` (8 patterns, 6 secrets removed) |
| Live notifications "not working" | Found: `Activity.request(pushType: .token)` throws on any build without the aps-environment entitlement (every unsigned sim build) and was swallowed by `try?` → no card, no line to point at. Now retries without push, records the refusal. **The Dynamic Island shows "Claude · pi-claude · Needs you · 3/4 machines online" on the signed build.** The lock-screen platter renders empty on the *simulator* (WidgetRenderer) — not the view. On your phone: if the card never updates once the app is closed, the daemon needs its APNs key (`~/.mesh/apns`, `laPush`); the card itself has no buttons by design (tap → session; Approve lives on the notification) | logs + island screenshot |
| Build an app through mesh, test it, widgets | **Hundred** (`~/Projects/hundred-days`, committed): 100-day challenge Sep 22 → Dec 31, check-in, journal, calendar, overview, lock-screen + home-screen widgets. Built by codex inside mesh session `hundred-days` (visible on the phone), built/installed/driven by me on the sim: Day 1 ✓, journal saved, the systemSmall widget added to the home screen reading the App Group snapshot. Registered with `mesh apps` → appears in the Apps tab. **fx + Jev could not do this:** the gateway answers `customer_verification_required` (needs a card on the Vercel team) and Jev is an evaluation model, not a code generator | screenshots; `git log` in hundred-days |
| Invite a friend | v1 shape only: a deep link configures the same challenge on the other phone; no sync yet (CloudKit share is the phase-2 route and needs the container on the team) | README |
| Update my real iPhone | 0.8.0 device build (Apple Development, team B5B87F7AXF) registered as the `meshwatch` OTA app and served over Tailscale — on the phone: **Apps tab → LeSearch AI → Install**, or `mesh apps list` prints the install page. The phone was not reachable by devicectl (no cable / not on this Wi-Fi); plug it in and `mesh apps install meshwatch` works too | install page 200, manifest served |
| 0.8 | app 0.8.0 (build 2) == daemon 0.8.0; fleet mac/pi/jetson upgraded; remote `mesh upgrade -H` fixed on the way (it dropped `--src`) | `mesh status` |

Not done, plainly: a Raycast-class launcher of our own (the machine's own launcher is one tap; ours is the `/apps` search sheet); configurable shortcut sets per user; the on-device brain; VNC credential flow; plugin route loader; CloudKit sync for Hundred; a real-phone pass on gestures/haptics.

## Evening, fourth pass — Moshi parity, phase 1 (6511d50 → ) — after Arya's "make it look and work like Moshi"

The map: `docs/product/moshi-parity-2026-09-22.md` (163 Moshi features from 41 docs pages
against 55 of ours; root cause of every rendering/input gap: no emulator, no byte stream).

| Slice | Done | Proof |
|---|---|---|
| 1 Native terminal screen | SwiftTerm 1.18 via SPM; colour, cursor, full-bleed dark, Moshi-like key bar; `/output?ansi=1` (`capture-pane -e` + cursor cell, capability `captureAnsi`); keystroke bytes → `/send` through `Shared/TerminalKeyRouter.swift`; meshd resolves `ctrl-`/`alt-` letters; sends serialised (they overtook each other: "ehco") | `check-native-terminal-keys.sh` (22 router cases); sim: coloured Claude-style screen, 35 chars typed in order, sticky Ctrl+c killed a sleep — `shots/native-terminal-colour.png`, `-keyboard.png` |
| 2 `/agents/:s/pty` | WebSocket, `tmux attach` under `Bun.Terminal` sized to the client (bun ≥ 1.3, no new dependency), binary = bytes, JSON = resize/ping, redacted on the bridge channel, SIGWINCH after resize (Bun's resize alone never reached tmux), 2000 lines of scrollback replayed first; capability `pty` | `check-pty-route.sh`: 401 without bearer, 404 unknown session, `stty size` echoes the client size, SGR bytes intact, resize changes the pane, pong, replay, close detaches and the session survives |
| 3 Phone stream | `Shared/PtyClient.swift`: bearer on the upgrade, bytes → `TerminalView.feed`, keystrokes raw with Ctrl/Alt folded in, resize on every layout change, 0.5→8 s backoff | sim: tmux resized the pane to 46×38 on attach and again under the keyboard; 47 chars in order; Ctrl+c; daemon killed and restarted → reattached in 1 s — `shots/native-terminal-stream.png` |
| 4 Key bar | Ctrl/Alt tap-once / tap-twice-to-lock (lock glyph); ↑ tap = Up, hold = d-pad row (← ↓ → ⏎ ⌫ PgUp PgDn), the hold's release no longer also sends Up | sim |
| 5 Themes + scrollback | Moshi / Dracula / Nord / Paper from the palette menu, applied live, remembered; Clear screen | sim: Dracula background sampled `(40,42,54)` |
| 6 Default + delete | Terminal mode of the session screen **is** the native terminal, full screen, tab bar hidden; pane picker / Control screen / VNC / paste / new–kill pane / kill session in the ⋯ menu; `BridgeTerminalScreen`, `BridgeWebView`, `ManualBridgeScreen`, the output/controls/presets cards and `import WebKit` deleted from TerminalView.swift (−~500 lines); idle-timer hold moved to the session screen (the existing check still counts it) | `check-native-terminal-keys.sh` pins no WKWebView in TerminalView.swift; sim: menu, d-pad, theme |
| The red check from the handoff | Named at last: the full gate's `test` was **three** checks, not one. `check-phone-input-and-wake` (`FeedbackView.swift:24` TextField without `.shellSafe`, from the third pass) — fixed. `check-daemon-gaps` (my two new `DaemonCapabilities.expected` rows: that list is pinned against a literal 0.5.0 capability snapshot, so adding to it accuses every daemon in the snapshot of being stale) — rows removed; the terminal degrades on its own. `check-approve-path` ("ctrl-z should be unsupported": the new ctrl-/alt-letter pattern had started accepting it) — refused by name on `/send`, since there is no client there to resume a suspended job; the pty stream still carries the raw byte | all three green |
| check-ios-smoke | Two sessions on this Mac both drive the simulator the check picks (it always takes the newest iPhone type — iPhone 18 Pro / iOS 27), so it died twice mid-run ("INCONCLUSIVE: the test runner was killed before it connected"). Agreed a hand-off protocol with the other session and ran it alone | `check-ios-smoke: OK — the app launches, every tab renders, and a text field can appear · ran on iPhone 18 Pro · iOS 27.0` |

Not done, plainly (phase 2+ in the map): swipe gestures for windows/panes, double-tap paste,
hardware-keyboard commands, the dictation pill + composer bubble, OSC 52 clipboard, session
cards with thumbnails and the Home/Inbox tabs, image paste, diff viewer, docs site, pricing.
The rmux-bridge daemon on :7820 is untouched (the Mac's web console still uses it).

Verify-before-coding results: SwiftTerm ≥ 1.19 ships a build-tool plugin xcodebuild refuses
without `-skipPackagePluginValidation` — pinned to 1.18.0. Its GPU renderer needs the Xcode
Metal toolchain, installed with `xcodebuild -downloadComponent MetalToolchain`. `Bun.Terminal`
exists on bun 1.3.14 (mac, pi) and 1.4.2 (jetson).


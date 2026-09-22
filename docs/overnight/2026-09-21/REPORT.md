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

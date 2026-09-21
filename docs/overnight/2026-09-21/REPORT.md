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

1. **Read this branch** (`gh pr view` once S12 opens the draft PR) and the STATE.md gate line; land the stack #124 → #131 → this.
2. `claude /login` on the Jetson and the Pi (browser).
3. **Re-pair the phone to `pi`** (token rotated): `mesh pair -H pi` on the Pi or scan its QR.
4. **Physical iPhone + Watch**: confirm S6 — from the watch, with Wi-Fi off on the watch so it relays, open a screen peek and start a session; a failed command must show a reason, not a tick (T06/T07/T21).
5. Tap **Allow** on the watch simulator's notification alert (or grant Claude the device).
6. Promote `share/skills-staged/mesh-knowledge` → `share/skills` and bump the count in `scripts/check-mesh-skills.sh` to 5.
7. Decide the `/pair/new` default (flip needs a one-line edit in `check-token-rotate.sh` so it sends the bearer) and: iPad `TARGETED_DEVICE_FAMILY "1,2"` (App Store listing consequence), the Mac `.app` filename (still `MeshWatch.app`), app-icon regeneration for the new name.
8. TestFlight: `MESH_ALLOW_VERSION_DOWNGRADE=1 sh scripts/release-testflight-asc.sh --external` (Keychain dialog), then publish meshd 0.6.0 to mesh-install (`sh scripts/release-mesh-install.sh --publish`) and `mesh upgrade -H pi/jetson` from the release.
9. Wire the live halves (`scripts/check-overnight.sh`) into CI or a nightly on this Mac — CI has no fleet.
10. Turn off tonight's installer share when done: `tailscale serve --https=8890 off`; `pkill -f "http.server 8897"`; stop edge0 (`pkill -f "edge0 serve"`).

## Screens

`shots/`: `iphone-machines-paired.png` (fleet adopted via the pairing deep link), `iphone-home-lesearch-ai.png`, `ipad.jpg` (compat mode), `watch*.png`, `mac-menubar.png`, `jetson-screen.jpg`, `pi-screen.jpg`.

---
run_id: 2026-09-21T173000Z-overnight-S1-fleet
stage: implement
started_at: 2026-09-21T17:30:00Z
finished_at: 2026-09-21T18:00:00Z
status: succeeded
issue: none
pull_request: none
gate_level: fast
gate_status: GREEN
verifier: accepted
human_required: false
---

# S1 — fleet online + Linux screen peek (interactive overnight session, Arya-directed)

Not a factory queue item: Arya asked for this in-session (2026-09-21) and approved the plan in
`~/.claude/plans/check-the-devices-we-prancy-yeti.md`. Factory discipline kept: one slice, new
checks only, fresh-context verifier, no protected file touched, no merge, no push to main.

## Done
- Pi `meshd 0.2.0 → 0.6.0` via `mesh upgrade -H pi --src https://arya-macbook-pro.tailaddf1e.ts.net:8890/mesh-install.tgz`
  (installer served from this checkout on loopback :8897 behind `tailscale serve --https=8890`).
  `~/.mesh` backed up first to `pi:~/.mesh/backups/pre-0.6-2026-09-21.tgz`. Weak default token rotated
  (`mesh token rotate -H pi --yes`) and re-registered on the Mac; **the phone must re-pair to `pi`**.
- Jetson fresh install over ssh (`curl …/install.sh | sh`), `mesh host add jetson 100.118.47.127`.
- Daemon: Linux `/screen.jpg` via scrot (`input-linux.ts`), doctor screen row real, installer service
  PATH gains `~/.local/bin` + `~/.bun/bin`, `MESH_DISPLAY`/`XAUTHORITY` pass-through. Implementer: Codex
  (codex-delegate, brief in session scratchpad); reviewed and landed by the orchestrator.
- New checks: `check-fleet.sh`, `check-remote-agent-loop.sh`, `check-watch-smoke.sh`, `check-sim-fleet.sh`.

## Proof (real output)
```
$ mesh status
local            127.0.0.1:8899         meshd 0.6.0    up 2d 9h  doctor: 7/7 ok
pi               100.94.168.17:8899     meshd 0.6.0    up 54m  doctor: 7/7 ok
jetson           100.118.47.127:8899    meshd 0.6.0    up 5h 30m  doctor: 7/7 ok
$ MESH_FLEET_LIVE=1 MESH_FLEET_HOSTS="mac pi jetson" sh scripts/check-fleet.sh
check-fleet: ok   mac (darwin) meshd 0.6.0, doctor green, input ok, screen ok
check-fleet: ok   pi (linux) meshd 0.6.0, doctor green, input ok, screen ok
check-fleet: ok   jetson (linux) meshd 0.6.0, doctor green, input ok, screen ok
check-fleet: OK (live)
$ MESH_FLEET_LIVE=1 MESH_REMOTE_HOST=jetson sh scripts/check-remote-agent-loop.sh
check-remote-agent-loop: OK — session created on jetson, Started/Completed events seen, send landed, killed
$ ./.claude/scripts/gates.sh fast
FACTORY_GATES: level=fast status=GREEN passed=2 failed=0 failing=none skipped=none misconfigured=none
```
Screens: `docs/overnight/2026-09-21/shots/jetson-screen.jpg` (3440×1440), `pi-screen.jpg` (1920×1080).

Real agent on a remote box, from the Mac CLI: `mesh new pi-probe -H pi --cmd bash`, then
`mesh send pi-probe -H pi "MESHD_SESSION=pi-probe mesh-agent-run agy agy --dangerously-skip-permissions
--add-dir /home/arya/lesearch-probe --model gemini-3.1-pro-low --print='…create hello.txt…'"` →
`mesh events -H pi`: `Started` … `Completed`; `pi:~/lesearch-probe/hello.txt` = `Mon Sep 21 14:05:09 EDT 2026`.

## Verifier (fresh context, oh-my-claudecode:verifier on sonnet)
ACCEPT. Two follow-ups, both taken: empty-capture guard added to `linuxCaptureScreen`; the installer
http.server moved off :8890 (collided with `check-install-idempotent.sh`'s stub port) to :8897.

## Found, not fixed (for the morning)
- `claude` on the Jetson and the Pi are **not logged in** (OAuth expired) — `claude /login` needs a browser.
  `agy` and `cursor-agent` on the Pi are authenticated; `agy` was used for the proof.
- `mesh new --task` typeahead is discarded when the shell/agent starts slower than the daemon's 1.2 s
  readiness poll (bash on the Jetson; Claude Code's trust prompt). The task must be re-sent. Fix belongs
  in `server.ts` (`/agents/new` readiness) — serialized file, deferred.
- `agy --print` needs `--add-dir <cwd>` or it writes into its own scratch workspace.
- `mesh` over a non-interactive ssh fails with `/usr/bin/env: 'bun': No such file` until `~/.bun/bin` is on PATH.

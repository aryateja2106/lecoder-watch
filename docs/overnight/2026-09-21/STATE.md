# Overnight 2026-09-21 — STATE (resume point)

Plan: `~/.claude/plans/check-the-devices-we-prancy-yeti.md`. Worktree: `.claude/worktrees/lesearch-ai-overnight`, branch `feat/lesearch-ai-overnight-2026-09-21` (base `chore/codebase-map-and-regression` + cherry-pick 0a1bb66 PRODUCT.md).

Rules in force: never merge / push main; never edit CHARTER, gates.conf, gates.sh, AGENTS.md, .github, existing scripts/check-*, existing tests; live meshd :8899 untouched until S12 (side port 8901); remotes: write only ~/.mesh.

| Slice | Status | Check | Output / commit |
|---|---|---|---|
| S0 bootstrap | DONE | gates.sh fast | `FACTORY_GATES: level=fast status=GREEN passed=2 failed=0 failing=none skipped=none misconfigured=none`; sims iOS27-repro + Watch27-test + iPad27-test booted |
| S1 fleet + Linux screen | DONE (4a2a151, verifier ACCEPT) | check-fleet.sh | `mesh status`: local/mac/pi/jetson all meshd 0.6.0 (pi 0.2.0→0.6.0 via `mesh upgrade -H pi --src https://arya-macbook-pro.tailaddf1e.ts.net:8890/mesh-install.tgz`; jetson fresh install over ssh); doctor pi 7/7, jetson 7/7; input trusted on both; units enabled, Linger=yes; pi token rotated + re-registered; Pi ~/.mesh backup `~/.mesh/backups/pre-0.6-2026-09-21.tgz`. Linux screen patch: codex run in progress |
| S2 sims + MeshDesktop | DONE (checks in 4a2a151; screenshots after rebrand pending S3) | check-sim-fleet.sh, check-watch-smoke.sh, check-ios-smoke.sh | |
| S3 rebrand LeSearch AI + 0.6.0 | DONE (c7a3011) | check-brand.sh | |
| S4 remote agent loop | DONE — check green on jetson AND pi; real agy task on pi produced hello.txt + Started/Completed events; claude on both Linux boxes NOT logged in (morning: claude /login) | check-remote-agent-loop.sh | run record 2026-09-21T173000Z-overnight-S1-fleet.md |
| S5 mesh cp + /fs/write | DONE (86ae97e) — pi hello.txt → Mac ~/Downloads and → jetson, sha-verified | check-cross-host-cp.sh | structural + live (jetson, pi) OK |
| S6 relay receiver (ARCH-01/02) | DONE (473d40e); physical-pair proof = morning | check-relay-receiver.sh + check-relay-ack.swift | OK |
| S7 harness picker from /doctor | DONE (b6ddc7e) | check-harness-picker.sh + check-launchable.swift | OK |
| S8 mesh kb + /search skill | in progress (codex) | check-kb-federation.sh | |
| S9 brains | DONE (86ae97e, 1cc9681): /brain ported; ollama qwen3:4b on jetson (12 s tool call), qwen3:1.7b on pi (23-40 s); edge0-8b on Mac :8001 tool call 3.8 s via our patch; Needle 26/28 tool, 0.7 s, 34 MB; ADR written | check-brain.sh, check-intent.sh | OK |
| S10 bearer on /pair/new | pending | check-pair-auth.sh | |
| S11 suite + gates full + ADR | pending | check-overnight.sh | |
| S12 ship: fleet upgrade, PR, REPORT, notify | pending | | |

## Log
- 10:5x IST S0 started. Worktree created, PRODUCT.md cherry-picked (efe9cb1).
- 23:16 IST Fleet online (3 hosts 0.6.0). iPhone sim paired to the Mac daemon via `xcrun simctl openurl <sim> 'meshwatch://pair?h=…&c=…'` + one tap on Pair; fleet adopted (mac, pi, jetson, dataflow-offline). Screenshots: shots/iphone-machines-paired.png, ipad-before-rebrand.png, watch-after-pair.png (watch shows the notification prompt; sim MCP access to the watch device not granted — cannot tap Allow unattended).
- Installer served for the night: python http.server on 127.0.0.1:8890 (install/dist) behind `tailscale serve --https=8890`. Direct tailnet bind of python triggered the macOS firewall prompt (unattended hang) — Tailscale Serve avoids it. Disable in the morning: `tailscale serve --https=8890 off`.
- 23:35 IST S1 committed 4a2a151 after verifier ACCEPT. S4 proven with agy on the Pi (claude OAuth expired on both Linux hosts). Installer server moved to loopback :8897 (tailscale serve :8890 → 8897). Next: S3 (agy running), then S5 mesh cp (codex, after agy finishes — both touch bin/mesh).
- 00:30 IST S5/S6/S7/S9 landed. Finding: the simulator loses paired machines on every `simctl install` of an unsigned build (Keychain items become inaccessible) — a simulator/unsigned-build artefact; on a real iPhone the Keychain survives even delete-and-reinstall (measured 2026-08-28). Re-pair the sim via the meshwatch:// deep link when screenshots need machines.
- 00:35 IST Codex running S8 (kb + skill). S10 brief written (pair auth), dispatch after S8 lands (serialized files).

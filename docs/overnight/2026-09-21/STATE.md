# Overnight 2026-09-21 — STATE (resume point)

Plan: `~/.claude/plans/check-the-devices-we-prancy-yeti.md`. Worktree: `.claude/worktrees/lesearch-ai-overnight`, branch `feat/lesearch-ai-overnight-2026-09-21` (base `chore/codebase-map-and-regression` + cherry-pick 0a1bb66 PRODUCT.md).

Rules in force: never merge / push main; never edit CHARTER, gates.conf, gates.sh, AGENTS.md, .github, existing scripts/check-*, existing tests; live meshd :8899 untouched until S12 (side port 8901); remotes: write only ~/.mesh.

| Slice | Status | Check | Output / commit |
|---|---|---|---|
| S0 bootstrap | DONE | gates.sh fast | `FACTORY_GATES: level=fast status=GREEN passed=2 failed=0 failing=none skipped=none misconfigured=none`; sims iOS27-repro + Watch27-test + iPad27-test booted |
| S1 fleet + Linux screen | deploy DONE, patch in review | check-fleet.sh | `mesh status`: local/mac/pi/jetson all meshd 0.6.0 (pi 0.2.0→0.6.0 via `mesh upgrade -H pi --src https://arya-macbook-pro.tailaddf1e.ts.net:8890/mesh-install.tgz`; jetson fresh install over ssh); doctor pi 7/7, jetson 7/7; input trusted on both; units enabled, Linger=yes; pi token rotated + re-registered; Pi ~/.mesh backup `~/.mesh/backups/pre-0.6-2026-09-21.tgz`. Linux screen patch: codex run in progress |
| S2 sims + MeshDesktop | in progress (phone+iPad+watch app running, phone paired to fleet via meshwatch://pair deep link; MeshDesktop building) | check-sim-fleet.sh, check-watch-smoke.sh, check-ios-smoke.sh | |
| S3 rebrand LeSearch AI + 0.6.0 | pending | check-brand.sh | |
| S4 remote agent loop (jetson) | pending | check-remote-agent-loop.sh | |
| S5 mesh cp + /fs/write | pending | check-cross-host-cp.sh | |
| S6 relay receiver (ARCH-01/02) | pending | check-relay-receiver.sh | |
| S7 harness picker from /doctor | pending | check-harness-picker.sh | |
| S8 mesh kb + /search skill | pending | check-kb-federation.sh | |
| S9 brains: /brain, Edge0, ollama, Needle | pending | check-brain.sh, check-intent.sh | |
| S10 bearer on /pair/new | pending | check-pair-auth.sh | |
| S11 suite + gates full + ADR | pending | check-overnight.sh | |
| S12 ship: fleet upgrade, PR, REPORT, notify | pending | | |

## Log
- 10:5x IST S0 started. Worktree created, PRODUCT.md cherry-picked (efe9cb1).
- 23:16 IST Fleet online (3 hosts 0.6.0). iPhone sim paired to the Mac daemon via `xcrun simctl openurl <sim> 'meshwatch://pair?h=…&c=…'` + one tap on Pair; fleet adopted (mac, pi, jetson, dataflow-offline). Screenshots: shots/iphone-machines-paired.png, ipad-before-rebrand.png, watch-after-pair.png (watch shows the notification prompt; sim MCP access to the watch device not granted — cannot tap Allow unattended).
- Installer served for the night: python http.server on 127.0.0.1:8890 (install/dist) behind `tailscale serve --https=8890`. Direct tailnet bind of python triggered the macOS firewall prompt (unattended hang) — Tailscale Serve avoids it. Disable in the morning: `tailscale serve --https=8890 off`.

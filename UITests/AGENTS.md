# UITests/ — automated tests that open the real iPhone app in a simulator and tap through it, so a crash on launch cannot ship again

**Read first:** `UITests/SmokeTests.swift:3-12` (why it exists: 0.5.0 crash) · `docs/playbooks/simulator-testing.md` (running rules) · `scripts/check-ios-smoke.sh` (the runner)
**Surface:** checks
**Serialized (one agent at a time):** the whole folder while a test runs — two `xcodebuild test` on one simulator kill each other's runner (`docs/playbooks/simulator-testing.md` "Never run two").
**Prove a change:**
- `sh scripts/check-ios-smoke.sh` (minutes; runs `xcodebuild test -scheme MeshWatch`, target `MeshWatchUITests`, `project.yml:31-34`, `:50-60`)
- release/CI reading: `MESH_SMOKE_REQUIRED=1 sh scripts/check-ios-smoke.sh` — otherwise a missing simulator is SKIP with exit 0
- screenshots: `sh scripts/product-shots.sh` (sets `TEST_RUNNER_MESH_SHOTS=1`, `scripts/product-shots.sh:35`)

**Traps:**
- `FeedbackSendTests` writes a real Supabase row and a real GitHub issue; it runs only with `TEST_RUNNER_MESH_FEEDBACK_E2E=1` (`FeedbackSendTests.swift:3-7`, `:16`). Never set it in a loop.
- XCUITest relaunches a crashed app, so `.runningForeground` alone passes through a crash; assert `tab.isSelected` (`SmokeTests.swift:40-46`).
- Tests find UI by visible text (`SmokeTests.swift:36`, `:85`); a label rename in `iOS/` breaks them. Update both in one change.
- The Face ID gate is bypassed with `-mesh.requireBiometrics.v1 <false/>`; a bare `NO` arrives as a String (`SmokeTests.swift:19-21`, key at `iOS/AppLock.swift:22`).
- This folder is not in `docs/agents/CODEMAP.md` or `CHECKS.md`; `scripts/codemap-index.py` does not scan it.
- Do not edit `scripts/check-ios-smoke.sh` in an unattended run (CLAUDE.md non-negotiable 3).

**SDLC stage:** Test, Deploy — the launch gate before TestFlight (`scripts/release-testflight-asc.sh` exports `MESH_SMOKE_REQUIRED=1`).
**Map:** see the file list above (3 tracked files)

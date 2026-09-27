# ci_scripts/ — the two scripts Apple's cloud build service (Xcode Cloud) runs before it builds the iPhone and Watch apps for testers

**Read first:** `ci_scripts/ci_pre_xcodebuild.sh` (release gate + build-number stamp), `scripts/release-testflight-asc.sh` (the local release path it mirrors), `docs/playbooks/xcode-cli.md`
**Surface:** checks
**Serialized (one agent at a time):** both files — the only gate on a lane that can hand a build to testers (`ci_pre_xcodebuild.sh:13-17`)
**Prove a change:** `sh -n ci_scripts/ci_post_clone.sh ci_scripts/ci_pre_xcodebuild.sh` and `sh scripts/check-all.sh` (what the hook runs, `ci_pre_xcodebuild.sh:58`). The lane itself cannot run locally — no dedicated check; add `scripts/check-ci-scripts.sh` (every plist using `$(CURRENT_PROJECT_VERSION)` gets stamped)
**Traps:**
- Needs `CI_PRIMARY_REPOSITORY_PATH` under `set -eu` (`ci_post_clone.sh:11`, `ci_pre_xcodebuild.sh:38`); never run the pre-build hook locally — it rewrites tracked plists (`:42-44`).
- Stamps 2 plists only; `MeshWatchWidgets/Info.plist:21-22` and `WatchWidgets/Info.plist:21-22` read `$(CURRENT_PROJECT_VERSION)`, so `:8-11` is stale and extension build numbers mismatch the app's (upload effect unverified).
- `brew install xcodegen` is unpinned (`ci_post_clone.sh:13`).
- Smoke test may SKIP and the hook only warns (`ci_pre_xcodebuild.sh:67-80`): an archive here is not a launched app (AGENTS.md rule 1).
- Whether an Xcode Cloud workflow is enabled is unverified from the tree.
**SDLC stage:** Deploy (TestFlight lane) and Test (runs every self-check before archiving).
**Map:** see the file list above (2 files)

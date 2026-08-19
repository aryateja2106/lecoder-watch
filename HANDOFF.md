# HANDOFF — MeshWatch (updated 2026-07-07)

Single entry point to resume. Read this → `docs/PROJECT-STATE-AND-LEARNINGS-2026-07-07.md` → `git log`, then continue.
Older but still-useful context: `docs/PRODUCT-CONTEXT-2026-06-05.md`, `docs/XCODE-WATCH-DEVICE-RUNBOOK.md`.

## Resume protocol
- **Branch `backup/2026-07-02`. NEVER push.** Tree clean; all work committed.
- **Build gate before every commit** (both must be `** BUILD SUCCEEDED **`):
  ```sh
  cd ~/Projects/lecoder-watch && xcodegen generate
  xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
  xcodebuild -project MeshWatch.xcodeproj -scheme 'MeshWatch Watch App' -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData build
  ```
  Then `scripts/check-*.swift` (swiftc + run). **No test targets** — self-checks are the pattern.
- **Commit per green slice**; stage only that slice's files (never `git add -A` — the Cursor agent has WIP in `meshd/`+`install/`).
- **Don't run `install.sh` against the Mac** — it clobbers the Cursor agent's deployed `~/.mesh` cmux-bridge fixes (see state doc → Ownership).

## Live & working (verified 2026-07-07)
- Fleet: **mac up · dataflow (arya@100.80.10.95, Ubuntu) up · pi down**. Check: `./install/payload/bin/mesh hosts`.
- **Watch clean terminal** — confirmed live showing real remote `ls` output, crown-scroll + auto-follow + key bar (`5ef5167`).
- **iOS app** — S1–S6 shipped, crash fixed, builds green, real remote output on phone.
- **Full Mac control from the watch** (`docs/mac-remote-control.md`) — meshd 0.2.2
  `/input` `/clipboard` `/volume` `/system` `/apps` `/displays`; Swift CGEvent +
  AXUIElement helper at `~/.mesh/bin/mesh-input`. Watch has "Control <mac>" as the first
  row of the machines list: display picker, tap-to-place cursor, trackpad, crown scroll,
  every-key keyboard, app switcher, window snapping, media, system power. Multi-display
  throughout. Deployed live 2026-08-19 (backup `~/.mesh/backups/pre-input-*`); all of it
  verified against :8899 and a listen-only CGEventTap. See PROGRESS.md for the slice log.
- **Phone tokens repaired 2026-08-19** — the iOS app had no saved machine list and fell
  back to `testtoken`, which meshd rotated away from on 08-13, so every host read "token
  rejected". Real tokens (from `~/.mesh/hosts.json`) written into the app's UserDefaults.
- **`mesh` CLI + one-curl installer + tailnet serving** — all verified. The prior P0s (phone terminal readability, pane nav, agent-view usability) are addressed.

## Open tasks (resume here)
| # | Task | Notes |
|---|------|-------|
| 15 | **iOS/mobile polish** | cmux-clean workspace list, session card, easier in-app add-host. User: "work a lot on mobile." |
| 16 | **Cross-platform desktop client** | New surface on the `mesh` CLI/API layer. Stack TBD (Tauri/Rust per prefs, or web). |
| 14 | **HTML artifacts** (non-technical) | what/how/deps/file-paths, trust-building. artifact-design skill. |
| 4  | **Nix reproducible workflow** | nix-darwin + home-manager + `~/dotfiles` flake; install pending user sudo. |
| 7  | **S7 meshd payload sync** | backport deployed `~/.mesh` fixes → repo payload (coord. w/ Cursor agent), then native `/limits` (recipe: `docs/native-limits-recipe-2026-07-07.md`). |
| 8  | **Runtime runbook** | cmux bridge :8901, noVNC :6080 (down; needed for VNC mirror), pi meshd. |

**Suggested order:** #15 or #16 first (ask which) → #14 (fast, high trust value) → #4/#7/#8 as capacity allows.

## Build gotchas (from prior rounds — still true, don't repeat)
- Build via **scheme + `-destination`**, never `-sdk iphonesimulator` (forces the embedded watch onto the iOS SDK → WCSessionDelegate fails).
- One `-derivedDataPath`; DerivedData fragments across `-target`/`-scheme` and leaves a stale embedded watch — clean when in doubt.
- Watch sim runs the **companion-embedded** watch app; uninstall the iOS app first to test a standalone watch build.
- **Watch deep-nav in the sim needs the Digital Crown** (automation can't scroll there) — verify deepest screens on device or via a paired phone relay.
- **Accessibility trust is per-process-launch and per-binary.** `mesh-input` run from a shell
  inherits the terminal's grant and reports `trusted:true` — that proves nothing about the
  launchd-run daemon. Always check via `curl .../input` against :8899. Recompiling the helper
  voids the grant; meshd recycles the child when a status check sees trust flip.
- `strings | grep` can't see Swift small-string literals (≤15 bytes) — not a valid build check.
- **build-green ≠ crash-free**: run the app past its first poll (~10s) and check `~/Library/Logs/DiagnosticReports/*.ips` (this session's `SIGABRT` came from `UserDefaults.set(aSet)` — Set isn't a plist type).

## Computer-use (not blocking)
Permissions now correct (BackgroundComputerUse.app in both Accessibility + Screen Recording). Still fails only because macOS reads TCC at process launch — **a fresh session/restart picks it up**. Only needed to drive the sims; product work doesn't depend on it. Memory: `computer-use-permissions`.

## Runtime notes
- Installer server (`:8890`) runs in the prior session's background — stops when that session ends. Re-run `sh scripts/serve-installer.sh` to add hosts.
- Keep OpenUsage (:6736) alive on the Mac until native `/limits` (S7) ships.

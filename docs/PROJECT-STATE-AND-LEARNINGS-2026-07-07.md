# LeSearch Mesh — Project State & Learnings (2026-07-07)

Resumption context. If you're a fresh Claude picking this up: read this, then `git log`, then continue.
**Branch `backup/2026-07-02`. Never push. Build-green gate before every commit (below).**

## What LeSearch Mesh is
iPhone + Apple Watch (+ soon a cross-platform desktop) client for driving coding agents on
many machines over Tailscale. `meshd` (bun HTTP daemon, :8899, Bearer token) runs on each
machine; the apps + the `mesh` CLI talk to it. Repo: `~/Projects/lecoder-watch`.

## What's WORKING now (verified this session)
- **Multi-host mesh live**: `mac` (127.0.0.1 / 100.94.221.115, macOS) + `dataflowagents`
  (`arya@100.80.10.95`, Ubuntu, meshd via systemd --user) both `up`; `arya-pi` (100.94.168.17) often down.
- **Clean watch terminal** (commit 5ef5167) — CONFIRMED live: the Watch shows real `ls` output
  from the remote dataflow box in a dark full-bleed monospaced terminal with Digital Crown
  scroll, auto-follow newest, and a horizontally-scrollable key bar (Reply/Enter/Interrupt/Tab/
  Esc/Up/Down/text-size) + VoiceOver labels. `Watch/WatchViews.swift` `terminalScreen`/`terminalKeyBar`/`keyChip`.
- **iOS app**: all six goals app-side (S1–S6), builds green both schemes, installs+launches on
  the sims. Crash fixed (see Learnings). Phone shows the same session's live remote output.
- **`mesh` CLI** (`install/payload/bin/mesh`, dependency-free bun): `hosts/ls/peek/send/key/
  new/kill/usage/health/events`, `-H host`, `--json`, `mesh man`. Config `~/.mesh/hosts.json`
  (mac default; dataflow + pi registered). Verified against live meshd incl. full new→send→peek→kill.
- **Installer**: `--upgrade` (token-preserving), `mesh` CLI + man ship with the `tools` component,
  one-curl tailnet serving via `scripts/serve-installer.sh`. Whole loop verified incl. a real
  `curl … | sh` install from the served URL.
- **Remote install proven**: `ssh arya@100.80.10.95` then `curl -fsSL http://100.94.221.115:8890/install.sh | sh -s -- --token testtoken` → meshd + rmux-bridge up.

## Commit history this session (ed2e5b4..HEAD, newest first)
5ef5167 watch clean terminal · 66ec4b3 CLI/install runbook · 5a0a910 mesh api() throw ·
bd89a6a mesh CLI + installer --upgrade + serving · 897256f iOS crash fix · f3dbcd0 goal matrix ·
9c9ad75 S1–S6 review fixup · 924d394 S6 watch · 67f8d82 S5 VNC · 9bbd068 S4 keys · b65a7dc S3
spawn-any-CLI · e001161 S2 reset-aware · 2550df1 native-limits recipe · 8fc77ac S1 alerts ·
1d7dbbb goal doc · 06abe74 untrack .omc · 4823916 WIP checkpoint.

## Core file paths (be careful of these)
- `Shared/Models.swift` — Machine/Agent/Pane/UsageLimit/WatchCommand/MeshSnapshot. **Changing the
  WatchCommand/MeshSnapshot schema breaks watch decode (try? → silent drop); ship phone+watch together.**
- `Shared/MeshClient.swift` — HTTP client, 3s timeout, multi-URL failover. `Shared/LimitHelpers.swift` — limit math (`isBlocked(_ limit:now:)` is reset-aware).
- `iOS/NotificationManager.swift` — limit lifecycle + reset alerts. **UserDefaults only stores
  property-list types — never a Set (see Learnings).**
- `iOS/MeshStore.swift` / `Watch/WatchMeshStore.swift` — polling + persistence + relay. `iOS/TerminalView.swift`, `iOS/ContentView.swift`, `Watch/WatchViews.swift` — UI.
- `meshd/server.ts` (dev) vs `install/payload/meshd/server.ts` (payload, canonical for install) — **FORKED, not versions. Both have NUL bytes → use `grep -a`/`diff --text`.**
- `install/install.sh` (666+ lines), `scripts/package-mesh-install.sh`, `scripts/serve-installer.sh`.
- Build gate: `xcodegen generate && xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build` and the
  same for scheme `'MeshWatch Watch App'` (watchOS Simulator). Then `scripts/check-*.swift` (swiftc + run). **No test targets** — a `scripts/check-*.swift` self-check is the repo's pattern.

## LEARNINGS (session)
- **build-green ≠ crash-free.** The iOS app crashed every ~8s (`SIGABRT`) despite both builds
  succeeding. Root cause: `UserDefaults.set(aSet)` throws — `Set.filter` returns a **Set**, and
  UserDefaults only stores property-list types. Fix: `Array(set.filter{…})`. **Always run the app
  past its first poll cycle (~10s+) and check `~/Library/Logs/DiagnosticReports/*.ips`, not just the launch frame.**
- **Session-limit kills wiped in-flight workflow agents twice.** Slices that commit per-agent
  survive it (S1 landed; S2–S6 re-ran after reset). Commit-per-slice is the resilient pattern.
- **watchOS API floor is 10.0** (`project.yml`). `.textSelection` is NOT on watchOS. `ScrollViewReader`,
  `safeAreaInset`, two-param `.onChange` are fine at 10.0.
- **Watch sim shows machines offline** unless a paired phone sim relays (WatchConnectivity) — the
  watch sim can't reach meshd directly. Verify the watch against the real paired setup, not the bare sim.
- **`--cmd shell` is a sentinel** meaning "plain session, no command" (matches the app picker); the
  CLI omits it. Passing it literally makes meshd exec a bogus `shell` → session dies instantly.
- **mesh CLI**: a helper that `process.exit`s on error can't be caught — `api()` must throw so
  `hosts` can mark peers down instead of bailing on the first unreachable one.
- **Installer token**: re-running install regenerates the token by default, breaking saved app/CLI
  configs — the installer now preserves an existing `$MESH_HOME/token` (and `--upgrade` relies on it).

## Ownership split (with the Cursor/gpt-5.5 agent in herdr)
- **Cursor agent owns** `meshd/`, `install/payload/meshd/`, and the deployed `~/.mesh` (cmux-bridge
  fixes: serialize cmux CLI calls behind a mutex — concurrent socket access was killing the bridge;
  60s cmux cache; tmux-based startup). Its work is in worktree `lecoder-watch-cmux-bridge`
  (branch `fix/cmux-bridge-slice-d`), NOT merged into ours. **Never run `install.sh` against the Mac
  or it clobbers those deployed fixes.** These are macOS-only (cmux) — inert on the Linux remote.
- **Claude (this session) owns** the Swift apps (`iOS/`, `Watch/`, `Shared/`), the `mesh` CLI, the
  installer's `--upgrade`/CLI/serving additions, docs. Two divergent iOS/Watch change-sets exist
  (mine committed, Cursor's uncommitted in its worktree) — need one reconciliation pass before merge.

## What's NEXT (roadmap)
1. **Mobile (iOS) polish** — user: "still need to work a lot on the mobile … application."
2. **Cross-platform desktop client** — user: "cross platform desktop application." New surface (the `mesh` CLI is the shared API layer to build on).
3. **HTML artifacts** (task #14) — non-technical product explainers (what/how/deps/file-paths) for trust.
4. **Nix reproducible workflow** (task #4) — nix-darwin + home-manager + `~/dotfiles` flake (scaffolded, install pending user sudo).
5. **meshd payload sync / S7** (task #7) — backport deployed ~/.mesh fixes → repo payload (coordinate with Cursor agent), then native `/limits` (recipe in `docs/native-limits-recipe-2026-07-07.md`).
6. **Runtime runbook** (task #8) — cmux bridge :8901, noVNC :6080 (down; needed for G5 VNC), pi meshd.

## Adding a machine (reproducible)
`sh scripts/serve-installer.sh` on the mac → on target: `curl -fsSL http://<mac-tailnet-ip>:8890/install.sh | sh -s -- --token testtoken`. `--upgrade` / `--uninstall --purge`. Details: `docs/mesh-cli-and-remote-install.md`.

## Computer-use permission (why it's blocked)
The helper **BackgroundComputerUse.app** has Screen Recording but is **missing from Accessibility**.
Fix: System Settings → Privacy & Security → Accessibility → add/enable BackgroundComputerUse.app,
then **fully quit & relaunch** the host process (TCC is read at process start). Retry `request_access` after.

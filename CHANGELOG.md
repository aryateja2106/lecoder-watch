# Changelog

Notable changes to MeshWatch (the iPhone + Apple Watch app) and to the mesh
installer payload that ships from this repo.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

A version here is a `v*` tag in this repo. Each tag is what a release of
[LeSearch-AI/mesh-install](https://github.com/LeSearch-AI/mesh-install) is cut
from — that public repo holds no source, only the `install.sh`,
`mesh-install.tgz` and `SHA256SUMS.txt` assets the one-liner resolves against.
See [docs/RELEASING.md](docs/RELEASING.md) for the version-string contract
(several of them currently disagree) and the release procedure.

## [Unreleased]

### Added

- `.github/workflows/release.yml` — tag-triggered release pipeline: lints
  `install.sh` (`sh -n` + shellcheck), runs the payload self-checks, builds the
  tarball, generates `SHA256SUMS.txt`, publishes all three assets to
  LeSearch-AI/mesh-install, and re-downloads them to verify. Needs a
  `RELEASE_TOKEN` repo secret; `GITHUB_TOKEN` cannot write cross-repo.
- `llms.txt` — llmstxt.org entry point so an agent can discover the install
  command, the `mesh` CLI, the meshd HTTP API and the Orca integration without
  reading the whole tree.
- `packaging/homebrew/lesearch-mesh.rb` — Homebrew formula for the `mesh` CLI
  alone (not meshd). The `lesearch-ai/homebrew-tap` repo it belongs in does not
  exist yet; the formula header carries the exact commands to create it.
- `packaging/npm/` — `@lesearch/mesh` launcher so `npx @lesearch/mesh` and
  `bun x @lesearch/mesh` reach an existing `~/.mesh/bin/mesh`. Unpublished.
- `docs/RELEASING.md` and this changelog.

## [0.2.2] - 2026-08-12

Supersedes 0.2.1. No functional change to what gets installed; this is about what
goes into the tarball.

### Fixed

- The payload no longer contains untracked files. 0.2.1 shipped
  `install/payload/meshd/.omc/state/sessions/<uuid>/` — two agent tool-state
  files — because `package-mesh-install.sh` walked the working tree. The
  contents were harmless (a shell error string and advisory text, no
  credentials), but the same mechanism would have published a stray `.env`.
  Membership now comes from `git ls-files`.
- The tarball is reproducible: tar metadata is normalised and gzip is stamped
  with `mtime=0`, so the same commit yields byte-identical output and the
  published checksum can be independently reproduced.
- `check-package-mesh-install.sh` now rejects any dot-entry and anything outside
  the four intended prefixes, instead of only `install/.omx/`.

## [0.2.1] - 2026-08-12

First release the bare one-liner actually completes on a machine that is not the
maintainer's.

### Added

- **Orca integration.** [Orca](https://github.com/stablyai/orca) terminals appear
  in meshd's `/agents` beside rmux/tmux and cmux sessions as `orca:<handle>`,
  with read and send. Orca ships desktop, iOS and Android clients but no watchOS
  one, so this is what makes MeshWatch a watch client for it. Implemented over
  the bundled `orca` CLI with `--json` (its documented agent contract), not the
  `:6768` WebSocket, which is end-to-end encrypted behind an undocumented
  handshake. 3s list cache and a 6s hard timeout keep an Electron-backed CLI from
  stalling meshd's 8s poll; orphaned terminals are dropped and process stats are
  left undefined rather than fabricated. A machine without Orca degrades to empty
  everywhere.
- `/health` reports an `orca` capability only when the Orca runtime is reachable,
  so the Machines tab can tell "not installed" from "installed but not running".
- App icons for iPhone and Watch, drawn from the Lesearch constellation mark. The
  watch gets its own artwork: the orbit arcs compute to 0.6px at complication
  size, so they are dropped rather than smeared, and the background is lifted off
  black. Light is opaque; dark and tinted are transparent.
- First-run onboarding (welcome → install → connect → notifications). Nothing
  polls and no permission is requested before the user knows what the app is; the
  notification prompt used to fire on the home screen at first launch.
- "Paste installer output" in onboarding parses `install.sh`'s summary block, so a
  32-character token never has to be transcribed by hand.

### Changed

- `install.sh` falls back to the published release when there is no `payload/`
  beside it — i.e. when piped from curl. A checkout still wins, so local
  development is unchanged; `MESH_FALLBACK_SRC` overrides for forks and mirrors.
- The app ships with **no** machines. `Machine.defaults` is empty and the
  maintainer's dogfood fleet moved to `Machine.devSeed`, loadable from
  Settings ▸ Developer. New users no longer land in three unreachable tailnet
  hosts with "token rejected".
- The in-app install command is the public curl one-liner instead of
  `sh install.sh` against a checkout a new user does not have.
- Docs reframe `scripts/serve-installer.sh` as the dev / air-gapped path it
  actually is, and document Orca as a session source.

### Fixed

- The advertised install was a Tailscale IP pointing at the maintainer's laptop,
  serving from a gitignored directory, only while a foreground script ran. The
  in-repo alternative used a literal `<host>`, and `install.sh` shipped with
  `MESH_SRC_DEFAULT="__MESH_SRC__"`, so piping it from anywhere died with
  "no payload found".
- The v0.1.0 tarball predated `validate_payload`'s `bin/mesh` requirement, so the
  fallback failed with `missing payload: bin/mesh`. This payload contains
  `bin/mesh`, `share/man` and the hook scripts.
- `ensure_tmux` ran unconditionally, so a clean VPS aborted on a dependency that
  launchd/systemd installs never use. It now runs only when tmux is the chosen
  supervisor.
- `mesh host add` no longer defaults the token to the shared literal
  `testtoken`; it reads this machine's `~/.mesh/token` and errors when there is
  none. Adding a host with someone else's literal only ever produced 401s against
  your own meshd.
- Two literal NUL bytes in a template literal in `meshd/server.ts`
  (`${e.host}\0${e.scope}`) made the file classify as binary, so `grep` silently
  matched nothing in it. Replaced with the `\0` escape; identical runtime string.
- iOS crash: `Set.filter` returns a `Set`, which `UserDefaults` cannot store —
  wrapped in `Array`.

### Removed

- Six `// #region agent log` debug blocks in the shipped meshd payload that wrote
  JSON to a hardcoded local path on every session list, stats call and cmux bridge
  error. They came from a single WIP snapshot, not live work.
- The dead cmux bridge probe in the poll path. `ensureCmuxBridge()` awaited
  `cmuxBridgeReady()` and discarded the result once its log was removed, costing a
  POST with a 2s timeout on every `cmuxSessions()` call — which runs on both
  `/agents` and `/stats`, so every phone poll paid for it. `cmuxJson()` already
  returns null when the bridge is down, so behaviour is unchanged.

### Security

- Stopped publishing a maintainer filesystem path (`/Users/…/debug-*.log`) to a
  public repo, and genericised a real tailnet IP in the `mesh(1)` EXAMPLES
  section.

## [0.1.0] - 2026-06-20

- Single curl command to install, start and uninstall the mesh stack (meshd,
  rmux-bridge, hook tools) on macOS, Linux and WSL, on arm64 and x86_64.
- Reboot-persistent services: launchd on macOS, `systemd --user` plus
  `loginctl enable-linger` on Linux/WSL, detached tmux where neither exists.
  KeepAlive/Restart on crash.
- Bun + TypeScript payload, no Node.
- Known broken: the payload omitted `bin/mesh`, which `validate_payload`
  requires, so the bare one-liner failed. Fixed in 0.2.1.

[Unreleased]: https://github.com/LeSearch-AI/mesh-install/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/LeSearch-AI/mesh-install/releases/tag/v0.2.1
[0.1.0]: https://github.com/LeSearch-AI/mesh-install/releases/tag/v0.1.0

# install/payload/bin/ — the `mesh` command people and agents type, plus the small helpers that send agent alerts and drive the Mac's mouse and keyboard

**Read first:** `mesh` dispatch at `mesh:2555-2612` (every verb), `docs/playbooks/daemon-and-mesh.md` (ports, tokens, restarts), `docs/agents/harnesses.md` §B (before touching `mesh-hook`)
**Surface:** cli
**Serialized (one agent at a time):** `mesh` `cmdPair` (`:789`), `cmdTokenRotate*` (`:1352-1515`), `hosts.json`/token handling (`:14-16`), `cmdHooks` (`:1622`, edits the user's `~/.claude/settings.json`)
**Prove a change:**
- the checks CODEMAP lists for the file (`docs/agents/CODEMAP.md:156-164`), e.g. `sh scripts/check-mesh-upgrade.sh`, `sh scripts/check-mesh-uninstall.sh`, `sh scripts/check-mesh-hooks.sh`, `sh scripts/check-mesh-skills.sh`
- `mesh-hook`: `python3 scripts/check-mesh-hook.py` (NOT run by `check-all.sh`) + `sh scripts/check-roundtrip.sh`; `mesh-input.swift`: `sh scripts/check-mesh-input.sh`; `mesh-kb`: `sh scripts/check-kb-federation.sh`
- then run the verb against a side-port daemon (AGENTS.md rules 1 and 5), `MESH_HOME=<scratch>`
**Traps:**
- `mesh` has no version of its own; it reads `const VERSION` from `meshd/server.ts` (`mesh:19-28`). Bump the daemon to ship a CLI change.
- Every file here is copied to `~/.mesh/bin` with mode 755 and put on PATH (`install/install.sh:515-516`, `mesh:998-1004`), including stray `.md` files; keep this folder to shipped binaries.
- meshd compiles `mesh-input.swift` into the LIVE `~/.mesh/bin/mesh-input` whenever the source is newer, even from a checkout run (`meshd/input.ts:42-50,92-94`); replacing that binary drops the Mac's Accessibility grant (`install/install.sh:737-742`). Read, not run.
- `mesh upgrade` syncs `meshd/`, `bin/`, `hooks/`, `rmux-bridge/public/` only (`mesh:1179-1181`): not `rmux-bridge/src/`, not `share/`.
- `mesh-hook` outside tmux/rmux posts `replyable:false` and the phone shows no buttons (`mesh-hook:139-190`, `docs/agents/harnesses.md:19`).
- `grep -c . mesh` = 2372 of 2616 lines; confirm a file is not skipped as binary before trusting zero matches (AGENTS.md rule 3).
**SDLC stage:** Build, Deploy — the `mesh` CLI code; its upgrade verb is the release path to existing users (see [docs/sdlc/3-build.html](../../../docs/sdlc/3-build.html), [docs/sdlc/5-ship.html](../../../docs/sdlc/5-ship.html))
**Map:** [INDEX.md](INDEX.md) (generated; regenerate with python3 scripts/folder-index.py); `docs/agents/CODEMAP.md` section `install/payload/bin/`

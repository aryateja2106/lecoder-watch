# install/payload/ — everything the installer copies into `~/.mesh` on a user's machine: daemon, command-line tools, terminal bridge, skills

**Read first:** `install/install.sh:506-528` (what is copied where), `AGENTS.md` rules 4 and 6 (one daemon copy; shipped is not this repo)
**Surface:** installer
**Serialized (one agent at a time):** `meshd/server.ts`, `meshd/auth.ts`, `meshd/pair.ts` (`docs/agents/CODEMAP.md:30`); pairing/token code in `bin/mesh`; auth in `rmux-bridge/src/server.ts`
**Prove a change:** `sh scripts/check-package-mesh-install.sh` (layout), then the check named in the sub-folder's AGENTS.md; `sh scripts/check-all.sh` before a PR
**Traps:**
- Every file here ships: `scripts/package-mesh-install.sh:17-29` tars this directory as-is (skips only `node_modules`, `.omc`, `bun.lock*`, `.DS_Store`). Leave no scratch files here.
- `meshd/` is the ONE daemon copy (AGENTS.md rule 4) and has its own area map. `rmux-bridge` imports `../../meshd/redact` (`rmux-bridge/src/server.ts:10`), so the bridge cannot run without it.
- `mesh upgrade` moves only `meshd/`, `bin/`, `hooks/`, `rmux-bridge/public/` (`bin/mesh:1179-1181`); `rmux-bridge/src/` and `share/` reach users only through a fresh install.
- Users run the last `mesh-install` release, not this tree (AGENTS.md rule 6): `curl -s http://127.0.0.1:8899/health` before debugging a real machine.
**SDLC stage:** Deploy — this directory is the release artifact (see [docs/sdlc/5-ship.html](../../docs/sdlc/5-ship.html))
**Map:** `docs/agents/CODEMAP.md` sections `install/payload/meshd/`, `install/payload/bin/`, `install/payload/rmux-bridge/`

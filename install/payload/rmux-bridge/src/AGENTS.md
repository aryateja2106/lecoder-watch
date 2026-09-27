# install/payload/rmux-bridge/src/ — the code of the port-7820 terminal bridge server

**Read first:** `server.ts` header (`:1`), auth at `server.ts:180-230`
**Surface:** daemon
**Serialized (one agent at a time):** `server.ts` auth (`authorized`, `:217`)
**Prove a change:** `sh scripts/check-bridge-auth.sh`; boot on a spare port (`PORT=7821 BRIDGE_HOST=127.0.0.1 bun run server.ts`)
**Traps:**
- Token comes from `MESHD_TOKEN` or `~/.mesh/token` (`server.ts:186-189`); the installer does not put it in the service env (`install/install.sh:836-843`).
- Not synced by `mesh upgrade` (`bin/mesh:1179-1181`).
- Imports `../../meshd/redact` (`server.ts:10`).
**SDLC stage:** Build — the legacy bridge server's code; its auth is serialized (see [docs/sdlc/3-build.html](../../../../docs/sdlc/3-build.html))
**Map:** 2 tracked files; run `git ls-files install/payload/rmux-bridge/src` to list them.

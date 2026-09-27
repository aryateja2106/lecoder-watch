# install/payload/rmux-bridge/ — a second small server (port 7820) that shows a live terminal in a web page; the phone app now uses a built-in terminal instead

**Read first:** `src/server.ts` (the whole service), `docs/product/PRODUCT.md` §5.4 (bridge needs the daemon token since 0.6), `docs/playbooks/daemon-and-mesh.md:9-18` (which "bridge" is which)
**Surface:** daemon
**Serialized (one agent at a time):** `src/server.ts` auth (`authorized`, `src/server.ts:180-230`) — AGENTS.md "Must be serialized"
**Prove a change:** `sh scripts/check-bridge-auth.sh && sh scripts/check-bridge-kill-scope.sh && sh scripts/check-package-mesh-install.sh`; boot on a spare port (`PORT=7821 BRIDGE_HOST=127.0.0.1 bun run src/server.ts`), never restart the live one (AGENTS.md rule 5)
**Traps:**
- Possibly vestigial: `Shared/Models.swift:82` `terminalURL` has no caller; the phone terminal is `iOS/NativeTerminalScreen.swift` over meshd `pty`. The phone still probes `:7820` (`iOS/MeshStore.swift:481`) and nags when it is down (`iOS/ContentView.swift:559-565`). Confirm the direction before investing here.
- `mesh upgrade` refreshes `public/` only (`bin/mesh:1044-1066`); `src/server.ts` changes reach users only via a fresh install.
- `mesh uninstall` does not stop this service (`bin/mesh:2232-2244` handles meshd only); read, not run.
- Imports `../../meshd/redact` (`src/server.ts:10`); it cannot run without the meshd tree beside it.
- `package.json:8-9` scripts point at files that do not exist; default session `spine-test` (`src/server.ts:457`) is a leftover.
**SDLC stage:** Build / Maintain — a live service with an unclear future.
**Map:** see the file list above; `docs/agents/CODEMAP.md` section `install/payload/rmux-bridge/`

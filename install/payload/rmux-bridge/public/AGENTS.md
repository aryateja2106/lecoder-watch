# install/payload/rmux-bridge/public/ — the web page (and its terminal library) that the terminal bridge serves

**Read first:** `index.html`, `../src/server.ts:445-456` (the only four paths served)
**Surface:** daemon
**Serialized (one agent at a time):** none
**Prove a change:** `sh scripts/check-bridge-auth.sh` (assets need the token) and `sh scripts/check-phone-input-and-wake.sh` (vendored xterm.js input attribute)
**Traps:**
- The server serves exactly `/`, `/xterm/xterm.css`, `/xterm/xterm.js`, `/xterm/addon-fit.js` (`../src/server.ts:445-456`); a new asset needs a route.
- `mesh upgrade` copies this whole folder to users (`bin/mesh:1048-1066`), so any file here ships.
- See `../AGENTS.md`: the phone may no longer open this page.
**SDLC stage:** Build — the web page of a legacy service (see [docs/sdlc/3-build.html](../../../../docs/sdlc/3-build.html))
**Map:** see the file list above.

# web/shots/ — the screenshots the landing page shows (phone, watch, Mac), captured from real builds

**Read first:** [../AGENTS.md](../AGENTS.md) (how the landing page is built and checked); `web/index.html` for where each image is used.
**Surface:** media
**Serialized (one agent at a time):** none
**Prove a change:** `sh scripts/check-web-docs.sh` (every image the page references exists); look at the page in a browser at phone width.
**Traps:** replace an image only with a capture from the current build (an old screen on the landing page is a promise the product no longer keeps); keep file names stable, the HTML references them by name.
**SDLC stage:** Deploy — marketing surface; images change when a screen ships (see [docs/sdlc/5-ship.html](../../docs/sdlc/5-ship.html))
**Map:** see the file list above

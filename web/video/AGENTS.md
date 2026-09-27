# web/video/ — two short looping clips on the landing page (the watch on a wrist, a Raspberry Pi desktop)

**Surface:** media — used by `web/index.html:153` (`wrist.mp4`) and `:212` (`pi-desktop.mp4`), each with a poster from `web/shots/`.
**Prove a change:** `sh scripts/check-web-docs.sh`, then open the page; no check reads these files.
**Traps:** replacing a clip without its poster frame leaves a mismatched first frame; every landing section uses a single real capture of the current build (`docs/factory/runs/2026-09-22T140000Z-landing-relaunch.md:22`), so no mock-ups.

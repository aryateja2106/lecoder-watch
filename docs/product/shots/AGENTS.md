# docs/product/shots/ — real screenshots of the current iPhone and Watch app, used by the getting-started guide and the website

**Surface:** media
**Regenerate, never hand-edit:** `sh scripts/product-shots.sh [iphone-udid] [watch-udid]` (real simulator captures, never a mock, `scripts/product-shots.sh:2-4`).
**Prove a change:** `bun scripts/build-web-docs.ts && sh scripts/check-web-docs.sh` — shots are copied to `web/shots/` (`scripts/build-web-docs.ts:8-9`) and each embedded one must exist and be over 10 KB (`scripts/check-web-docs.sh:11-15`).
**Traps:** renaming a PNG breaks `docs/getting-started.md`, `docs/product/design-system.md` and the served page together; the publish finish line needs at least 6 committed PNGs here, each over 10 KB (`scripts/check-published.sh:284-288`). 18 files, 3.8 MB today.

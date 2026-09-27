# web/ — the public website at lesearch.ai: the landing page, the getting-started guide, the privacy promise and the brand board

**Read first:** `index.html` (the landing page), `vercel.json` (redirects: `/install.sh`, `/beta`, `/github`, `/changelog`, `/roadmap`), `privacy.html` (a public promise, root AGENTS.md design principle 2)
**Surface:** web
**Serialized (one agent at a time):** `privacy.html` (must agree with `install/payload/meshd/telemetry.ts` and the README Telemetry section), `vercel.json`
**Prove a change:** `sh scripts/check-web-docs.sh` and `sh scripts/check-brand.sh` (both OK on 2026-09-27); after a deploy, `sh scripts/check-published.sh` (network; the release finish line)
**Traps:**
- `getting-started.html` and `shots/` are generated. Edit `docs/getting-started.md`, then `bun scripts/build-web-docs.ts`; `check-web-docs.sh:11` fails a hand edit. Shots are copied from `docs/product/shots/` (`build-web-docs.ts:8-9`); all 11 match byte-for-byte today.
- `check-published.sh:185` greps the live landing page for the daemon version (`server.ts:30`, now 0.8.0, shown at `index.html:138,220`). Bump the daemon without bumping this page and the finish line goes red.
- `check-web-docs.sh:18-21` requires these links on the landing page: `/getting-started`, `/install.sh`, the `from-users` issues query; `privacy.html` must describe "Report a problem".
- Deploy is manual: `vercel deploy --prod` from `web/` to Vercel project `lesearch-website` (`docs/overnight/2026-09-21/HANDOFF-2026-09-22-publish.md:16-17`). Publishing is Arya's call; no CI deploys this folder (unverified beyond `.github/workflows/ci.yml` having no web step).
- `docs/agents/CODEMAP.md:27` still says mesh.lesearch.ai; the live domain is lesearch.ai (`check-published.sh:45`).
- `shots/iphone-remote-pi.png` is referenced by no page (git grep) — dead weight on the site.
**SDLC stage:** Deploy (the public face; `check-published.sh` gates release) and Maintain (privacy page kept true).
**Map:** INDEX.md (10 direct entries; generate with `python3 scripts/folder-index.py`)

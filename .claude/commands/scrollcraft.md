---
name: scrollcraft
description: Build a scroll-driven Mesh landing page (web/) with a unique grammar and one peak. Does not replace Claude's built-in /design.
---

Read `docs/agents/workflows.md`, then follow `.claude/skills/scrollcraft/SKILL.md`.

Mesh constraints (these win over the skill's defaults):

- The shipped page is `web/index.html`. `web/privacy.html` is a public promise — do not rewrite it.
- Brand tokens already live on that page: `#191919` / `#e9e9e7` / JetBrains Mono. Brand rules win.
- Build from our own footage and screenshots (`docs/recordings/`, `reference-video/`, product stills). Do not spend a `KIE_AI_API_KEY` unless Arya asks.
- Do not add a repo-root `package.json` (factory stack detect). Install `playwright-core` only inside the scrollcraft workspace if verification needs it.
- Workspace is `web/.scrollcraft` via `web/.scrollcraft.json`. Do not dump builds at repo root.
- Leave Claude Code's built-in `/design` alone. After artboards exist, this skill still owns the scroll page.
- Do not run `/impeccable init` at the repo root.

# .agents/ — the shared folder other AI coding tools (mainly Codex) read for skills and rules, plus old June 2026 redesign notes

**Read first:** `skills/AGENTS.md` (what Codex sees), `rules/codemap.md` (read the map before grepping), root `AGENTS.md` (the real brief)
**Surface:** agent-config
**Serialized (one agent at a time):** `skills/factory-*` (pointers to `.claude/skills/factory-*`; keep them pointers)
**Prove a change:** no dedicated check — add `scripts/check-skill-copies.sh` (pointer skills name an existing canonical file; tracked copies match `.claude/skills/`)
**Traps:**
- Load-bearing: `docs/factory/CHARTER.md:53` lists `.agents/**`.
- `block-merge.sh:59-62` blocks Bash commands that name `.agents/` and contain a space-preceded `>`, `sed`, `rm`, `cp`, `mv`, `tee`; use the editor tool to write.
- `.gitignore:49-50` ignores `skills/*` except `factory-*`: a NEW file under `skills/` (including `skills/AGENTS.md`) is silently untracked.
- `REDESIGN-BRIEF.md`, `REDESIGN-STATUS.md`, `RELAUNCH.md` are June 2026 snapshots (`REDESIGN-STATUS.md:3`) naming branch `codex/redesign-exp-1`; `REDESIGN-BRIEF.md:3` claims `.agents/` is gitignored — it is tracked. Do not act on them.
- Which tool reads `rules/` and `workflows/` (`trigger: always_on` frontmatter) is unverified — likely Antigravity (`agy`).
**SDLC stage:** Build — skills and always-on rules for the non-Claude harnesses; the root `.md` files are stale June notes, not intents (see [docs/sdlc/3-build.html](../docs/sdlc/3-build.html))
**Map:**
| path | what |
|---|---|
| `skills/` | 16 skills (7 factory pointers, 9 tracked copies) |
| `rules/` | `codemap.md`, `graphify.md` — always-on |
| `workflows/graphify.md` | graphify pipeline trigger |
| `design/` | 12 HTML mockups, June 2026 (stale) |
| `REDESIGN-*.md`, `RELAUNCH.md` | June 2026 hand-offs (stale) |

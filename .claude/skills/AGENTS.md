# .claude/skills/ — 70 reusable instruction packs ("skills") that tell Claude Code how to do recurring jobs: plan, spec, test, review, run the factory queue, build apps

**Read first:** root `CLAUDE.md` "Agent skills" section (which packs are the default), `factory-implement/SKILL.md` (the queue workflow), `../../install/payload/share/skills/` (skills shipped to users)
**Surface:** agent-config
**Serialized (one agent at a time):** `factory-*/SKILL.md` (canonical for all three harnesses; `.agents/skills/factory-*` and `.cursor/skills/factory-*` point here)
**Prove a change:** `sh scripts/check-mesh-skills.sh` (only the 5 product-skill symlinks, `check-mesh-skills.sh:37-42`); everything else: no dedicated check — add `scripts/check-skill-copies.sh` (openspec copies identical, symlinks resolve, every folder has a `SKILL.md`)
**Traps:**
- 7 entries are symlinks: `app-brief`, `apple-native-apis`, `mesh-knowledge`, `native-app-builder`, `pwa-local-app-builder` → `install/payload/share/skills/` (edit there; root `AGENTS.md:124`); `to-prd`, `writing-great-skills` → `.agents/skills/`.
- 53 `.cursor/skills/*` entries are symlinks INTO this folder: renaming or deleting a skill here breaks Cursor.
- `openspec-*` exist three times (here, `.cursor/skills`, `.codex/skills`), identical today; edit all or none.
- `grill-with-docs`, `handoff`, `prototype`, `tdd`, `teach` also have real copies in `.agents/skills/` (same content; this copy adds `agents/openai.yaml`).
- Overlaps with no router rule: `tdd`/`test-driven-development`, `grill-me`/`grilling`/`grill-with-docs`, `code-review`/`code-review-and-quality`, `triage`/`factory-triage`, `ask-matt`/`using-agent-skills`.
- `overnight-slice/SKILL.md:12-20` gates on building, not running, and reverts with `git checkout -- .` — conflicts with AGENTS.md rule 1.
**SDLC stage:** Plan → Maintain; skills are the playbook's "policy as code" (advisory; `../hooks/` holds the must-hold rules).
**Map:** INDEX.md (133 tracked files; one row per skill: real or symlink target, one-line purpose).

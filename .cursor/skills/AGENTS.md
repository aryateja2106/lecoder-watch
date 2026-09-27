# .cursor/skills/ — the instruction packs Cursor sees; almost all are links to the Claude Code copies so there is one version, not three

**Read first:** `factory-implement/SKILL.md` (pointer to the canonical workflow), `.claude/skills/AGENTS.md` (where the real content lives)
**Surface:** agent-config
**Serialized (one agent at a time):** `factory-*` — must stay thin pointers to `.claude/skills/factory-*` (`factory-implement/SKILL.md:8-9`)
**Prove a change:** `sh scripts/check-mesh-skills.sh` (the 5 product-skill symlinks here, `check-mesh-skills.sh:37-42`); rest: no dedicated check — add `scripts/check-skill-copies.sh` (every symlink resolves; openspec copies identical)
**Traps:**
- 58 of 71 entries are symlinks: 53 → `../../.claude/skills/<x>`, 5 → `../../install/payload/share/skills/<x>`. Edit the target, never the link. Renaming a `.claude/skills` folder breaks the link here.
- `openspec-*` (6) are real copies, identical to `.claude/skills/` and `.codex/skills/` today.
- `factory-status`, `factory-tune` differ from `.agents/skills/` twins only in the title line.
- `meshwatch-ui-taste` is not here, so Cursor has no native-UI taste skill.
**SDLC stage:** Build (3.3 skills for the Cursor harness).
**Map:** INDEX.md (71 tracked entries; generate from `readlink`).

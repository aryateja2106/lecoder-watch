# .agents/skills/ — the instruction packs Codex (and other tools that use the shared folder) sees: the factory queue workflow plus a few design and teaching skills

**Read first:** `factory-implement/SKILL.md` (pointer to the canonical workflow), `.claude/skills/factory-implement/SKILL.md` (the workflow), `meshwatch-ui-taste/SKILL.md` (native UI taste)
**Surface:** agent-config
**Serialized (one agent at a time):** `factory-*` — must stay thin pointers to `.claude/skills/factory-*`
**Prove a change:** no dedicated check — add `scripts/check-skill-copies.sh` (each pointer names an existing canonical file; tracked copies equal `.claude/skills/<x>`)
**Traps:**
- `.gitignore:49-50`: everything here except `factory-*` is ignored. `grill-with-docs`, `handoff`, `prototype`, `tdd`, `teach`, `to-prd`, `writing-great-skills`, `meshwatch-ui-taste`, `claude-design-to-meshwatch-swiftui` are tracked only because they predate the rule; new files (this `AGENTS.md` too) need `git add -f`.
- Root `AGENTS.md:124` calls this folder per-machine and gitignored — half-true (see above).
- `factory-status`, `factory-tune` differ from `.cursor/skills/` twins only in the title line (Codex vs cursor-agent).
- `meshwatch-ui-taste` and `claude-design-to-meshwatch-swiftui` exist only here: Claude Code and Cursor cannot see them.
- `check-mesh-skills.sh:43-45` fails if a product skill (`app-brief`, …) appears here as a real folder; product skills belong in `install/payload/share/skills/`.
- Whether Codex reads this folder or `.codex/skills/` is unverified; root `CLAUDE.md:59-60` says this one.
**SDLC stage:** Build (3.3 skills for the non-Claude harness).
**Map:** INDEX.md (27 tracked files, 16 skills).

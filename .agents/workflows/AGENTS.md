# .agents/workflows/ — one saved routine that tells a non-Claude AI tool to rebuild the code knowledge graph

**Read first:** `graphify.md` (the workflow), `.claude/skills/graphify/SKILL.md` (the pipeline it defers to)
**Surface:** agent-config
**Serialized (one agent at a time):** none
**Prove a change:** no dedicated check — add `scripts/check-harness-rules.sh`; manual proof is `graphify update .` in the repo root
**Traps:**
- `graphify.md:8` says "follow the graphify skill" but no graphify skill exists under `.agents/skills/`; the only copy is `.claude/skills/graphify/`.
- This folder's consumer is unverified (likely Antigravity); an `AGENTS.md` here may be listed as a workflow.
**SDLC stage:** Maintain — keeps the navigation graph current.
**Map:** see the file list above (1 file, 10 lines).

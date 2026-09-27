# .agents/workflows/ — one saved routine that tells a non-Claude AI tool to rebuild the code knowledge graph

**Read first:** `graphify.md` (the workflow), `.claude/skills/graphify/SKILL.md` (the pipeline it defers to)
**Surface:** agent-config
**Serialized (one agent at a time):** none
**Prove a change:** no dedicated check — add `scripts/check-harness-rules.sh`; manual proof is `graphify update .` in the repo root
**Traps:**
- `graphify.md:8` says "follow the graphify skill" but no graphify skill exists under `.agents/skills/`; the only copy is `.claude/skills/graphify/`.
- This folder's consumer is unverified (likely Antigravity); an `AGENTS.md` here may be listed as a workflow.
**SDLC stage:** Build — rebuilds the code knowledge graph agents navigate by (playbook 3.2 institutional knowledge) (see [docs/sdlc/3-build.html](../../docs/sdlc/3-build.html))
**Map:** 2 tracked files; run `git ls-files .agents/workflows` to list them.

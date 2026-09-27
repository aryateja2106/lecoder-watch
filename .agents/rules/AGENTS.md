# .agents/rules/ — two always-on instructions for non-Claude AI tools: read the code map first, and use the knowledge graph for "how does X relate to Y"

**Read first:** `codemap.md` (map before grep), `graphify.md` (graph queries), `docs/agents/CODEMAP.md` (the map itself)
**Surface:** agent-config
**Serialized (one agent at a time):** none
**Prove a change:** no dedicated check — add `scripts/check-harness-rules.sh` (the `.agents/rules/*.md` and `.cursor/rules/*.mdc` versions say the same thing)
**Traps:**
- Diverged from the Cursor copies: `.cursor/rules/graphify.mdc:8` makes graphify MANDATORY before any Read/Grep; `graphify.md:11` here is advisory. Pick one wording.
- Files here are rules; this `AGENTS.md` may itself be loaded as a rule by the consuming tool (unverified which tool reads this folder — `trigger: always_on` suggests Antigravity).
- `graphify.md:11` assumes `graphify-out/graph.json` exists; it is generated, not committed (only `GRAPH_REPORT.md` is, per `.gitignore:56`).
**SDLC stage:** Build — institutional knowledge (playbook 3.2): cheap navigation before reading source (see [docs/sdlc/3-build.html](../../docs/sdlc/3-build.html))
**Map:** see the file list above: `codemap.md` (18 lines), `graphify.md` (14 lines).

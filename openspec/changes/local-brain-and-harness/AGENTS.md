# openspec/changes/local-brain-and-harness/ — August research on running an AI agent's "brain" on your own machines, and what to adopt instead of building

**Read first:** `proposal.md` (findings, non-goals, owner questions), `docs/adr-2026-09-22-local-brains-and-streaming-moe.md` (what was measured since), `tasks.md`
**Surface:** specs
**Serialized (one agent at a time):** `tasks.md`
**Prove a change:** `openspec validate local-brain-and-harness --no-interactive`
**Traps:**
- Partly superseded: 0/11 tasks ticked (`openspec list`) while the September ADRs record real measurements (Needle 2, edge0) and the daemon already has a `brain` capability (`docs/agents/CONTRACTS.md:125`, nothing gates it). Do not redo this research; update `tasks.md` from the ADRs.
- `tasks.md:21-31` names specific models. Arya picks the model per device; never download or run one to tick a task without asking him.
- The requirement that matters (`specs/agent-brain/spec.md:7-24`): any agent runtime runs through the persistent multiplexer sessions, never per-command process spawning.
- `specs/agent-brain/spec.md:54-62`: README and `web/index.html` must not call the product locally powered while the default brain is hosted. Check `web/` copy against it before publishing.
**SDLC stage:** Plan, Design — a research-backed proposal and requirements; no Build yet (see [docs/sdlc/1-plan.html](../../../docs/sdlc/1-plan.html), [docs/sdlc/2-design.html](../../../docs/sdlc/2-design.html))
**Map:** see the file list above (`proposal.md`, `tasks.md`, `specs/agent-brain/spec.md`)

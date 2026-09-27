# .claude/agents/ — the two specialist helper assistants Claude Code can hand work to: an independent checker and a devil's advocate

**Read first:** `factory-verifier.md` (the fresh-context check), `factory-critic.md` (the case against), `docs/factory/CONTRACT.md` (their inputs)
**Surface:** agent-config
**Serialized (one agent at a time):** `factory-verifier.md` — root `CLAUDE.md:46` delegates all verification to it by name
**Prove a change:** no dedicated check — add `scripts/check-subagents.sh` (frontmatter has `name`, `description`, `tools`; names match what `CLAUDE.md` and the factory skills call)
**Traps:**
- Claude Code loads every `*.md` here as a subagent definition; this `AGENTS.md` has no frontmatter and may be skipped or warned about (documented convention, not tested here). Move it out if it causes noise.
- Both agents get `Bash` and `WebFetch` (`factory-verifier.md:4`, `factory-critic.md:4`); they are read-only by instruction, not by tool list.
- The verifier must be given the diff, not the implementer's story (`factory-verifier.md:22`); passing a summary defeats it (AGENTS.md rule 1).
**SDLC stage:** Test, Deploy — fresh-context verification and adversarial review before a human sees a PR (see [docs/sdlc/4-test.html](../../docs/sdlc/4-test.html), [docs/sdlc/5-ship.html](../../docs/sdlc/5-ship.html))
**Map:** see the file list above (2 files).

# .cursor/rules/ — three instructions Cursor loads into every session: the factory's no-merge policy, read the code map first, use the knowledge graph

**Read first:** `factory.mdc` (policy), `codemap.mdc` (navigation), `docs/factory/CHARTER.md` (the source the policy summarises)
**Surface:** agent-config
**Serialized (one agent at a time):** `factory.mdc`
**Prove a change:** no dedicated check — add `scripts/check-harness-rules.sh` (claims in `factory.mdc` match `gates.sh`, `CHARTER.md`, root `CLAUDE.md`)
**Traps:**
- `factory.mdc:29` describes `deep` as "+ auth surface + architecture assertions"; `gates.sh:178-213` has neither an auth gate nor a real architecture rule.
- `graphify.mdc:8` makes graphify MANDATORY before any read; `.agents/rules/graphify.md:11` is advisory. They were meant to match.
- All three are `alwaysApply: true` — every token here is paid on every Cursor request; keep them short.
- Cursor may also treat a plain `.md` here as a rule (unverified); this `AGENTS.md` could be loaded as one.
**SDLC stage:** Build, Deploy — institutional knowledge (playbook 3.2) and the merge policy (5.2), advisory only because Cursor has no hook (see [docs/sdlc/3-build.html](../../docs/sdlc/3-build.html), [docs/sdlc/5-ship.html](../../docs/sdlc/5-ship.html))
**Map:** 4 tracked files; run `git ls-files .cursor/rules` to list them — `factory.mdc` (63 lines), `codemap.mdc` (15), `graphify.mdc` (21).

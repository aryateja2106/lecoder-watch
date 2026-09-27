# .cursor/ — project settings for Cursor (an AI code editor): always-on rules, slash commands, and skills that mostly point back to the Claude ones

**Read first:** `rules/factory.mdc` (the policy Cursor always loads), `commands/factory.md` (control room pointer), `docs/factory/CONTRACT.md`
**Surface:** agent-config
**Serialized (one agent at a time):** `rules/factory.mdc` — Cursor's only copy of the no-merge policy
**Prove a change:** no dedicated check — add `scripts/check-harness-rules.sh` (rules agree with `.agents/rules/` and root `CLAUDE.md`)
**Traps:**
- Cursor has NO hook: nothing mechanically stops a merge; `rules/factory.mdc` asks nicely. Claude and Codex run `block-merge.sh`.
- `rules/factory.mdc:29` says `gates.sh deep` adds "auth surface"; `gates.sh:178-213` has no such gate.
- `commands/factory.md:16` says the charter caps pending reviews at two; `docs/factory/CHARTER.md:151` says more than 3.
- `hooks/state/` is ignored harness output (`.gitignore:42`).
**SDLC stage:** Build (rules, skills) for the Cursor harness.
**Map:**
| path | what |
|---|---|
| `mcp.json` | codegraph MCP server |
| `rules/` | `factory.mdc`, `codemap.mdc`, `graphify.mdc` (all `alwaysApply`) |
| `commands/` | `/factory`, `/factory-tune` pointers; 6 `opsx-*` |
| `skills/` | 71 entries, 58 symlinks |

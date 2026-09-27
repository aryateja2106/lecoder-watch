# .claude/ — the rulebook and toolbox for Claude Code (the AI coding assistant) when it works on this repo

**Read first:** `docs/factory/CONTRACT.md` (queue rules), `docs/factory/CHARTER.md` (what is allowed), `settings.json` (what is denied)
**Surface:** agent-config
**Serialized (one agent at a time):** `settings.json`, `hooks/block-merge.sh`, `scripts/gates.sh` — all policy; edit only when the human asks in this session (root `CLAUDE.md:42-43`)
**Prove a change:** `./.claude/scripts/gates.sh fast` (ends `FACTORY_GATES: level=fast status=GREEN`); hook changes: no dedicated check — add `scripts/check-block-merge.sh` that feeds canned commands to the hook
**Traps:**
- `hooks/block-merge.sh:59-62` refuses ANY Bash command that names `.claude/`, `.agents/`, `.codex/` and contains a space-preceded `>`, `sed`, `tee`, `rm`, `mv`, `cp` — even `diff … >/dev/null`. Read with `cat -n`/`awk`; write with the editor tool.
- Whole folder is load-bearing: `docs/factory/CHARTER.md:52` — any change forces `deep` gates and a human read.
- `worktrees/` holds full stale checkouts (git-excluded, `.git/info/exclude:13`); exclude it from every grep (AGENTS.md rule 2).
- `settings.json` has an uncommitted change (`Edit(AGENTS.md)` → `Edit(./AGENTS.md)`); do not commit it unasked.
- `settings.local.json` is machine-local and globally git-ignored; never rely on it for shared policy.
**SDLC stage:** Build, Test — skills, hooks and subagents constrain every Claude Code session, and `scripts/gates.sh` verifies it (see [docs/sdlc/3-build.html](../docs/sdlc/3-build.html), [docs/sdlc/4-test.html](../docs/sdlc/4-test.html))
**Map:**
| path | what |
|---|---|
| `CLAUDE.md` | 3 lines: `/graphify` → `skills/graphify/SKILL.md` |
| `settings.json` | allow git read + `gates.sh`; deny merge, force-push, Edit of 6 policy files; wires `block-merge.sh` (`:26-36`) |
| `agents/` | 2 subagents: `factory-verifier`, `factory-critic` |
| `commands/` | `/factory`, `/factory-tune`, `/opsx:*` |
| `hooks/` | `block-merge.sh` (live), `stop-published.sh` (dormant) |
| `scripts/gates.sh` | the factory verdict |
| `skills/` | 70 skills — see `skills/AGENTS.md` |

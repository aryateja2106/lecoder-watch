# .claude/scripts/ — the one script that gives a pass/fail verdict on any change before it can become a pull request

**Read first:** `gates.sh` (the verdict), `../../.factory/gates.conf` (which gates are required), `../../package.json` (what each gate runs)
**Surface:** checks
**Serialized (one agent at a time):** `gates.sh` — policy file; Edit is denied in `.claude/settings.json:20`; change only when the human asks (root `CLAUDE.md:42-43`)
**Prove a change:** `./.claude/scripts/gates.sh fast` → last line `FACTORY_GATES: level=fast status=GREEN passed=2 failed=0 …` (measured 2026-09-27, ~40 s). `full` runs xcodebuild for minutes; pre-PR only.
**Traps:**
- The gates are defined by `package.json` script names (`gates.sh:100,122-129,156-157` → `package.json:6-9`). Rename a script and the gate becomes SKIP, then MISCONFIGURED (`gates.sh:85-91`).
- `deep` is thinner than it sounds: the architecture block is a commented example that always passes (`gates.sh:201-213`); `audit` is `npm audit` over a `package.json` with no dependencies (`:181`; result without a lockfile unverified).
- `.cursor/rules/factory.mdc:29` says `deep` adds an "auth surface" gate; none exists here.
- Quote the `FACTORY_GATES:` line verbatim (`gates.sh:237-240`); RED and MISCONFIGURED both block.
- A green gate is not proof a feature works (AGENTS.md rule 1).
**SDLC stage:** Test — the single verification command the playbook asks for.
**Map:** see the file list above (1 file, 242 lines).

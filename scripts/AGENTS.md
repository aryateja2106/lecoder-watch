# scripts/ — the automatic tests that prove the product still works, plus the release and repo-map tools

**Read first:** docs/agents/CHECKS.md (what each file proves, one line), scripts/check-all.sh (how checks are found and run), CLAUDE.md "The gate" (which command to run when)
**Surface:** checks
**Serialized (one agent at a time):** `check-all.sh` (its `DEPS` line at :14 is also read by `gate-types.sh:33`), `gate-*.sh` (wired to the factory gate by package.json:6-9), `check-published.sh` (release finish line; reads PUBLISHED.md and BLOCKED.md)
**Prove a change:**
- Loop: `./.claude/scripts/gates.sh fast` (about 6 s: meshd `tsc`, Shared/ typecheck, script syntax, published links)
- One check: `sh scripts/check-<name>.sh`, or for Swift: `DEPS=(Shared/Models.swift …); swiftc -Onone -o /tmp/c scripts/check-<name>.swift "${DEPS[@]}" && /tmp/c`
- New or renamed file: `sh scripts/check-codemap.sh` (red → `python3 scripts/codemap-index.py`)
- Before a PR: `./.claude/scripts/gates.sh full` (minutes; runs check-all + three xcodebuilds). Quote the `FACTORY_GATES:` line verbatim.

**Traps:**
- Never edit an existing `check-*` in an unattended run; add a new one instead (CLAUDE.md:44). No hook enforces this, so the rule is yours to keep.
- check-all is NOT offline. It globs `check-overnight.sh`, which turns on live fleet, brain, watch and simulator checks (check-overnight.sh:25-37). `MESH_OVERNIGHT_SKIP="fleet brain sim-fleet …"` opts out (:8).
- A `SKIP` exits 0. Missing bun/tmux/xcrun or an unset `MESH_*_LIVE` flag gives a silent green (e.g. check-clean-install.sh:15). Read the output. check-intent, check-clean-install and check-sim-fleet skip on every normal run (docs/overnight/2026-09-21/gate-full-publish.txt:62,94,192).
- Swift checks must build with `-Onone` against check-all's 9-file `DEPS` (check-all.sh:4-6,14). A subject outside those files will not compile. Pass multi-word args as an array (AGENTS.md rule 7).
- Only one simulator run at a time: a second check-all, `gates.sh full` or `xcodebuild test` kills the first one's runner → `INCONCLUSIVE` (check-ios-smoke.sh:129).
- check-published.sh hardcodes branch `feat/lesearch-ai-overnight-2026-09-21` and PR 133 (:43-44), and every `## ` heading in BLOCKED.md must appear in PUBLISHED.md or check-all goes red (:106-110).
- Live checks boot throwaway daemons on side ports and never kill a listener. Keep it that way (AGENTS.md rules 5 and 8; check-approve-path.sh:24).

**SDLC stage:** Test (the Stage 4 "one command" is `gates.sh full` → `check-all.sh`), Deploy (`check-published.sh`, `release-*.sh`), Maintain (`feedback-to-issues.ts`, live fleet probes).
**Map:** scripts/INDEX.md once generated (125 tracked files); until then docs/agents/CHECKS.md

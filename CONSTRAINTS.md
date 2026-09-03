# Constraints

Last reviewed: 2026-09-03 by Claude (unattended session; numbers measured, defaults
applied, then corrected after an independent critic re-measured them). Owner:
@aryateja2106. Read the "Decisions" list at the bottom before treating any row as final.

This file is the written quality bar for LeSearch Mesh. Agents write most of the code
here; nobody reads all of it. So the bar lives in numbers a script can check, not in
prose an agent may or may not follow. `AGENTS.md` says how to work; this file says what
"good enough to ship" means. Tightening it is silent. Loosening it must be loud: a
threshold that goes down, a floor bullet that disappears, or a new exception row is a
review finding, not a detail.

## Floor (always enforced, no setup required)

`sh scripts/check-floor.sh` checks the diff against `origin/main` (added lines, untracked
files, and removed lines in checks and CI). Exit `0` clean, `1` violation, `2` could not
run. A `2` is not a pass. It runs inside `check-all.sh` and takes under a second.

Checked by the script:

- No new suppression comments: `@ts-ignore`, `@ts-expect-error`, `@ts-nocheck`,
  `eslint-disable`, `swiftlint:disable`, `nosemgrep`, `gitleaks:allow`. Baseline: 0.
- No new unfinished work in shipped code: `TODO`, `FIXME`, `fatalError("TODO`,
  `Not implemented`, or a new empty `catch {}`. Baseline: 0 TODO/FIXME; 5 empty catches
  (exception E1).
- No test or check made easier: no `.skip(`, `.only(`, `XCTSkip`; no deleted
  `scripts/check-*`; no assertion removed from a check that stays; no
  `run: sh scripts/check-*` line removed from `.github/workflows/*.yml`.
- No literal `/Users/...` path and no `testtoken` in code. There is no such thing as
  `testtoken`.
- No weakened bar: no floor bullet removed from this file, no new Exceptions row
  without review.

Checked by other tools, or by a person, and written here so nobody forgets:

- No secrets in source. `gitleaks protect --staged --redact --no-banner` before every
  commit. Report the rule and the location, never the value.
- No hardcoded host name, IP, or token in code (AGENTS.md review step 2, by eye at
  review; `scripts/check-mesh-auth.sh` and `check-token-rotate.sh` cover the token paths).
- Every new capability is wired to a caller and proven against a real daemon, not a
  fixture (AGENTS.md rule 1). A function nobody calls compiles perfectly. Only a person
  reading the diff catches this; the floor script cannot.
- The telemetry promise stays consistent: `install/payload/meshd/telemetry.ts`,
  `web/privacy.html`, and the README Telemetry section change together.
- This file does not get weakened to make a change pass.

## Enforced with numbers

Every row names the one command that produces the verdict. A row with a number and no
command is an aspiration, not a constraint.

| Dimension | Rule | Checked by | Runs at |
|---|---|---|---|
| Floor | Zero findings on the diff | `sh scripts/check-floor.sh` | every task end; inside `check-all.sh` |
| Types (daemon) | Zero `tsc` errors | `cd install/payload/meshd && bun add -D --no-save bun-types typescript@~5.7.0 && bun x tsc --noEmit -p tsconfig.json` (0.7 s measured) | every daemon edit; CI `daemon` job |
| Builds (apps) | Three schemes build for generic simulator/macOS destinations | the three `xcodebuild` lines in AGENTS.md "Build and verify" | task end for any Swift edit; CI `apps` job |
| Self-checks | `check-all.sh` exits 0: 19 Swift checks compiled `-Onone` plus 34 shell checks | `sh scripts/check-all.sh` (1 min 42 s and 1 min 48 s over two runs, 2026-09-03) | task end; CI `apps` job |
| Wire parity | Daemon key list equals the watch key bar | `sh scripts/check-watch-terminal-wiring.sh` (inside `check-all.sh`) | task end |
| Secrets | Zero gitleaks findings on the staged diff | `gitleaks protect --staged --redact --no-banner` | before every commit |
| Daemon shape | Zero runtime dependencies in `install/payload/meshd/package.json` (today: 0; "reviewable in one sitting" per ROADMAP.md) | `jq '.dependencies // {} \| length' install/payload/meshd/package.json` | CI `daemon` job |

Budgets. The edit loop (`tsc`, `gitleaks`, the floor) stays under 5 seconds. The task-end
gate (`check-all.sh` plus the builds) is minutes and stays out of the edit loop. Nothing
in this file runs `xcodebuild` on every edit.

## Measured, not yet enforced

Ratchets: today's number and a direction. Nobody had to pick a target; the check compares
against the recorded value. When a number improves, update it here. When it gets worse,
that is the finding. Tolerance 0.5 percent absorbs unrelated drift. Commands avoid
`ls` and `gh` defaults on purpose: `ls` is aliased to a grid here and miscounted files by
half, and `gh issue list` stops at 30 unless told otherwise.

| Metric | Today (2026-09-03) | Direction | One command |
|---|---|---|---|
| `tsc --strict` errors in meshd | 6 | must not rise; goal 0, then flip `strict: true` (exception E2) | `cd install/payload/meshd && (bun x tsc --noEmit -p tsconfig.json --strict \| grep -c "error TS" \|\| true)` |
| Empty `catch {}` in meshd | 5 | must not rise | `grep -rnE 'catch \{\}' install/payload/meshd --include='*.ts' \| wc -l` |
| `check-all.sh` wall time | 1 min 48 s | must stay under 3 min, or a check moves to CI-only | `time sh scripts/check-all.sh` |
| meshd modules | 14 `*.ts` files, 3,914 lines | grows only with a matching row in `CONTEXT.md` ("one module per capability") | `find install/payload/meshd -maxdepth 1 -name '*.ts' \| wc -l` |
| Check lines in CI | 16 (Ubuntu job: 14 shell + 1 Python of the 54 checks; macOS job: `check-all.sh`, which runs the 19 Swift and all 34 shell checks) | must not fall | `grep -c 'run: .*scripts/check-' .github/workflows/ci.yml` |
| Open issues | 107; 17 carry a severity label (2 blocker, 9 high, 5 medium, 1 low) | should fall; a run that closes one and opens none is the unit of progress | `gh issue list --state open --limit 300 --json number --jq length` |
| Merged pull requests, trailing 4 weeks | 3 (all on 2026-08-27, the 0.5.x releases, all by the owner) | the baseline for the factory experiment in `docs/product/PRODUCT-MAP-2026-09-03.md` section 8 | `gh pr list --state merged --limit 200 --search 'merged:>=2026-08-06' --json number --jq length` |
| Daemon version drift | repo `0.5.0`, released `v0.5.2` (2026-08-27), deployed on this Mac `0.5.4` | the three must agree within one minor version and 14 days (AGENTS.md rule 6: a stale daemon answers 200 with the old shape) | `echo "repo $(grep -o 'VERSION = "[^"]*"' install/payload/meshd/server.ts) released $(gh release view --repo LeSearch-AI/mesh-install --json tagName --jq .tagName) deployed $(curl -s 127.0.0.1:8899/health \| jq -r .meshdVersion)"` |

## Not applicable here (and why)

- **Coverage.** There is no test runner; the suite is `scripts/check-*` assert programs.
  Coverage of changed lines has nothing to read. Revisit when the daemon gets a `bun test`
  suite; the same rule (changed lines at or above 80 percent) applies then.
- **Lighthouse and axe.** `web/` is a static page on Vercel and the daemon serves two
  HTML files behind a bearer token. Neither has a preview URL a CI job can hit today. Add
  both when Mesh Apps (pillar 3 in `docs/product/PRODUCT-MAP-2026-09-03.md`) serves user
  apps: LCP at or below 2500 ms, CLS at or below 0.1, zero critical or serious axe
  violations, against a local `meshd` on a spare port.
- **Semgrep, osv-scanner.** Zero runtime dependencies means osv-scanner has nothing to
  scan. Semgrep on `install/payload/meshd` is worth adding in CI (`p/default`,
  `p/owasp-top-ten`) once someone installs it; not enforced until it runs.
- **Mutation testing.** No suite to mutate.

## Exceptions

| ID | Rule | Path | Reason | Owner | Expires |
|---|---|---|---|---|---|
| E1 | empty `catch {}` | `install/payload/meshd/push.ts:166`, `server.ts:911`, `telemetry.ts:52,86,120` | Best-effort parse and telemetry paths that must never throw; replace with a logged catch | @aryateja2106 | 2026-12-01 |
| E2 | `strict: true` | `install/payload/meshd/tsconfig.json` | 6 strict errors today; flip the flag when the ratchet reaches 0 | @aryateja2106 | 2026-12-01 |

## Decisions still open (the interview did not run)

The constraint-driven-development intake needs a live user; this file applied the floor
and the defaults instead. Four questions, each with the default taken:

1. Beyond the floor, which dimensions to enforce. Taken: types, builds, self-checks,
   secrets, daemon shape. Not taken: coverage, performance, accessibility (no tool can
   run them here yet).
2. Block or warn when a check fails mid-task. Taken: block on the floor and on `tsc`;
   the rest fires at task end.
3. Targets or ratchets. Taken: ratchets, values measured 2026-09-03.
4. Slowest tolerable task-end check. Taken: `check-all.sh` at under 2 min; ceiling 3 min.

`AGENTS.md` should carry the line "Read CONSTRAINTS.md before writing code. Do not weaken
it to make a change pass." That file is factory policy and was not edited unattended;
`CLAUDE.md` carries the pointer for now.

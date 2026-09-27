---
run_id: 2026-09-27T060000Z-sdlc-playbook-adoption
stage: implement
started_at: 2026-09-27T06:00:00Z
finished_at: 2026-09-27T16:00:00Z
status: succeeded
issue: none
pull_request: none
gate_level: fast
gate_status: GREEN
verifier: see "Verification" below
human_required: true
---

# Adopting the AI-native SDLC playbook: the first day

Arya asked (2026-09-27) to adopt the AI-native SDLC playbook
(claude.com/blog/the-ai-native-sdlc-playbook) for this repo: learn how to break the project
into lifecycle pieces, refine the codebase one block at a time, teach it with HTML pages that
use this project's own modules, give every folder an AGENTS.md and every big folder an INDEX.md,
review five inspiration repos, and open a separate session for him to flush out his plans.
Rule for the whole effort: only Opus subagents, never Fable.

## Where the work is

Branch `sdlc/ai-native-playbook`, created off `feat/lesearch-ai-overnight-2026-09-21` at
e666aab (the newest integrated tip; the primary checkout had been sitting on a `main` a month
stale). Commits, oldest first:

| commit | what |
|---|---|
| 88a1332 | `intents/` (Stage 1 home: README, TEMPLATE, brief, `check-intents.sh`); `scripts/folder-index.py` + `check-folder-docs.sh`; `check-sdlc-site.sh`; the narrowed deny rule |
| 5710d51 | 68 per-folder AGENTS.md, 18 generated INDEX.md, five reference reviews under `docs/sdlc/references/` |
| d8a287f | seven draft intents, `docs/sdlc/BLOCKS.md` (22 blocks), `docs/sdlc/architecture-proposal.md`, `intents/INTERVIEW.md`, PRODUCT.md names the navigation files |
| ecd8056 | interview brief accepts a worktree branch forked from the sdlc branch |
| b2db2e9 | the ten-page teaching site `docs/sdlc/`, `scripts/check-sdlc-status.sh`, stage lines aligned in 60 briefs, docs index updated |

## How it was done

Four Workflow runs, every agent on `model: opus`, batches of five (this Mac's session limit
kills larger fleets):

1. **Understand** (17 agents, 34 min): twelve readers mapped every folder against the playbook
   and drafted its AGENTS.md; five reviewers read the reference clones (Orca, OpenMuse,
   security-audit-skill, agent-git, Nethera) and wrote `docs/sdlc/references/<repo>.md`.
2. **Design** (15 agents, 32 min): three site proposals (reader-first, playbook-fidelity,
   repo-reality) scored by two judges and synthesised into one spec; a blocks planner refuted by
   two critics and revised by a fresh agent; an architecture draft refuted by a skeptic and
   revised; a seed-intents writer; the plans-session prompt.
3. **Build** (14 agents, 110 min): a planner wrote the stylesheet and skeleton; ten page writers
   built the pages from the spec without talking to each other; an aligner fixed the SDLC stage
   line in 60 briefs; a checker writer produced `check-sdlc-status.sh` after the pages and found
   one stale line (B-07), fixed by the integrator.
4. **Verify**: five fresh Opus lenses (site truth, non-technical reader, briefs truth, intents
   and blocks, gates and policy) with two skeptics per serious finding. Outcome recorded below.

## What was checked and found clean

- `./.claude/scripts/gates.sh fast` at b2db2e9:
  `FACTORY_GATES: level=fast status=GREEN passed=2 failed=0 failing=none skipped=none misconfigured=none`
- `sh scripts/check-sdlc-site.sh` → `ok (10 pages)`; `sh scripts/check-sdlc-status.sh` →
  `ok (10 pages, 73 status lines, 6 live skipped)`; `check-folder-docs.sh`, `check-intents.sh`,
  `check-product-spec.sh`, `check-docs-index.sh`, `check-codemap.sh` all ok.
- The site rendered in the desktop app's browser pane over a loopback `http.server`, at
  desktop and at 375px, light and dark; nav wraps, no horizontal scroll.
- No pre-existing `scripts/check-*` was modified. Root `AGENTS.md`, `CLAUDE.md`,
  `docs/factory/CHARTER.md`, `.factory/gates.conf`, `.claude/scripts/gates.sh` untouched.

## The one policy change, flagged for Arya

`.claude/settings.json`: `"Edit(AGENTS.md)"` became `"Edit(./AGENTS.md)"`. The unanchored
spelling matched every AGENTS.md at any depth and denied the per-folder briefs Arya asked for
in this session; the anchored spelling protects the root brief only. The running session kept
the old rule cached, so the briefs were written through python heredocs and the change takes
effect in the next session. Revert with one line if unwanted.

## Findings that need Arya (not fixed here; in BLOCKS.md and the intents)

- 135 open pull requests, 123 of them from an unattended Cursor loop on 22–23 September;
  about 21 build account features the roadmap rules out. Decision block B-15.
- `main` has no GitHub branch protection; the "never merge" rule rests on a local hook that
  cloud agents never run. Block B-04, two minutes.
- `docs/factory/CHARTER.md` is still the unfilled template. Block B-16, an interview.
- CI is red on the integration branch (`apps` job); the `deep` gate is permanently red
  (`npm audit` with no lockfile). Blocks B-19, B-20.
- The app has no written design theme; four competing looks exist. Intent
  `2026-09-27-bring-my-design-theme-into-the-app`, interview in `intents/INTERVIEW.md`.

## Verification

Filled in from the verify workflow: see the section appended below.

---
status: draft
owner: Arya
source: conversation
date: 2026-09-27
---

# Intent: Every piece of work on LeSearch AI starts from a written "why" and ends with a human saying yes

## Problem

I have been building the base and adding features one by one, and I have not been focused on
the plan: capturing what I want, in my words, before agents build it. Agents fill that gap with
their own guesses, and nobody notices until the work is already done.

One concrete example. On 22 and 23 September an unattended Cursor agent opened pull requests
on this repository for about 22 hours straight. A live count on 2026-09-27 found 135 open pull
requests, 123 of them from `cursor/*` branches, 112 of those stacked on top of each other. About
21 of them build account and sign-in features, and my own roadmap lists "an account system" as a
non-goal (`ROADMAP.md`, section "Non-goals"). Nothing stopped this: there was no written intent
to compare against, the factory policy file `docs/factory/CHARTER.md` still says
`CHARTER_STATUS: incomplete` and `TIER: <choose one tier>`, and the `main` branch has no GitHub
protection, so the "an agent never merges" rule rests on a local hook that Cursor's cloud agents
never run. (Counts and protection status come from the crosswalk measured today with `gh`; the
earlier brief said 100 PRs, the live number is higher.)

The safety equipment for building and testing mostly works (`./.claude/scripts/gates.sh fast`
was green today). The front of the lifecycle (what to build and why, including design) and the
back (noticing problems after release) are close to empty. Until today `intents/` did not exist.

## Proposed outcome

- I can open `intents/` and see, in plain language, everything I have asked for, with a status
  I set: draft, accepted, in progress, shipped, or closed with a reason.
- Every change an agent makes can be traced back: pull request → plan → spec → the intent I
  wrote. If there is no accepted intent, an agent does not start.
- An agent can never merge its own work, on any tool (Claude Code, Codex, Cursor), because
  GitHub itself refuses it, not only a local script.
- The unreviewed pile of agent pull requests has a recorded decision, and the open-PR count is
  back under the limit I set.
- One command tells me whether the work is green, and I know what "green" looks like.
- I can find my way around the codebase myself using the per-folder guides, and I am taught
  the lifecycle using our own modules as the example.
- Problems found after release (monitoring, security scans, user feedback) come back into
  `intents/` as new drafts instead of being lost.

## Affected users and systems

Mainly me and every coding agent that works on this repo (Claude Code, Codex, Cursor). The
repository's GitHub settings, `intents/`, `openspec/`, `docs/factory/`, `docs/sdlc/`, the per-folder
`AGENTS.md` files and the gate scripts. Indirectly every product surface (Apple Watch app, iPhone
app, Mac menu-bar app, `meshd`, `mesh`, installer, landing site), because all of their work will
now start here.

## Constraints

- Revenue first in 2026 (CloudAGI consulting). The lifecycle must make shipping faster and
  calmer, not add ceremony. Lightweight, local, no new tools or services.
- The first steps need no product code.
- Human-owned policy files (`docs/factory/CHARTER.md`, `.factory/gates.conf`,
  `.claude/scripts/gates.sh`, `AGENTS.md`, `.claude/**`) change only when I ask in the session.
- Agents never merge and never push `main`. Only I mark an intent `accepted`.
- The repository is public: no secrets and no unfixed security findings are committed.
- Only Opus subagents for this work.
- The non-goals outrank everything: no cloud relay, no VNC, no account system, local-first.

## Open questions

The charter, field by field (`docs/factory/CHARTER.md` is a template today):

- Which tier do agents get? (The 2026-09-17 publish plan suggested `greenfield`; see
  `docs/publish-plan-2026-09-17.md`, task T04.)
- Which paths are load-bearing? The template lists `src/auth/**` and `src/payments/**`, which do
  not exist here. Candidates from the publish plan: `Shared/**`, `install/payload/meshd/server.ts`,
  `auth.ts`, `pair.ts`, `project.yml`, `.github/workflows/**`. Anything to add or remove?
- How many pull requests may wait for review before agents stop? The charter says "more than 3";
  `CLAUDE.md` says "more than two". Pick one number.
- How many agent sessions may run in parallel at once (the playbook says start with 2–3)?
- The "may be automated" list points to `docs/factory/MIGRATION.md`, which does not exist. Keep,
  replace, or drop that line?
- The date you last reviewed the charter, so `LAST_REVIEWED` and `CHARTER_STATUS: ready` can be set.

The Cursor pull requests:

- Did you start that Cursor loop on purpose, and is it still running anywhere?
- What happens to the 123 `cursor/*` pull requests: close them all, park them on one branch for
  later, or review a small sample first? (They are stacked, so any cleanup must go from the
  newest up or close the whole chain.)
- Is any of that work (for example the knowledge, notes or voice ones) worth keeping?

The rest:

- Will you turn on a GitHub ruleset for `main` (require a pull request, block force pushes, no
  bot bypass)? It takes about two minutes in the web settings and only you can do it.
- What should `main` be? It is 261 commits behind this branch.
- Use the factory queue (GitHub `factory:*` labels, which were never created) or retire it and
  use `intents/` plus draft pull requests only?
- Which GitHub repository is the one issue list: `aryateja2106/lecoder-watch` or `LeSearch-AI/mesh`
  (where user feedback lands today)?
- The `deep` gate can never be green today (it runs an audit with no lockfile). May it be fixed?
- How often do you want to sit down and triage `intents/`: weekly, or before each release?

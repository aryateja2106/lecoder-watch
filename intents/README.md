# intents/ — where every piece of work starts

This folder is **Stage 1 of the software lifecycle** described in
[docs/sdlc/](../docs/sdlc/index.html): the place where an idea is written down *before*
anyone designs, plans or builds it. One file per idea. Arya owns this folder; agents read
it and may propose new files here, but a file only counts once Arya has committed it.

**Do not confuse this with [`intent/`](../intent/) (singular).** That folder is data for
the local "brain" that turns a spoken phrase into a daemon call. Different thing.

## What an intent is

A short, honest note that answers five questions. It is not a spec and not a plan. It is
allowed to be wrong and allowed to have open questions — those are the point.

```
# Intent: <title>
## Problem                       what hurts today, for whom, with an example
## Proposed outcome              what is true when this is done (not how)
## Affected users and systems    which of: watch, phone, Mac app, daemon, CLI, installer, landing site, docs
## Constraints                   money, time, local-first, App Review, security, what must not change
## Open questions                the things only Arya can answer, or nobody knows yet
```

Copy [TEMPLATE.md](TEMPLATE.md), name the file `YYYY-MM-DD-<short-slug>.md`, fill it in
plain language, commit it. That commit is the audit trail: who asked, when, and every
revision after.

## What happens next (the chain)

| Stage | Artifact | Where it lives here | Who signs off |
|---|---|---|---|
| 1 Plan | `intents/<slug>.md` | this folder | Arya |
| 2 Design | spec (requirements + design under the repo's skills) | `openspec/changes/<slug>/proposal.md` + `specs/` | Arya, tech lead for risky items |
| 3 Build | plan (files that change, order, risks, proof) | `openspec/changes/<slug>/tasks.md`, or a `plan.md` committed before code | the engineer or agent, Arya for load-bearing paths |
| 4 Test | one green command | `./.claude/scripts/gates.sh fast|full` and a `scripts/check-<x>.sh` that fails without the change | the session itself, then a fresh verifier |
| 5 Deploy | a draft pull request through the review policy | GitHub | a human merges, never an agent |
| 6 Maintain | findings come back as new files here | this folder | Arya triages: fix now, schedule, dismiss |

An intent that is accepted moves to `status: accepted` in its front matter and gets a
spec. One that is dropped gets `status: closed` and a one-line reason; it stays in the
folder so the same idea is not re-argued next quarter.

## Status values

`draft` (Arya is still thinking) · `accepted` (a spec may start) · `in-progress` (there is
a plan and a branch) · `shipped` (merged and in a release) · `closed` (decided not to do,
with why).

## For agents

- Read every `accepted` intent before proposing a spec. Quote its title in the spec and in
  the pull request.
- Never mark an intent `accepted`; that is Arya's word.
- Findings from monitoring, security scans or reviews that need more than a one-file fix
  are written here as `draft` intents in the template shape, with `source:` naming what
  found them.

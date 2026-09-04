# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues on `aryateja2106/lecoder-watch`.
Use the `gh` CLI for all operations.

The **live factory queue** is the same issue tracker, with `factory:*` labels and
`factory-handoff:v1` comments. See `docs/factory/CONTRACT.md`. Matt Pocock `/triage`
and `/to-tickets` must not invent a second queue: prefer `factory-triage` for product
work, and map Matt's five roles onto `factory:*` labels (see `docs/agents/triage-labels.md`).

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** Draft PRs are the factory's handoff to a human, not incoming work.

## When a skill says "publish to the issue tracker"

Create a GitHub issue. For Mesh product work that an agent will implement, also apply
`factory:ready-to-spec` or `factory:ready-to-implement` per `docs/factory/CONTRACT.md`
and do not open a second local-markdown tracker.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`. If a `factory-handoff:v1` comment exists, that
comment is the brief.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue. Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`).
- **Blocking**: GitHub native issue dependencies when available; otherwise a `Blocked by: #<n>` line at the top of the child body.
- **Claim**: `gh issue edit <n> --add-assignee @me`. Factory implement runs still claim via the remote-branch rule in the contract, not this assignee alone.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`.

---
name: /factory
id: factory
category: Workflow
description: Factory control room. Show queue state, review bottleneck, and what needs a human right now.
---

Factory control room for this repo.

Read `docs/factory/CONTRACT.md` for queue semantics and `docs/factory/CHARTER.md` for the
limits, then follow the report workflow in `.claude/commands/factory.md` — that file is
canonical and this command is a pointer to it, so the three harnesses cannot drift.

Live GitHub `factory:*` labels and open PRs outrank every Markdown snapshot in
`docs/factory/`. Lead with the human review queue: the binding constraint here is how many
decisions are pending one person's judgment, and the charter caps it at two.

This command reports only. It never merges, approves, labels, or closes work.

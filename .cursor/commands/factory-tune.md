---
name: /factory-tune
id: factory-tune
category: Workflow
description: Review factory performance and propose deliberate constraint changes. Proposes only; never edits the charter.
---

Monthly constraint review, or run it after any escaped defect.

Read `docs/factory/CONTRACT.md`, then follow `.claude/commands/factory-tune.md` — that file
is canonical and this command is a pointer to it.

Propose only. Tighten where a gate let something through and say what the gate missed;
loosen where a class of change has been green long enough and cite the run of evidence.
Record accepted human decisions in `docs/factory/DECISIONS.md`. Never edit
`docs/factory/CHARTER.md` or `.factory/gates.conf` on your own initiative.

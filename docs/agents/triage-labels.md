# Triage Labels

The Matt Pocock skills speak in five canonical roles. This repo already has a
factory state machine. Use the factory labels. Do not create `needs-triage` /
`ready-for-agent` duplicates.

| Label in mattpocock/skills | Label in our tracker | Meaning |
| -------------------------- | -------------------- | ------- |
| `needs-triage`             | *(none — leave unlabeled, or `factory:monitor` for provenance only)* | Not yet in the factory queue |
| `needs-info`               | `factory:needs-info` | Blocked on a named question |
| `ready-for-agent`          | `factory:ready-to-implement` | Brief is written; an implement run may claim it |
| `ready-for-human`          | `factory:ready-to-spec` | Needs an interactive product or design decision |
| `wontfix`                  | close the issue with a comment | Will not be actioned |

Related factory states that Matt's five roles do not name:

- `factory:in-progress` — claimed by one implement run
- `factory:awaiting-review` — draft PR open; a human owns the next decision
- `factory:wait-to-implement` — understood, blocked on a named dependency

When a skill says "apply the AFK-ready triage label", apply `factory:ready-to-implement`
and write a `factory-handoff:v1` comment. Prefer the `factory-triage` skill over Matt's
`/triage` for Mesh product work.

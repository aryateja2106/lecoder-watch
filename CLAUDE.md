Read [AGENTS.md](AGENTS.md). It is the single brief for every agent working on this repo —
Claude Code, Codex and Cursor all use the same one, so it does not get forked here.

---

# Factory

This repo also runs a [software factory](https://github.com/addyosmani/factory): GitHub
issues are the work queue, `factory:*` labels are the live state, and a run claims one item,
implements it, proves it, and opens a **draft** PR. Two files are the policy:

- **[docs/factory/CONTRACT.md](docs/factory/CONTRACT.md)** — queue semantics, the handoff
  format, and the non-negotiable rules. Shared with Codex and Cursor. Read it first.
- **[docs/factory/CHARTER.md](docs/factory/CHARTER.md)** — what *this* project permits:
  tier, load-bearing paths, what may be automated, and the stop conditions. Human-owned;
  never edit it on your own initiative.

Setup and the local dry run: [docs/factory/README.md](docs/factory/README.md).

## The bar

Read [CONSTRAINTS.md](CONSTRAINTS.md) before writing code. Do not weaken it to make a change
pass. `scripts/check-floor.sh` enforces its floor on the diff and runs inside `check-all.sh`.

## The gate

```sh
./.claude/scripts/gates.sh fast   # shared-model compile + published-link check (~40s)
./.claude/scripts/gates.sh full   # + sh scripts/check-all.sh  (MINUTES — runs xcodebuild)
./.claude/scripts/gates.sh deep   # + auth surface + architecture assertions
```

Quote the final `FACTORY_GATES:` line verbatim. `RED` and `MISCONFIGURED` both block, and a
required gate that could not run is `MISCONFIGURED`, never green. `.factory/gates.conf`
documents what each gate name means in this repo.

**`full` is a pre-PR gate, not a loop gate.** It runs `check-ios-smoke.sh`, which drives
`xcodebuild` against a simulator. Use `fast` while working.

## Non-negotiable

1. **Never merge**, and never push `main`. Branch protection is the boundary; the hook in
   `.claude/hooks/block-merge.sh` is a second layer.
2. **Never edit factory policy** — `docs/factory/CHARTER.md`, `.factory/gates.conf`,
   `.claude/scripts/gates.sh`, `AGENTS.md` — unless the human asks in this session.
3. **Never modify an existing `scripts/check-*`** in an unattended run. Adding a new one is
   encouraged.
4. **Verification uses a fresh context.** Delegate to `factory-verifier`. The writer never
   grades the work.
5. AGENTS.md rule 1 outranks a green gate: *verify by running, not by building.* Three
   features here shipped correct and completely dead while compiling green.

Stop and hand back when the charter's `STOP_IF` fires — in particular when more than two
items are already awaiting review, or when proving the change needs a physical device.

State lives in files: one immutable record per run under `docs/factory/runs/`, and GitHub
labels for operational state. Transcripts are not the queue.

## Agent skills

Skills live in `.claude/skills/` (Claude Code), `.agents/skills/` (Codex and the
shared copy), and `.cursor/skills/` (Cursor pointers).

The living index is **[docs/agents/workflows.md](docs/agents/workflows.md)** — edit that
file when you want a different default. Slash shortcuts:

- `/mesh` — pick the right skill
- `/see` — watch a recording or screenshots, then route
- `/design` — Claude Code built-in artboards (do not override)
- `/taste` — native Watch / iPhone UI (`meshwatch-ui-taste`)
- `/scrollcraft` — scroll-driven `web/` landing story
- `/spec` `/plan` `/build` `/grill` — Addy / Matt loop
- `/factory` — product queue
- `/opsx:propose` — Mesh OpenSpec change

Factory and OpenSpec stay the queue for Mesh product work. Native app UI:
`meshwatch-ui-taste`. Landing *story*: `/scrollcraft`. Landing *polish*:
`impeccable`. Drop recordings in `docs/recordings/` or attach them to the chat.

### Issue tracker

GitHub issues on this remote (`gh`). Factory `factory:*` labels are the live queue.
See `docs/agents/issue-tracker.md`.

### Triage labels

Map Matt's five roles onto `factory:*`. Do not create a second label set.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md`, `MEMORY.md`, `AGENTS.md`. See `docs/agents/domain.md`.

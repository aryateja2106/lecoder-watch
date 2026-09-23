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

## The gate

```sh
./.claude/scripts/gates.sh fast   # types (meshd tsc + Shared/ swiftc) + lint (shell syntax + published links) ~40s
./.claude/scripts/gates.sh full   # + test (sh scripts/check-all.sh, incl. the sim smoke) + build (3 xcodebuilds)  MINUTES
./.claude/scripts/gates.sh deep   # + npm audit (no deps here) + the architecture rule block
```

The gate reads `package.json` at the root: `typecheck`, `lint`, `test`, `build` map to
`scripts/gate-*.sh` and `scripts/check-all.sh`. Same commands as `npm run <name>`.

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
shared copy), and `.cursor/skills/` (Cursor pointers). Factory and OpenSpec skills
stay the queue for Mesh product work. Matt Pocock and Addy Osmani packs are the
general engineering loop.

### Issue tracker

GitHub issues on this remote (`gh`). Factory `factory:*` labels are the live queue.
See `docs/agents/issue-tracker.md`.

### Triage labels

Map Matt's five roles onto `factory:*`. Do not create a second label set.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md`, `MEMORY.md`, `AGENTS.md`. See `docs/agents/domain.md`.

## Codebase map — read it before you grep

Three layers, cheapest first. Stop at the first one that answers.

1. **The committed map** (generated from the tree, checked by `scripts/check-codemap.sh`):
   [docs/agents/CODEMAP.md](docs/agents/CODEMAP.md) — which file (purpose, size, the
   checks that name it), ~4k tokens; [CONTRACTS.md](docs/agents/CONTRACTS.md) — daemon
   routes with auth tier, capabilities and where each is gated, relay commands;
   [CHECKS.md](docs/agents/CHECKS.md) — what each `scripts/` file proves;
   [SYMBOLS.md](docs/agents/SYMBOLS.md) — `grep -n '^| Name ' docs/agents/SYMBOLS.md`, never read whole.
2. **codegraph** (MCP tool `codegraph_explore`; CLI `codegraph explore|callers|impact <symbol>`):
   verbatim source plus callers and blast radius in one call. Use it before changing anything
   in the serialized list, instead of a grep-and-read loop.
3. **graphify** (`graphify query "<question>"`, `path`, `explain`): code + docs graph for
   "how does X relate to Y". `graphify-out/GRAPH_REPORT.md` only for architecture review.

Then open ONE file. `sh scripts/repo-status.sh` says which tree is the truth (worktrees,
branches vs `origin/main`, open PRs, map freshness).

After editing: `python3 scripts/codemap-index.py` when you added a file, a header line, a
top-level declaration, a route or a capability (the check tells you); `graphify update .`
for the graph. `sh scripts/codemap.sh` does all of it. Every code file's first comment
line is its purpose in the map; a new file without one fails the check.
Per-harness wiring: [docs/agents/codebase-map.md](docs/agents/codebase-map.md).

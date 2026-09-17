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

## Codebase map

Two local graphs, no API key, nothing leaves the machine. Build or refresh both with
`sh scripts/codemap.sh` (once per clone, then after edits; `--full` after big deletes).

- **graphify** — code + docs knowledge graph in `graphify-out/`. For any "where / how /
  what talks to what" question, run `graphify query "<question>"` before grepping;
  `graphify path "<A>" "<B>"` for a relationship, `graphify explain "<concept>"` for one
  thing. `graphify-out/GRAPH_REPORT.md` is the committed readable map; read it whole only
  for architecture review.
- **codegraph** — symbol / caller / impact graph over MCP (`codegraph_explore`; CLI
  `codegraph explore|callers|impact <symbol>`). Use it before changing a shared function.
- `sh scripts/repo-status.sh` — which tree is the truth right now: worktrees, branches vs
  `origin/main`, open PRs, and whether the map is stale.

After modifying code, `graphify update .` (AST only, seconds) keeps the graph current.
Per-harness wiring and what is committed: [docs/agents/codebase-map.md](docs/agents/codebase-map.md).

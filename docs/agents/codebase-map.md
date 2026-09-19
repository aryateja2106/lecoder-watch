# Codebase map — how agents find things here without reading the tree

Three layers, cheapest first. Stop at the first that answers. Every layer is local; no API
key; nothing leaves the machine.

| Layer | Answers | Cost | Needs |
|---|---|---|---|
| **1. The committed map** — `docs/agents/CODEMAP.md`, `CONTRACTS.md`, `CHECKS.md`, `SYMBOLS.md` | which file · which route / capability / relay command · what check-x proves · where symbol X is | 4k / 1.7k / 2.5k tokens; SYMBOLS is grep-only | nothing — it is in git |
| **2. codegraph** ([colbymchenry/codegraph](https://github.com/colbymchenry/codegraph)) | verbatim source + callers + callees + blast radius, one call | one MCP call instead of a grep-and-read loop | `sh scripts/codemap.sh` once per clone (160 MB SQLite in `.codegraph/`, gitignored) |
| **3. graphify** ([Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify)) | how X relates to Y across code and docs; communities; god nodes | a scoped subgraph per query | same command (`graphify-out/`, only `GRAPH_REPORT.md` committed) |

Then open ONE file. `sh scripts/repo-status.sh` says which tree is current.

## Layer 1: the generated map

`python3 scripts/codemap-index.py` reads the tree (stdlib only, under a second) and writes:

- **CODEMAP.md** — every code file grouped by area with its *purpose*, a size bucket
  (S <200 lines, M <600, L <1200, XL), and the `scripts/check-*` files that name it. The
  serialized files from AGENTS.md are tagged.
- **CONTRACTS.md** — the daemon route table (method, path, `auth = none|token`, file:line)
  parsed from `server.ts` and every module it dispatches to, plus the two other listeners;
  the `CAPABILITIES` list with every `supports("x")` / `contains("x")` site in Swift and
  whether `DaemonCapabilities.expected` lists it; every `WatchCommandKind` case and the
  line in `MeshStore.handle(_:)` that serves it (or **no case**).
- **CHECKS.md** — one line per `scripts/` file: what it proves, in its own header's words.
- **SYMBOLS.md** — every top-level declaration (Swift column-0 types and funcs, TS exports,
  CLI functions) → `file:line`, sorted. `grep -n '^| Name ' docs/agents/SYMBOLS.md`.

**The purpose is the file's own first comment line.** That is the whole convention:
`// pair.ts — bring a phone onto the mesh…`, `# check-wol.sh — …`, `"""mesh-kb — …"""`.
It moves with the file, it is visible to anyone who opens it, and there is no second
place to update. A code file without one fails `scripts/check-codemap.sh`.

**It cannot rot silently.** The output is deterministic (no dates, no SHAs, line totals
rounded), so `check-codemap.sh` regenerates in memory and diffs. It goes red only on a
real structural change: a file added or removed, a header changed, a declaration, a route
or a capability added. The fix is always the same one command. It runs inside
`check-all.sh`, so `gates.sh full` and CI enforce it.

## Layers 2 and 3: the graphs

`sh scripts/codemap.sh` installs both tools if missing (uv for graphify, the official
install script for codegraph), turns telemetry off, builds or syncs both indexes, and
regenerates layer 1. `--full` rebuilds from scratch after large deletes.

| Agent | Reads | codegraph MCP |
|---|---|---|
| Claude Code | `CLAUDE.md` "Codebase map"; `/graphify` skill in `.claude/skills/graphify/` | `.mcp.json` (project, committed): approve `codegraph` once |
| Codex CLI | `AGENTS.md` → `index.md` → this map | `.codex/config.toml` (project; needs the folder trusted) and `~/.codex/config.toml` |
| Cursor / cursor-agent | `.cursor/rules/codemap.mdc` and `graphify.mdc` (always on; graphify's file is tool-owned) | `.cursor/mcp.json` |
| Antigravity (`agy`) | `.agents/rules/codemap.md` and `graphify.md` (always on) + `.agents/workflows/graphify.md` | `~/.gemini/config/mcp_config.json` (global; Antigravity has no project MCP file) |

graphify's installers also offer a `PreToolUse` hook for `.claude/settings.json` that
nags on every Read. It is deliberately not installed: that file is factory policy and the
rules above are enough.

## What is committed and what is not

- committed: the four generated files, `codegraph.json` (excludes), the MCP configs and
  rule files above, `scripts/codemap-index.py`, `check-codemap.sh`, `codemap.sh`,
  `repo-status.sh`, `graphify-out/GRAPH_REPORT.md`
- rebuilt locally: `graphify-out/graph.json` (6 MB), `graph.html`, `.codegraph/` (SQLite)
- excluded from both graphs: `references/external/` (cloned reference repos),
  `reference-video/`, `node_modules`, `build/`, `web/.scrollcraft/`

Known parser gaps on 2026-09-17: tree-sitter-swift reports syntax errors partway through
`Watch/RemoteView.swift` (line 349) and `Watch/WatchMeshStore.swift` (line 554), so
symbols after those lines are missing from graphify. codegraph and layer 1 index both
files fully.

# Codebase map — read the graph before you grep

Two local graphs describe this repo. Build or refresh both with:

```sh
sh scripts/codemap.sh          # once per clone, then after edits (incremental)
sh scripts/codemap.sh --full   # after large refactors or deletes
```

No API key, nothing leaves the machine, about a minute. Telemetry is off in both tools.

| Tool | What it holds | Ask it |
|---|---|---|
| **graphify** ([Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify)) | code **and** docs: 5.9k nodes over 421 files, communities, cross-file edges, in `graphify-out/` | `graphify query "how does pairing mint a token?"` · `graphify path "MeshClient" "auth.ts"` · `graphify explain "AlertGating"` |
| **codegraph** ([colbymchenry/codegraph](https://github.com/colbymchenry/codegraph)) | symbols, callers, callees, blast radius, in `.codegraph/` (per machine, self-gitignored) | MCP tool `codegraph_explore` · CLI `codegraph explore "pairing"` · `codegraph callers sessionsNeedingAttention` · `codegraph impact WatchCommand` |
| `sh scripts/repo-status.sh` | which tree is the truth: worktrees, every local branch vs `origin/main`, open PRs, map freshness | run it before AGENTS.md rule 2 |

`graphify-out/GRAPH_REPORT.md` is the committed, readable map (god nodes, communities,
suggested questions). Read it whole only for architecture review; `query` / `path` /
`explain` return a scoped subgraph that is far smaller than grep output.

After editing code: `graphify update .` (AST only, seconds). codegraph re-syncs itself
through a file watcher while its MCP server is running.

## How each agent gets it

| Agent | Rules it reads | codegraph MCP |
|---|---|---|
| Claude Code | `CLAUDE.md` "Codebase map" section; `/graphify` skill in `.claude/skills/graphify/` | `.mcp.json` (project, committed) — approve `codegraph` once |
| Codex CLI | `AGENTS.md` → this file | `.codex/config.toml` (project; needs the folder trusted) and `~/.codex/config.toml` |
| Cursor / cursor-agent | `.cursor/rules/graphify.mdc` (always on, graphify-owned — do not hand-edit) | `.cursor/mcp.json` |
| Antigravity (`agy`) | `.agents/rules/graphify.md` (always on) + `.agents/workflows/graphify.md` | `~/.gemini/config/mcp_config.json` (global; Antigravity has no project MCP file) |

The graphify installers can also add a `PreToolUse` hook to `.claude/settings.json` that
nags on every Read/Grep. It is deliberately **not** installed: that file is factory policy,
and the rule in `CLAUDE.md` is enough.

## What is committed and what is not

- committed: `graphify-out/GRAPH_REPORT.md`, `codegraph.json` (excludes), the MCP configs
  and rule files above, `scripts/codemap.sh`, `scripts/repo-status.sh`
- rebuilt locally: `graphify-out/graph.json` (6 MB, changes every run), `graph.html`
  (open it in a browser), `.codegraph/` (160 MB SQLite)
- excluded from both graphs: `references/external/` (cloned reference repos),
  `reference-video/`, `node_modules`, `build/`, `web/.scrollcraft/`

Known parser gaps on 2026-09-17: tree-sitter-swift reports syntax errors partway through
`Watch/RemoteView.swift` (line 349) and `Watch/WatchMeshStore.swift` (line 554), so
symbols after those lines are missing from graphify. codegraph indexes both files fully.

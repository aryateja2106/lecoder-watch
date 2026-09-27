---
trigger: always_on
description: Read the generated codebase map before opening or grepping source.
---

## Codebase map

Before reading, grepping or globbing this repo: open `docs/agents/CODEMAP.md` (which
file, ~4k tokens). For a daemon route, a capability string or a watch→phone command:
`docs/agents/CONTRACTS.md`. For a symbol: `grep -n '^| Name ' docs/agents/SYMBOLS.md`.
For what a check proves: `docs/agents/CHECKS.md`. Then open ONE file. For callers and
blast radius use the `codegraph` MCP tool (`codegraph_explore`) or the CLI
`codegraph explore <symbol>` instead of a grep-and-read loop.

After adding a file, changing a file's first comment line, or adding a top-level
declaration, a daemon route or a capability: run `python3 scripts/codemap-index.py` and
commit the result; `scripts/check-codemap.sh` is red until you do. A new code file needs a
one-line header comment saying what it is; that line is its entry in the map.

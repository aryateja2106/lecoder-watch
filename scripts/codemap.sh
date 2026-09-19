#!/bin/sh
# codemap.sh — rebuild the codebase map every agent reads before it greps.
#
# Two local tools, no API key, nothing leaves the machine:
#   graphify   knowledge graph over code AND docs -> graphify-out/ (GRAPH_REPORT.md is
#              committed as the readable map; graph.json is rebuilt here, ~1 min, AST only)
#   codegraph  symbol / call / impact graph served to agents over MCP -> .codegraph/
#              (per machine, self-gitignored; wired in .mcp.json, .cursor/mcp.json,
#              .codex/config.toml and ~/.gemini/config/mcp_config.json for Antigravity)
#
# Usage:
#   sh scripts/codemap.sh          # incremental: sync what changed since the last run
#   sh scripts/codemap.sh --full   # rebuild both from scratch (after big refactors/deletes)
#
# CODEMAP_NO_INSTALL=1 refuses to install a missing tool and reports it instead.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FULL=0
[ "${1:-}" = "--full" ] && FULL=1

note() { echo "codemap: $1"; }

# --- tools -------------------------------------------------------------------------
if ! command -v graphify >/dev/null 2>&1; then
  if [ "${CODEMAP_NO_INSTALL:-}" = "1" ] || ! command -v uv >/dev/null 2>&1; then
    note "graphify missing — install with: uv tool install graphifyy"
  else
    note "installing graphify (uv tool install graphifyy)"
    uv tool install graphifyy >/dev/null 2>&1 || note "graphify install failed; continuing without it"
  fi
fi
if ! command -v codegraph >/dev/null 2>&1; then
  if [ "${CODEMAP_NO_INSTALL:-}" = "1" ] || ! command -v curl >/dev/null 2>&1; then
    note "codegraph missing — install with: curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh"
  else
    note "installing codegraph (official install.sh -> ~/.local/bin/codegraph)"
    curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh >/dev/null 2>&1 \
      || note "codegraph install failed; continuing without it"
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

# --- codegraph (symbols, callers, impact; MCP) --------------------------------------
if command -v codegraph >/dev/null 2>&1; then
  codegraph telemetry off >/dev/null 2>&1 || true     # never phones home; idempotent
  if [ ! -d .codegraph ]; then
    note "codegraph init (first index of this clone)"
    codegraph init >/dev/null 2>&1 || note "codegraph init failed"
  elif [ "$FULL" -eq 1 ]; then
    note "codegraph index (full rebuild)"
    codegraph index >/dev/null 2>&1 || note "codegraph index failed"
  else
    note "codegraph sync"
    codegraph sync >/dev/null 2>&1 || note "codegraph sync failed"
  fi
  codegraph status 2>/dev/null | grep -E 'Files|Nodes|Edges' | sed 's/^ */codemap:   /' || true
else
  note "codegraph unavailable — callers/impact queries will not work until it is installed"
fi

# --- graphify (code + docs knowledge graph) -----------------------------------------
if command -v graphify >/dev/null 2>&1; then
  note "graphify update . (AST only, no API cost)"
  if [ "$FULL" -eq 1 ]; then
    GRAPHIFY_FORCE=1 graphify update . --force 2>&1 | grep -E 'nodes|warning|error' | sed 's/^/codemap:   /' || true
  else
    graphify update . 2>&1 | grep -E 'nodes|warning|error' | sed 's/^/codemap:   /' || true
  fi
  [ -f graphify-out/GRAPH_REPORT.md ] && note "map: graphify-out/GRAPH_REPORT.md (commit this), graphify-out/graph.html (open in a browser)"
else
  note "graphify unavailable — graphify-out/ was not refreshed"
fi

# --- the committed map (stdlib python, no graph tools needed) ------------------------
note "codemap-index.py (docs/agents/CODEMAP, CONTRACTS, CHECKS, SYMBOLS)"
python3 "$ROOT/scripts/codemap-index.py" | sed 's/^/codemap:   /'

note "read:    docs/agents/CODEMAP.md first (~4k tokens), then ONE file"
note "ask it:  graphify query \"how does pairing mint a token?\"   |   codegraph explore \"pairing\""
note "tree:    sh scripts/repo-status.sh   (worktrees, branches, open PRs, map freshness)"

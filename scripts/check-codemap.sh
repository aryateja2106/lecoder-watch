#!/bin/sh
# check-codemap.sh — the committed codebase map matches the tree, and every code file
# says what it is.
#
# docs/agents/{CODEMAP,CONTRACTS,CHECKS,SYMBOLS}.md are generated from the sources by
# scripts/codemap-index.py so agents can find a file, a route, a capability or a symbol
# without opening the tree. A hand-written map rots (index.md once listed 0.3.0 as the
# current release); a generated one that nobody regenerates rots the same way. This check
# regenerates into memory and diffs: red means "run python3 scripts/codemap-index.py".
#
# It also fails when a code file has no header comment, because the purpose column is
# read from the file itself — a file that cannot say what it is has no place in the map.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "check-codemap: SKIP (no python3)"; exit 0; }
python3 "$ROOT/scripts/codemap-index.py" --check

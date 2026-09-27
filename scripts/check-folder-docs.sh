#!/bin/sh
# check-folder-docs.sh — every folder an agent may land in has an AGENTS.md, and every big
# folder's INDEX.md matches the tree.
#
# The root AGENTS.md is one page for the whole repo; the per-folder AGENTS.md files are the
# next page down (read-first, serialized files, the command that proves a change, traps),
# and INDEX.md is the generated one-line-per-file map next to it. A hand-written map rots;
# a generated one nobody regenerates rots the same way, so this regenerates into memory
# and diffs. Red means: `python3 scripts/folder-index.py` for INDEX.md, or write the
# missing AGENTS.md by hand. Reads the tree only; runs in about a second.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "check-folder-docs: SKIP (no python3)"; exit 0; }
python3 "$ROOT/scripts/folder-index.py" --check

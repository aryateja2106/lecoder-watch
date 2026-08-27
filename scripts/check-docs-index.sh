#!/bin/sh
# check-docs-index.sh — every doc is findable, and the index does not point at ghosts.
#
# Before docs/README.md existed, seven of seventeen files in docs/ were linked from
# nowhere. An agent could not tell that app-store-submission.md was current research and
# that PROJECT-STATE-AND-LEARNINGS-2026-07-07.md would send it to a months-stale branch,
# without opening both. The index only helps while it is complete, and a doc added six
# months from now will not add itself.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INDEX="$ROOT/docs/README.md"
ok=1
bad() { echo "FAIL: check-docs-index.sh: $1"; ok=0; }

[ -f "$INDEX" ] || { bad "docs/README.md is missing — docs/ has no index"; exit 1; }

# 1. Every doc is listed. README.md indexes the others and does not index itself.
for f in "$ROOT"/docs/*.md; do
  n="$(basename "$f")"
  [ "$n" = "README.md" ] && continue
  grep -q "($n)" "$INDEX" \
    || bad "docs/$n is in the folder but not in the index — nothing would lead an agent to it"
done

# 2. Every link in the index resolves. A row for a file somebody deleted is worse than no
#    row: it reads as a promise that the answer exists somewhere.
grep -oE '\]\([A-Za-z0-9_./-]+\)' "$INDEX" | tr -d '](' | tr -d ')' | while read -r link; do
  case "$link" in http*|\#*) continue ;; esac
  [ -e "$ROOT/docs/$link" ] || [ -e "$ROOT/$link" ] \
    || echo "DANGLING:$link"
done > "$ROOT/.docs-index-dangling" 2>/dev/null || true
if [ -s "$ROOT/.docs-index-dangling" ]; then
  bad "the index links to files that do not exist:"
  sed 's/^DANGLING:/    /' "$ROOT/.docs-index-dangling"
fi
rm -f "$ROOT/.docs-index-dangling"

# 3. The index has to keep telling agents which half is history. That distinction is the
#    entire reason it exists.
grep -q 'Dated snapshots' "$INDEX" \
  || bad "the index no longer separates current docs from dated snapshots"

[ "$ok" -eq 1 ] || exit 1
echo "check-docs-index: OK ($(ls "$ROOT"/docs/*.md | grep -cv 'README.md$') docs, all indexed, no dangling rows)"

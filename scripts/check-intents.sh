#!/bin/sh
# check-intents.sh — every file in intents/ is a well-formed Stage 1 intent: front matter
# with a known status, the five playbook headings, and a dated slug filename.
#
# intents/ is where work starts (see intents/README.md). A file that skips the headings or
# the status line is a plan or a note in the wrong folder, and an agent reading the folder
# cold would treat it as an accepted ask. Reads the tree only; runs in under a second.
set -eu
cd "$(dirname "$0")/.."
fail=0
bad() { printf 'check-intents: %s: %s\n' "$1" "$2"; fail=1; }
for f in intents/*.md; do
  case "$(basename "$f")" in README.md|TEMPLATE.md|AGENTS.md|INDEX.md) continue ;; esac
  printf '%s\n' "$(basename "$f")" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md$' || bad "$f" "name it YYYY-MM-DD-<slug>.md"
  head -1 "$f" | grep -q '^---$' || bad "$f" "missing front matter"
  grep -qE '^status: (draft|accepted|in-progress|shipped|closed)' "$f" || bad "$f" "status must be draft|accepted|in-progress|shipped|closed"
  grep -q '^# Intent: ' "$f" || bad "$f" "first heading must be '# Intent: <title>'"
  for h in 'Problem' 'Proposed outcome' 'Affected users and systems' 'Constraints' 'Open questions'; do
    grep -q "^## $h" "$f" || bad "$f" "missing '## $h'"
  done
done
[ "$fail" = 0 ] && echo "check-intents: ok" || exit 1

#!/bin/sh
# sync-issues.sh — create the backlog in .github/backlog.json as GitHub issues.
#
#   sh scripts/sync-issues.sh                    # show what would happen, create nothing
#   sh scripts/sync-issues.sh --create           # create the missing ones
#   sh scripts/sync-issues.sh --create --repo O/R  # …somewhere other than origin
#
# Idempotent by title: an issue whose exact title already exists (open OR closed) is
# skipped, so this can be re-run after adding items to the manifest without producing a
# second copy of everything. That is the whole trick — there is no state file to lose.
#
# Labels are created first because `gh issue create --label` fails outright on a label
# that does not exist yet, and it fails AFTER writing some of the issues.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/.github/backlog.json"
CREATE=0
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --create) CREATE=1 ;;
    --repo) shift; REPO="$1" ;;
    *) echo "unknown argument: $1"; exit 1 ;;
  esac
  shift
done

[ -f "$MANIFEST" ] || { echo "FAIL: no $MANIFEST"; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "FAIL: gh is not installed"; exit 1; }
[ -n "$REPO" ] || REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

echo "==> repo: $REPO"

# Existing titles, open and closed. A closed issue is still a decision that was made; making
# a fresh copy of it silently reopens an argument somebody already settled.
EXISTING="$(mktemp)"
gh issue list -R "$REPO" --state all --limit 1000 --json title -q '.[].title' > "$EXISTING" 2>/dev/null || true
echo "==> $(wc -l < "$EXISTING" | tr -d ' ') issues already on the repo"

if [ "$CREATE" -eq 1 ]; then
  echo "==> ensuring labels"
  python3 -c "
import json,sys
print('\n'.join(sorted({l for o in json.load(open('$MANIFEST')) for l in o['labels']})))
" | while read -r label; do
    [ -n "$label" ] || continue
    case "$label" in
      area:*)   color=1d76db ;;
      effort:*) color=c2e0c6 ;;
      state:*)  color=fbca04 ;;
      round:*)  color=ededed ;;
      *)        color=cccccc ;;
    esac
    gh label create "$label" -R "$REPO" --color "$color" >/dev/null 2>&1 \
      && echo "    created $label" || true
  done
fi

created=0; skipped=0
COUNT="$(python3 -c "import json;print(len(json.load(open('$MANIFEST'))))")"
i=0
while [ "$i" -lt "$COUNT" ]; do
  TITLE="$(python3 -c "import json;print(json.load(open('$MANIFEST'))[$i]['title'])")"
  if grep -Fxq "$TITLE" "$EXISTING" 2>/dev/null; then
    skipped=$((skipped+1)); i=$((i+1)); continue
  fi
  if [ "$CREATE" -eq 0 ]; then
    echo "    would create: $TITLE"
    created=$((created+1)); i=$((i+1)); continue
  fi
  BODYFILE="$(mktemp)"
  python3 -c "import json;open('$BODYFILE','w').write(json.load(open('$MANIFEST'))[$i]['body'])"
  LABELS="$(python3 -c "import json;print(','.join(json.load(open('$MANIFEST'))[$i]['labels']))")"
  gh issue create -R "$REPO" --title "$TITLE" --body-file "$BODYFILE" --label "$LABELS" >/dev/null
  rm -f "$BODYFILE"
  echo "    created: $TITLE"
  created=$((created+1)); i=$((i+1))
  # GitHub's secondary rate limit on content creation bites at roughly 80/minute, and it
  # answers with a 403 that reads like a permissions problem rather than a throttle.
  sleep 1
done
rm -f "$EXISTING"

if [ "$CREATE" -eq 0 ]; then
  echo
  echo "Nothing was created. $created would be new, $skipped already exist."
  echo "To create them:  sh scripts/sync-issues.sh --create"
else
  echo
  echo "Created $created, skipped $skipped that already existed."
  echo "  https://github.com/$REPO/issues"
fi

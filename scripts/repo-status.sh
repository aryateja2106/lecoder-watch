#!/bin/sh
# repo-status.sh — what is happening in this codebase right now, in one screen.
#
# This repo has many worktrees and branches, several weeks stale, and a whole session was
# once spent editing a six-week-old tree (AGENTS.md rule 2). Run this before editing and
# whenever "which tree is the truth?" comes up. Read-only; fetches origin if it can.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

git fetch -q origin 2>/dev/null || echo "(offline — origin not fetched, ahead/behind may be stale)"

echo "== this tree =="
printf '%s  on %s\n' "$(git log -1 --date=short --format='%h %cd %s')" "$(git branch --show-current 2>/dev/null || echo 'detached')"
git status -sb | head -1
n="$(git status --porcelain | wc -l | tr -d ' ')"; [ "$n" = "0" ] || echo "$n uncommitted paths"

echo
echo "== worktrees =="
git worktree list

echo
echo "== local branches vs origin/main (date · ahead/behind · branch) =="
for b in $(git for-each-ref --format='%(refname:short)' refs/heads); do
  ab="$(git rev-list --left-right --count "origin/main...$b" 2>/dev/null | awk '{printf "-%s/+%s", $1, $2}')"
  printf '%s  %-10s %s\n' "$(git log -1 --date=short --format='%cd' "$b")" "$ab" "$b"
done | sort -r

if command -v gh >/dev/null 2>&1; then
  echo
  echo "== open pull requests =="
  gh pr list --state open --limit 30 \
    --json number,isDraft,headRefName,title,updatedAt \
    --jq '.[] | "#\(.number) \(if .isDraft then "draft" else "open " end) \(.updatedAt[:10]) \(.headRefName) :: \(.title)"' \
    2>/dev/null || echo "(gh could not list PRs)"
fi

echo
echo "== codebase map =="
if [ -f graphify-out/GRAPH_REPORT.md ]; then
  built="$(grep -o 'Built from commit: `[0-9a-f]*`' graphify-out/GRAPH_REPORT.md | grep -o '[0-9a-f]\{7,\}' || true)"
  head="$(git rev-parse --short=8 HEAD)"
  if [ -n "$built" ] && git merge-base --is-ancestor "$built" HEAD 2>/dev/null && [ "$built" = "$(git rev-parse --short=8 "$built")" ]; then
    behind="$(git rev-list --count "$built..HEAD")"
    [ "$behind" = "0" ] && echo "graphify-out/GRAPH_REPORT.md is current ($head)" \
      || echo "graphify-out/GRAPH_REPORT.md is $behind commit(s) behind HEAD — run: sh scripts/codemap.sh"
  else
    echo "graphify-out/GRAPH_REPORT.md was built from $built, not an ancestor of HEAD — run: sh scripts/codemap.sh"
  fi
else
  echo "no graphify-out/GRAPH_REPORT.md — run: sh scripts/codemap.sh"
fi
[ -d .codegraph ] && echo "codegraph index present (.codegraph/)" || echo "no codegraph index — run: sh scripts/codemap.sh"
if python3 scripts/codemap-index.py --check >/dev/null 2>&1; then
  echo "docs/agents/CODEMAP.md matches the tree"
else
  echo "docs/agents/CODEMAP.md is STALE — run: python3 scripts/codemap-index.py"
fi

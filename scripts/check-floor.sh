#!/bin/sh
# check-floor.sh — the CONSTRAINTS.md floor, checked on the diff.
#
# Looks at every line ADDED (and, for checks, REMOVED) between the merge base with
# origin/main and the working tree, untracked files included, and flags the five moves
# that lower the bar without anyone deciding to: a silenced checker, unfinished work,
# a test made easier, a weakened CONSTRAINTS.md, a new exception row.
#
# Exit 0 clean, 1 violation, 2 could not run. A 2 is not a pass.
# Scope is code, not prose: docs/, references/, launch/, openspec/ and the agent
# instruction trees are ignored on purpose. FLOOR_BASE overrides the base ref.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BASE="${FLOOR_BASE:-origin/main}"

mb="$(git merge-base "$BASE" HEAD 2>/dev/null)"
if [ -z "$mb" ] && [ -n "${CI:-}" ] && [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  git fetch --quiet --unshallow origin main 2>/dev/null || git fetch --quiet origin main 2>/dev/null
  mb="$(git merge-base "$BASE" HEAD 2>/dev/null)"
fi
if [ -z "$mb" ]; then
  echo "check-floor: no merge base against $BASE (shallow clone? run: git fetch --unshallow origin main)"
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Tracked changes (committed + working tree) and untracked files, one unified diff.
# Only the paths that ship are diffed; prose trees are out of scope by construction.
SCOPE="install Shared iOS Watch MeshDesktop MeshWatchWidgets WatchWidgets scripts web CONSTRAINTS.md"
# shellcheck disable=SC2086
git diff --unified=0 --no-color "$mb" -- $SCOPE >"$TMP/diff"
# shellcheck disable=SC2086
git ls-files --others --exclude-standard -- $SCOPE | while IFS= read -r f; do
  [ -f "$f" ] || continue
  git diff --unified=0 --no-color --no-index /dev/null "$f" >>"$TMP/diff" 2>/dev/null
done

constraints_is_new=0
git cat-file -e "$mb:CONSTRAINTS.md" 2>/dev/null || constraints_is_new=1

# A deleted self-check is a test made easier, whatever the diff says line by line.
git diff --name-status "$mb" -- scripts | awk '$1=="D" && $2 ~ /scripts\/check-/ {print $2}' >"$TMP/deleted"

# One awk pass: every pattern lives here, so adding a language means editing one place.
awk -v constraints_is_new="$constraints_is_new" '
  function flag(rule, file, text) {
    n++; printf "  [%s] %s: %s\n", rule, file, substr(text, 1, 110)
  }
  function in_scope(f) {
    return f ~ /^(install|Shared|iOS|Watch|MeshDesktop|MeshWatchWidgets|WatchWidgets|scripts)\// || f ~ /^web\/.*\.(html|js)$/ || f == "CONSTRAINTS.md"
  }
  BEGIN {
    n = 0
    SUPPRESS = "@ts-ignore|@ts-expect-error|@ts-nocheck|eslint-disable|swiftlint:disable|nosemgrep|gitleaks:allow"
    STUBS    = "(^|[^A-Za-z])TODO([^A-Za-z]|$)|FIXME|[Nn]ot implemented|fatalError\\(\"TODO|catch[ \t]*(\\([^)]*\\))?[ \t]*\\{[ \t]*\\}"
    SKIPS    = "\\.skip\\(|\\.only\\(|(^|[^A-Za-z])xit\\(|xdescribe\\(|XCTSkip"
    ASSERT   = "assert\\(|assert |expect\\(|XCTAssert|check\\(|fail\\("
  }
  /^\+\+\+ / { f = $2; sub(/^b\//, "", f); next }
  /^--- /    { next }
  /^@@/      { next }
  /^\+/ {
    if (!in_scope(f) || f == "scripts/check-floor.sh") next
    t = substr($0, 2)
    if (f == "CONSTRAINTS.md") {
      # The floor names the patterns it forbids; only a new exception row counts here.
      if (!constraints_is_new && t ~ /^\| *(W|E)[0-9]+ *\|/) flag("new-exception", f, t)
      next
    }
    if (t ~ SUPPRESS) flag("silenced-checker", f, t)
    if (t ~ STUBS)    flag("unfinished-work", f, t)
    if (t ~ SKIPS)    flag("test-made-easier", f, t)
    next
  }
  /^-/ {
    if (!in_scope(f)) next
    t = substr($0, 2)
    if (f ~ /^scripts\/check-/ && t ~ ASSERT) flag("assertion-removed", f, t)
    if (f == "CONSTRAINTS.md" && t ~ /^- /)   flag("floor-bullet-removed", f, t)
    next
  }
  END {
    while ((getline d < "'"$TMP/deleted"'") > 0) if (d != "") flag("check-deleted", d, "file removed")
    exit n
  }
' "$TMP/diff"
n=$?

if [ "$n" -eq 0 ]; then
  echo "check-floor: clean against $BASE ($(git rev-parse --short "$mb"))"
  exit 0
fi
echo "check-floor: $n floor violation(s) against $BASE. Each lowers the bar; fix the code or add a tracked exception in CONSTRAINTS.md."
exit 1

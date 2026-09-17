#!/bin/sh
# gate-lint.sh — the factory "lint" gate (gates.sh fast). Seconds.
#
# There is no linter config in this repo and adding one is not the point. What "lint"
# has to mean here is: every script the release and the checks depend on still parses,
# and the two links the docs publish still answer. Both have broken silently before —
# a shell script with a syntax error fails only when it runs, and README pointed at a
# host with no DNS for weeks (see scripts/check-links.sh).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

echo "lint: shell syntax (sh -n / bash -n)"
for f in scripts/*.sh install/install.sh install/payload/hooks/*.sh .factory/scripts/*.sh; do
  [ -e "$f" ] || continue
  case "$(head -1 "$f")" in
    *bash*) bash -n "$f" || { echo "FAIL: $f does not parse (bash)"; fail=1; } ;;
    *)      sh -n "$f"   || { echo "FAIL: $f does not parse (sh)"; fail=1; } ;;
  esac
done
bash -n .claude/scripts/gates.sh .claude/hooks/block-merge.sh \
  || { echo "FAIL: a factory script does not parse"; fail=1; }

echo "lint: python syntax"
for f in scripts/*.py; do
  [ -e "$f" ] || continue
  python3 -m py_compile "$f" || { echo "FAIL: $f does not compile"; fail=1; }
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "lint: shellcheck (errors only)"
  # Errors only: the scripts carry their own `# shellcheck disable` where a warning is
  # deliberate, and a warning-level flood is how a lint gate gets switched off.
  shellcheck -S error scripts/*.sh install/install.sh || { echo "FAIL: shellcheck"; fail=1; }
else
  echo "lint: shellcheck not installed (brew install shellcheck) — syntax only"
fi

echo "lint: published links"
sh scripts/check-links.sh || { echo "FAIL: a published link is dead"; fail=1; }

[ "$fail" -eq 0 ] || exit 1
echo "lint: OK"

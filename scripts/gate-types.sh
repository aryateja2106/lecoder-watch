#!/bin/sh
# gate-types.sh — the factory "types" gate (gates.sh fast): does the daemon typecheck, and
# do the shared models the phone, the watch and every self-check compile against still
# parse? Seconds, no simulator, no network.
#
# Two things, deliberately no more:
#   1. meshd typechecks — the same `tsc --noEmit` CI runs, against the one shipping copy
#      of the daemon (AGENTS.md rule 4).
#   2. the dependency-free Shared/ sources typecheck — the exact list check-all.sh links
#      every Swift self-check against, read from that file so the two cannot drift.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

echo "types: meshd (tsc --noEmit)"
if command -v bun >/dev/null 2>&1; then
  (
    cd install/payload/meshd
    # bun-types + typescript are installed ephemerally (--no-save) so this never writes
    # to the committed package.json — identical to .github/workflows/ci.yml.
    [ -x node_modules/.bin/tsc ] || bun add -D --no-save bun-types "typescript@~5.7.0" >/dev/null 2>&1
    bun x tsc --noEmit -p tsconfig.json
  ) || { echo "FAIL: meshd does not typecheck"; fail=1; }
else
  echo "FAIL: bun is not installed, so the daemon cannot be typechecked here"; fail=1
fi

echo "types: Shared/ models (swiftc -typecheck)"
if [ -x /usr/bin/swiftc ]; then
  # DEPS="..." is the one line in check-all.sh that names the shared sources.
  eval "$(grep '^DEPS=' scripts/check-all.sh)"
  # shellcheck disable=SC2086
  /usr/bin/swiftc -typecheck $DEPS || { echo "FAIL: Shared/ models do not typecheck"; fail=1; }
else
  echo "SKIP: no swiftc on this machine (macOS only) — the Swift half was not checked"
fi

[ "$fail" -eq 0 ] || exit 1
echo "types: OK"

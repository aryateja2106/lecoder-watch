#!/bin/sh
# Run every self-check in this repo.
#
# Swift checks MUST compile with -Onone. `assert` is a no-op under -O, so an
# optimised build of an assert-based check passes even when the code under test is
# wrong — verified: breaking normalizedPreviewPoint still exits 0 under -O.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Dependency-free Foundation sources the checks compile against.
DEPS="$ROOT/Shared/Models.swift $ROOT/Shared/LimitHelpers.swift $ROOT/Shared/AgentNotifications.swift $ROOT/Shared/WatchGlance.swift $ROOT/Shared/APNsEnvironment.swift $ROOT/Shared/RiskClassifier.swift $ROOT/Shared/ScreenZoom.swift $ROOT/Shared/AlertGating.swift"

fail=0

for check in "$ROOT"/scripts/check-*.swift; do
  [ -e "$check" ] || continue
  name="$(basename "$check" .swift)"
  # shellcheck disable=SC2086
  if /usr/bin/swiftc -Onone -o "$TMP/$name" "$check" $DEPS 2>"$TMP/$name.err"; then
    if "$TMP/$name"; then :; else echo "FAIL: $name"; fail=1; fi
  else
    echo "FAIL: $name does not compile"; tail -5 "$TMP/$name.err"; fail=1
  fi
done

for check in "$ROOT"/scripts/check-*.sh; do
  [ -e "$check" ] || continue
  case "$(basename "$check")" in check-all.sh) continue ;; esac
  if sh "$check"; then :; else echo "FAIL: $(basename "$check")"; fail=1; fi
done

[ "$fail" -eq 0 ] || exit 1
echo "All self-checks passed."

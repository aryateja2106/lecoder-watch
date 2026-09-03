#!/bin/sh
# check-daemon-gaps.sh — hold the "your agent is out of date" row to the three other
# files it makes claims about. The Swift check next door proves the logic; this one
# proves the logic is talking about things that exist.
#
# Three ways this row could lie, each of which this catches:
#
#   1. It names a capability meshd will never advertise — then the warning never clears,
#      no matter how many times the user upgrades. This is the worst failure, because it
#      trains people to ignore a warning that is right the rest of the time.
#   2. It claims a feature is gated on a capability the Swift never actually checks —
#      the feature works fine on an old daemon and we told them it did not.
#   3. It hands over an upgrade command the installer does not support.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAPS="$ROOT/Shared/DaemonCapabilities.swift"
SERVER="$ROOT/install/payload/meshd/server.ts"
INSTALLER="$ROOT/install/install.sh"
ok=1
bad() { echo "FAIL: check-daemon-gaps.sh: $1"; ok=0; }

[ -f "$CAPS" ] || { bad "Shared/DaemonCapabilities.swift is missing"; exit 1; }
[ -f "$SERVER" ] || { bad "install/payload/meshd/server.ts is missing"; exit 1; }

# The capabilities the app says it needs, read out of the expected[] table.
wanted=$(grep -oE 'capability: "[a-zA-Z]+"' "$CAPS" | sed 's/.*"\(.*\)"/\1/' | sort -u)
[ -n "$wanted" ] || bad "expected[] names no capabilities — the row can never fire"

# The capabilities the daemon actually advertises, read out of its CAPABILITIES array.
advertised=$(grep -m1 'export const CAPABILITIES' "$ROOT/install/payload/meshd/capabilities.ts" \
  | grep -oE '"[a-zA-Z]+"' | sed 's/"//g' | sort -u)
[ -n "$advertised" ] || advertised=$(grep -A25 'export const CAPABILITIES' "$ROOT/install/payload/meshd/capabilities.ts" \
  | grep -oE '"[a-zA-Z]+"' | sed 's/"//g' | sort -u)
[ -n "$advertised" ] || bad "could not read CAPABILITIES out of capabilities.ts"

for cap in $wanted; do
  # (1) meshd must be able to advertise it, or the warning is permanent.
  echo "$advertised" | grep -qx "$cap" \
    || bad "expected[] names \"$cap\", which meshd never advertises — that warning could never clear"

  # (2) something in the app must actually gate on it, or we are reporting the loss of
  #     a feature that was never using it. supports("x") is how every gate is written.
  grep -rqE "supports\(\"$cap\"\)|\"$cap\"" "$ROOT/Shared" "$ROOT/iOS" "$ROOT/Watch" \
    --include='*.swift' --exclude='DaemonCapabilities.swift' \
    || bad "expected[] names \"$cap\", but no Swift outside DaemonCapabilities.swift mentions it"
done

# (3) The command we put in front of a user has to be one the installer understands.
flag=$(grep -oE '\-\-upgrade' "$CAPS" | head -1)
[ -n "$flag" ] || bad "upgradeCommand does not pass --upgrade"
grep -q '\-\-upgrade|\-\-update)' "$INSTALLER" \
  || grep -qE '^\s*--upgrade' "$INSTALLER" \
  || bad "install.sh does not accept --upgrade, so the command we show would fail"

# And it has to point at the repo that actually publishes daemon releases; pointing the
# fleet at a repo with no releases is the same as shipping nothing.
grep -q 'mesh-install/releases/latest/download/install.sh' "$CAPS" \
  || bad "upgradeCommand does not fetch from the mesh-install latest release"

[ "$ok" -eq 1 ] || exit 1
echo "check-daemon-gaps.sh: ok"

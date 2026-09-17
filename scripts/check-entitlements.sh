#!/bin/sh
# check-entitlements.sh — the capabilities the code calls are the capabilities the
# build is entitled to.
#
# Features have shipped correct and completely dead because an entitlement was missing:
# the code compiled, the feature was wired, and the OS silently refused it at runtime.
# Nothing that reads Swift can see that; this pins the contract between what the
# sources use and what the entitlements and Info keys declare, so the two cannot drift
# apart again without a red line here.
#
# Static on purpose — a signed build is not available on CI or on a laptop with no
# certificate, so this checks the inputs to signing rather than its output.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ok=1
bad() { echo "FAIL: check-entitlements.sh: $1"; ok=0; }

# 1. Every entitlements file project.yml points at exists — a missing file does not
#    fail the build, it just signs the target with nothing.
for f in $(grep -o 'CODE_SIGN_ENTITLEMENTS: *[^ ]*' project.yml | sed 's/.*: *//'); do
  [ -f "$f" ] || bad "project.yml names $f, which does not exist"
done

# 2. The iOS app registers for remote notifications, so it needs aps-environment.
if grep -q 'registerForRemoteNotifications' iOS/*.swift; then
  grep -q '<key>aps-environment</key>' iOS/MeshWatch.entitlements \
    || bad "iOS registers for push but iOS/MeshWatch.entitlements has no aps-environment"
fi

# 3. The iOS app starts Live Activities, so Info must say NSSupportsLiveActivities.
if grep -rq 'import ActivityKit' iOS/; then
  grep -q 'NSSupportsLiveActivities: true' project.yml \
    || bad "iOS imports ActivityKit but project.yml has no NSSupportsLiveActivities: true"
fi

# 4. The watch app and its complication share one app group; both sides must be
#    entitled to it or the complication reads an empty container forever.
for id in $(grep -rhoE 'group\.com\.[a-zA-Z0-9.\-]+' Shared Watch WatchWidgets iOS MeshWatchWidgets 2>/dev/null | sort -u); do
  for ent in Watch/MeshWatchWatch.entitlements WatchWidgets/WatchWidgets.entitlements; do
    grep -q "<string>$id</string>" "$ent" || bad "$id is used in code but not granted in $ent"
  done
done

[ "$ok" -eq 1 ] || exit 1
echo "check-entitlements.sh: OK — entitlements and Info keys match what the code uses"

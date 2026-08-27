#!/bin/sh
# check-drag-lock-release.sh — the watch must never walk away holding the Mac's mouse
# button down.
#
# `.hold` presses a real mouse button on the machine and only `.release` lifts it. For
# a while `.release` was emitted from exactly one place — the drag-lock toggle — so
# leaving the Control screen with drag lock on left the button held: every subsequent
# pointer move became a drag that selected and dropped whatever it crossed, including
# from the Mac's own trackpad, and no screen on the watch offered the control that
# would have released it.
#
# This cannot be caught by a build, and it cannot be caught by a screenshot — the view
# looks identical either way. So it is checked against the source: the teardown path
# has to exist, has to send a release, and has to be the one wired to onDisappear.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/Watch/RemoteView.swift"
ok=1
bad() { echo "FAIL: check-drag-lock-release.sh: $1"; ok=0; }

[ -f "$VIEW" ] || { bad "Watch/RemoteView.swift is missing"; exit 1; }

# 1. A teardown function exists and actually sends a release.
body=$(awk '/func relinquish\(\)/,/^    }/' "$VIEW")
[ -n "$body" ] || bad "RemoteControl has no relinquish() — nothing undoes a held mouse button"
printf '%s' "$body" | grep -q '\.release' \
  || bad "relinquish() never sends .release, so a held mouse button stays held"
printf '%s' "$body" | grep -q 'dragLocked' \
  || bad "relinquish() does not consult dragLocked"
# The armed flag has to come down too, or returning to the screen shows an air-mouse
# mode whose sensor was stopped and whose arm therefore moves nothing.
printf '%s' "$body" | grep -q 'setAirMouse(false)' \
  || bad "relinquish() leaves airMouse armed after stopping the sensor"

# 2. Leaving the screen calls it. A relinquish() nobody invokes is the bug intact.
grep -q 'onDisappear {.*relinquish()' "$VIEW" \
  || bad "onDisappear does not call relinquish() — the release never fires on exit"

# 3. And nothing has quietly gone back to the old teardown, which stopped the motion
#    sensor and left the mouse button down.
if grep -q 'onDisappear {.*stopMotion()' "$VIEW"; then
  bad "onDisappear still calls stopMotion() directly — that path never releases the button"
fi

[ "$ok" -eq 1 ] || exit 1
echo "check-drag-lock-release.sh: OK (exiting the Control screen releases the button and disarms air mouse)"

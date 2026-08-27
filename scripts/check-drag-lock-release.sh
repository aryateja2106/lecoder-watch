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

# 4. The release must be DELIVERED, not merely queued. Assertions 1-3 all passed while
#    the button stayed down, because they only proved the event was handed to the batch
#    queue. `perform()` routes through `flush()`, which returns early whenever a request
#    is already in flight — the ordinary state during a drag — and the only thing that
#    drains the queue afterwards is the view's `.task` loop, which SwiftUI cancels on the
#    very disappear that triggered this. So the event sat in `discrete` forever.
if printf '%s' "$body" | grep -qE '(^|[^A-Za-z])perform\(' ; then
  bad "relinquish() sends the release through perform()/the batch queue — flush() returns early while a request is in flight, and the loop that would drain it is cancelled by the same disappear"
fi

# 5. It has to outlive the view. A plain `Task {}` on a @MainActor object that the view
#    is releasing is not a promise that it runs.
printf '%s' "$body" | grep -q 'Task.detached'   || bad "relinquish() does not send the release from a detached task, so it dies with the view that asked for it"

# 6. And it has to have somewhere to go when the direct route is not the live one. A
#    watch usually has no Tailscale, so the phone relay is the normal path, not the
#    exception — a release that only knows the direct route is a release that never
#    lands on a real wrist.
printf '%s' "$body" | grep -q 'WatchLink.shared.send'   || bad "relinquish() has no relay fallback — on a watch reaching meshd through the phone the release never arrives"
printf '%s' "$body" | grep -q 'queueIfUnreachable: true'   || bad "relinquish() drops the release when the phone is briefly unreachable; this is the one event that must be queued"

[ "$ok" -eq 1 ] || exit 1
echo "check-drag-lock-release.sh: OK (the release is sent directly, outlives the view, and has a queued relay fallback)"

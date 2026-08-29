#!/bin/sh
# RETIRED — this is now a shim onto scripts/release-testflight-asc.sh.
#
# WHAT THIS SCRIPT USED TO DO, AND WHY THAT IS NOT ALLOWED ANY MORE
#
# It archived with xcodebuild and exported straight to App Store Connect. Three gates that
# the release path now requires were simply absent from it, and each absence has already
# cost something real:
#
#   No group assignment. This is the zero-group trap in its purest form: the export lands
#     the build in App Store Connect and stops. It processes, goes VALID, and belongs to NO
#     BETA GROUP, so nobody can install it — not external testers, not internal ones, not
#     you. Every list view shows a healthy build. On 2026-08-27 that was the entire answer
#     to "I cannot find the update in TestFlight".
#
#   No version check. Uploading a marketing version LOWER than one already on TestFlight is
#     allowed by App Store Connect and punished by iOS: testers on the higher version are
#     asked to delete and reinstall, which wipes the app Keychain and un-pairs every machine
#     they had added. The 1.0 → 0.5.0 rename did that to everyone at once.
#
#   No smoke test. It ran check-all.sh, which in 2026-08 was entirely static — and 0.5.0
#     passed all of it while shipping an app that closed itself on every screen containing a
#     text field. A build that has not been launched has not been tested.
#
# Rather than fix three holes in a second implementation of the same job, the file stays as
# a name that still works. Muscle memory, older docs, and half-remembered runbooks all point
# here; they should all land on the gated path instead of on a working script with no gates.
# Deleting it would send those callers to "No such file", which teaches nothing.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "scripts/release-testflight.sh is retired."
echo ""
echo "  It uploaded with no group assignment (the build reached nobody), no version-downgrade"
echo "  check (testers lost every pairing), and no smoke test (0.5.0 shipped unlaunchable)."
echo "  scripts/release-testflight-asc.sh does the same job with all three gates in place,"
echo "  and needs no ASC_KEY_ID/ASC_ISSUER_ID — asc holds the credentials in the keychain."
echo ""
echo "  Running it now: sh scripts/release-testflight-asc.sh $*"
echo ""

exec sh "$ROOT/scripts/release-testflight-asc.sh" "$@"

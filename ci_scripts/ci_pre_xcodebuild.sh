#!/bin/sh
# Xcode Cloud pre-xcodebuild hook.
#
# Stamps a build number into the two checked-in Info.plist sources that reference
# $(CURRENT_PROJECT_VERSION) (project.yml sets GENERATE_INFOPLIST_FILE: NO, so these
# are hand-authored sources, not something xcodegen writes):
#   Generated/iOS-Info.plist, Generated/Watch-Info.plist
# (MeshWatchWidgets/Info.plist and WatchWidgets/Info.plist hardcode a static
# "1"/"1.0" instead of referencing the build setting, so they're untouched here —
# same as scripts/release-testflight.sh's build-setting override, which only ever
# reaches the two plists above.)
#
# scripts/release-testflight.sh stamps local archives via
#   CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)"
# passed straight to xcodebuild on the command line — there's no build-setting
# substitution left to do once that runs. Xcode Cloud runs its own xcodebuild
# invocation with no such command line to hook, so this script does the
# equivalent thing earlier: it overwrites the literal CFBundleVersion in those two
# plists before xcodebuild starts. Xcode still $(VAR)-substitutes Info.plist at
# build time, but only where the placeholder is still there; PlistBuddy replaces it
# with a literal number, so there's nothing left to substitute. Xcode Cloud's
# checkout is discarded after the build — this never touches what's committed.
#
# Same YYYYMMDDHHMM shape as the local script, so build numbers from both paths
# always compare correctly against each other (App Store Connect requires each new
# build to be numerically greater than the last one uploaded for the same
# CFBundleShortVersionString). One open edge case: this uses UTC and the local
# script uses whatever timezone the machine running it is in, so a local release
# and an Xcode Cloud build landing within the same ~6-hour window of each other in
# wall-clock time could in principle produce out-of-order build numbers. See
# docs/ci.md.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

BUILD="$(date -u +%Y%m%d%H%M)"

for PLIST in Generated/iOS-Info.plist Generated/Watch-Info.plist; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
done

echo "ci_pre_xcodebuild: stamped CFBundleVersion=$BUILD"

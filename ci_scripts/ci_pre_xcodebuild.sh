#!/bin/sh
# Xcode Cloud pre-xcodebuild hook.
#
# Stamps a build number into the two checked-in Info.plist sources that reference
# $(CURRENT_PROJECT_VERSION) (project.yml sets GENERATE_INFOPLIST_FILE: NO, so these
# are hand-authored sources, not something xcodegen writes):
#   Generated/iOS-Info.plist, Generated/Watch-Info.plist
# (MeshWatchWidgets/Info.plist and WatchWidgets/Info.plist hardcode a static
# "1"/"1.0" instead of referencing the build setting, so they're untouched here —
# same as the local release script's build number, which only ever reaches the two
# plists above.)
#
# It also runs scripts/check-all.sh, because this hook is the last thing that runs
# before an archive that an enabled Xcode Cloud workflow auto-distributes to
# TestFlight. Until now it ran ZERO checks — so a lane that can put a build in
# testers' hands had no gate on it at all, while the local release script had four.
# 0.5.0 is what an ungated release path ships. See the block below the stamping.
#
# scripts/release-testflight-asc.sh gives local uploads their build number with
#   asc publish testflight --build-number "$(date -u +%Y%m%d%H%M)"
# so there's no build-setting substitution left to do once that runs. Xcode Cloud
# runs its own xcodebuild invocation with no such command line to hook, so this
# script does the equivalent thing earlier: it overwrites the literal
# CFBundleVersion in those two plists before xcodebuild starts. Xcode still
# $(VAR)-substitutes Info.plist at build time, but only where the placeholder is
# still there; PlistBuddy replaces it with a literal number, so there's nothing left
# to substitute. Xcode Cloud's checkout is discarded after the build — this never
# touches what's committed.
#
# Same UTC YYYYMMDDHHMM shape as the local script, so build numbers from both paths
# always compare correctly against each other (App Store Connect requires each new
# build to be numerically greater than the last one uploaded for the same
# CFBundleShortVersionString). Both are UTC now; the local-timezone skew that used
# to make this an open edge case went away when the last `date +%Y%m%d%H%M` (no -u)
# did, along with the retirement of scripts/release-testflight.sh.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

BUILD="$(date -u +%Y%m%d%H%M)"

for PLIST in Generated/iOS-Info.plist Generated/Watch-Info.plist; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
done

echo "ci_pre_xcodebuild: stamped CFBundleVersion=$BUILD"

# Every gate in scripts/, before the archive rather than after it reaches testers.
#
# MESH_SMOKE_REQUIRED is deliberately NOT set: what simulator runtimes an Xcode Cloud image
# carries is not something this repo controls or can check from here, and a release lane that
# refuses to build because Apple changed an image is worse than one that builds and says
# plainly what it did not verify. So the smoke test may skip — but it may not skip QUIETLY.
# The whole 0.5.0 lesson is that "no simulator here" and "the app runs" are the same exit 0,
# and the only thing that separates them afterwards is whether the log said so.
echo "ci_pre_xcodebuild: running scripts/check-all.sh"
LOG="$(mktemp)"
if sh scripts/check-all.sh >"$LOG" 2>&1; then
  cat "$LOG"
else
  cat "$LOG"
  echo "ci_pre_xcodebuild: FAIL — self-checks are red. Refusing to archive."
  rm -f "$LOG"
  exit 1
fi

if grep -q 'check-ios-smoke: SKIP' "$LOG"; then
  echo ""
  echo "ci_pre_xcodebuild: ###############################################################"
  echo "ci_pre_xcodebuild: #  WARNING: THE APP WAS NEVER LAUNCHED IN THIS BUILD."
  echo "ci_pre_xcodebuild: #  check-ios-smoke.sh skipped — no usable iOS simulator on this"
  echo "ci_pre_xcodebuild: #  Xcode Cloud image. Every check that passed above reads source;"
  echo "ci_pre_xcodebuild: #  none of them ran it. 0.5.0 passed all of them and still closed"
  echo "ci_pre_xcodebuild: #  itself on every screen containing a text field."
  echo "ci_pre_xcodebuild: #  Do not treat this archive as smoke-tested. Before promoting it"
  echo "ci_pre_xcodebuild: #  to testers, run on a machine with a current Xcode:"
  echo "ci_pre_xcodebuild: #      MESH_SMOKE_REQUIRED=1 sh scripts/check-ios-smoke.sh"
  echo "ci_pre_xcodebuild: ###############################################################"
  echo ""
fi
rm -f "$LOG"

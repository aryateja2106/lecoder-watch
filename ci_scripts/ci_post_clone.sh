#!/bin/sh
# Xcode Cloud post-clone hook.
#
# MeshWatch.xcodeproj is gitignored — xcodegen generates it from project.yml (see
# scripts/set-development-team.sh / release-testflight.sh for the same pattern
# used locally). Xcode Cloud checks the repo out fresh into
# CI_PRIMARY_REPOSITORY_PATH before it ever looks for a scheme, so the project has
# to exist by the time this script exits.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

brew install xcodegen

xcodegen generate

chmod +x ci_scripts/*.sh

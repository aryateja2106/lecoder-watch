#!/bin/sh
# gate-build.sh — the factory "build" gate (gates.sh full): the three apps compile for
# their simulators, the way CI builds them. MINUTES. No signing, no device.
#
# A green build proves very little on its own (AGENTS.md rule 1) — the smoke test that
# launches the app lives in scripts/check-ios-smoke.sh and runs with the test gate. This
# gate exists so a Swift change cannot reach a PR without the watch, the phone and the
# Mac menu bar app all still compiling, which is the cheapest thing that has ever been
# skipped.
#
# On a machine without Xcode this SKIPs loudly (exit 0). MESH_BUILD_REQUIRED=1 turns
# that skip into a failure — set it wherever a green tick is read as "it built".
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

note() { echo "gate-build: $1"; }
skip() {
  if [ "${MESH_BUILD_REQUIRED:-}" = "1" ]; then
    note "FAIL: the build was REQUIRED (MESH_BUILD_REQUIRED=1) and did not run — $1"; exit 1
  fi
  note "SKIP — $1"; exit 0
}

command -v xcodebuild >/dev/null 2>&1 || skip "no xcodebuild on this machine"
command -v xcodegen  >/dev/null 2>&1 || skip "xcodegen is not installed (brew install xcodegen)"

xcodegen generate >/dev/null 2>&1 || { note "FAIL: xcodegen could not generate the project"; exit 1; }

fail=0
build() {
  scheme="$1"; dest="$2"
  log="$(mktemp -t mesh-build)"
  printf 'gate-build: %s ... ' "$scheme"
  # Arguments are passed literally, never through an unquoted variable: zsh does not
  # word-split, and a mis-parsed -destination silently builds for a device (AGENTS.md 7).
  if xcodebuild -project MeshWatch.xcodeproj -scheme "$scheme" -destination "$dest" \
       -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build >"$log" 2>&1; then
    echo "ok"; rm -f "$log"
  else
    echo "FAILED"
    grep -E 'error:|\*\* BUILD FAILED' "$log" | head -20 | sed 's/^/  /'
    note "full log: $log"
    fail=1
  fi
}

build "MeshWatch"           "generic/platform=iOS Simulator"
build "MeshWatch Watch App" "generic/platform=watchOS Simulator"
build "MeshDesktop"         "generic/platform=macOS"

[ "$fail" -eq 0 ] || exit 1
note "OK — iOS, watchOS and macOS targets all build"

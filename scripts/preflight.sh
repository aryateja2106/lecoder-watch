#!/bin/sh
# Everything that must be true before anything is published.
#
#   sh scripts/preflight.sh          full gate (includes the two Xcode builds)
#   sh scripts/preflight.sh --fast   skip Xcode; for a pre-commit loop
#
# Runs every section even after one fails, then reports. A gate that stops at the
# first error makes you re-run it N times to find N problems.
#
# Exit codes: 0 all passed, 1 one or more sections failed.

set -u

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)
cd "$ROOT" || exit 1

FAST=0
[ "${1:-}" = "--fast" ] && FAST=1

FAILED=""
PASSED=""

# Run a named section; record pass/fail without aborting the script.
section() {
  name="$1"; shift
  printf '\n\033[1m── %s\033[0m\n' "$name"
  if "$@"; then
    PASSED="$PASSED $name"
  else
    printf '\033[31mFAILED: %s\033[0m\n' "$name"
    FAILED="$FAILED $name"
  fi
}

# 1. Secrets. Both the history and the working tree: a secret that was committed
#    and then deleted is still in the history, and still leaked.
check_secrets() {
  if ! command -v gitleaks >/dev/null 2>&1; then
    echo "gitleaks not installed — brew install gitleaks"
    return 1
  fi
  gitleaks git . -c .gitleaks.toml --no-banner --redact || return 1
  gitleaks dir . -c .gitleaks.toml --no-banner --redact || return 1
}

# 2. install.sh is piped straight into `sh` by strangers, so a parse error is a
#    broken install for everyone. shellcheck is advisory — style findings in a
#    ~700-line POSIX installer must not be able to block a release.
check_shell() {
  sh -n install/install.sh || return 1
  echo "sh -n install/install.sh: OK"
  for f in scripts/*.sh; do sh -n "$f" || return 1; done
  echo "sh -n scripts/*.sh: OK"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck --shell=sh --severity=error install/install.sh || return 1
    echo "shellcheck (errors): OK"
  else
    echo "shellcheck not installed (advisory only) — brew install shellcheck"
  fi
}

# 3. Types. strict:true across meshd, the bridge and the repo's own TS scripts.
check_types() {
  [ -d node_modules ] || bun install --frozen-lockfile >/dev/null 2>&1 || bun install >/dev/null 2>&1
  ./node_modules/.bin/tsc --project tsconfig.json || return 1
  echo "tsc --strict: OK"
}

# 4. Every TS entry point actually bundles (catches bad imports tsc allows).
check_bundles() {
  (cd install/payload/meshd && bun build server.ts --target=bun --outfile=/dev/null >/dev/null) || return 1
  (cd install/payload/rmux-bridge && bun build src/server.ts --target=bun --outfile=/dev/null >/dev/null) || return 1
  cp install/payload/bin/mesh /tmp/preflight-mesh.ts \
    && bun build /tmp/preflight-mesh.ts --target=bun --outfile=/dev/null >/dev/null || return 1
  rm -f /tmp/preflight-mesh.ts
  echo "meshd / rmux-bridge / mesh CLI bundle: OK"
}

# 5. The repo's self-checks. No test targets here — these are the tests.
check_selfchecks() {
  bun scripts/check-orca-adapter.ts || return 1
  sh scripts/check-package-mesh-install.sh || return 1
  echo "check-package-mesh-install: OK"
  # The Swift checks cover the app, not the payload. CI runs on Linux, where
  # there is no toolchain for them — skip rather than fail, since the macOS
  # preflight (and the app build) is what actually gates them.
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "xcrun unavailable — skipping Swift self-checks (not macOS)"
    return 0
  fi
  tmp=$(mktemp -d)
  xcrun swiftc Shared/Models.swift Shared/LimitHelpers.swift scripts/check-limit-helpers.swift -o "$tmp/a" \
    && "$tmp/a" || return 1
  xcrun swiftc Shared/Install.swift scripts/check-install-summary.swift -o "$tmp/b" && "$tmp/b" || return 1
  xcrun swiftc Shared/Models.swift scripts/check-session-state.swift -o "$tmp/c" && "$tmp/c" || return 1
  rm -rf "$tmp"
}

# 6. Swift has no separate typecheck — the build IS the type gate for the apps.
check_apps() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild unavailable — skipping app builds (not macOS)"
    return 0
  fi
  xcodegen generate >/dev/null || return 1
  for scheme_dest in \
    "MeshWatch|generic/platform=iOS Simulator" \
    "MeshWatch Watch App|generic/platform=watchOS Simulator"
  do
    scheme=${scheme_dest%%|*}
    dest=${scheme_dest#*|}
    if ! xcodebuild -project MeshWatch.xcodeproj -scheme "$scheme" \
        -destination "$dest" -derivedDataPath build/DerivedData \
        CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -q "BUILD SUCCEEDED"; then
      echo "xcodebuild failed for scheme: $scheme"
      return 1
    fi
    echo "build OK: $scheme"
  done
}

section "secrets"      check_secrets
section "shell"        check_shell
section "types"        check_types
section "bundles"      check_bundles
section "self-checks"  check_selfchecks
if [ "$FAST" -eq 1 ]; then
  printf '\n\033[33m── apps (skipped: --fast)\033[0m\n'
else
  section "apps" check_apps
fi

printf '\n\033[1m── preflight\033[0m\n'
[ -n "$PASSED" ] && printf '\033[32mpassed:\033[0m%s\n' "$PASSED"
if [ -n "$FAILED" ]; then
  printf '\033[31mfailed:\033[0m%s\n' "$FAILED"
  exit 1
fi
printf '\033[32mall clear — safe to publish\033[0m\n'

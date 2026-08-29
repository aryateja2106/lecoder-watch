#!/bin/sh
# check-mesh-version.sh — `mesh version` reports the daemon that is actually installed.
#
# The CLI used to carry its own `const VERSION = "0.1.0"` while meshd beside it was
# 0.5.0. Two constants, one payload, and nothing keeping them equal — so the single
# command a user runs to answer "am I up to date?" was four minor versions out and had
# been for months. Worse, it under-reported: a user on a genuinely stale daemon and a
# user on the newest one both read the same wrong number, so the CLI could never be the
# thing that told them to upgrade.
#
# The fix was to delete the second constant and read meshd/server.ts. This check exists
# so the constant cannot come back.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/install/payload/bin/mesh"
SERVER="$ROOT/install/payload/meshd/server.ts"
ok=1
bad() { echo "FAIL: check-mesh-version.sh: $1"; ok=0; }

command -v bun >/dev/null 2>&1 || { echo "check-mesh-version: SKIP (no bun)"; exit 0; }
[ -f "$CLI" ] || { bad "install/payload/bin/mesh is missing"; exit 1; }
[ -f "$SERVER" ] || { bad "install/payload/meshd/server.ts is missing"; exit 1; }

want="$(sed -n 's/^[[:space:]]*const VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$SERVER" | head -1)"
[ -n "$want" ] || { bad "could not read VERSION out of meshd/server.ts"; exit 1; }

# 1. With no installed tree, the CLI falls back to the payload it was unpacked from —
#    and that payload's daemon is the version it must report. This is the case that was
#    broken: a fresh install, `mesh version`, and a number from a different year.
got="$(MESH_HOME="$ROOT/.no-such-mesh-home-$$" bun "$CLI" version 2>/dev/null | tail -1)"
[ "$got" = "$want" ] \
  || bad "payload says meshd is $want but \`mesh version\` says '$got' — the CLI is lying about what it ships"

# 2. An installed tree wins over the payload. `mesh version` has to describe the daemon
#    that is running on THIS machine, not the tarball the CLI happened to arrive in;
#    otherwise an upgrade that half-failed still reads as success.
T="$(mktemp -d)"
mkdir -p "$T/meshd"
printf 'const VERSION = "9.9.9-check";\n' > "$T/meshd/server.ts"
got2="$(MESH_HOME="$T" bun "$CLI" version 2>/dev/null | tail -1)"
rm -rf "$T"
[ "$got2" = "9.9.9-check" ] \
  || bad "an installed meshd reporting 9.9.9-check was read as '$got2' — the CLI reports the payload, not the machine"

# 3. The revert guard. Any bare version literal assigned to VERSION in the CLI is the
#    old bug growing back, whatever value it holds.
if grep -nE '^[[:space:]]*const VERSION[[:space:]]*=[[:space:]]*"' "$CLI" >/dev/null 2>&1; then
  bad "the CLI has a hardcoded \`const VERSION = \"...\"\` again — that is the drift this check exists to stop:"
  grep -nE '^[[:space:]]*const VERSION[[:space:]]*=[[:space:]]*"' "$CLI" | sed 's/^/    /'
fi

[ "$ok" -eq 1 ] || exit 1
echo "check-mesh-version: OK (CLI reports $want from the payload, and defers to an installed tree)"

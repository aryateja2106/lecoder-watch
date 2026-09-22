#!/bin/sh
# Local routing fixture. Runs entirely on this machine.
# The gateway key stays unset, so this check cannot call out.
set -eu
unset AI_GATEWAY_API_KEY

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if grep -q 'liveGatewayCall' "$ROOT/experiments/jev-routing/check.ts"; then
  echo "FAIL: check must not call liveGatewayCall" >&2
  exit 1
fi
node --experimental-strip-types "$ROOT/experiments/jev-routing/check.ts"

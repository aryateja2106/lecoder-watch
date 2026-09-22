#!/bin/sh
# Draft a filtered note only when the local route allows it.
# The gateway key stays unset, so this check cannot call out.
set -eu
unset AI_GATEWAY_API_KEY

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRAFT="$ROOT/experiments/note-route-draft/draft.ts"
CHECK="$ROOT/experiments/note-route-draft/check.ts"

if grep -q 'liveGatewayCall' "$DRAFT"; then
  echo "FAIL: note route draft must not call liveGatewayCall" >&2
  exit 1
fi
if grep -q 'ai-gateway.vercel.sh' "$DRAFT"; then
  echo "FAIL: draft module must not name the gateway" >&2
  exit 1
fi
if grep -q 'Where should this turn be shown' "$DRAFT"; then
  echo "FAIL: question list was forked" >&2
  exit 1
fi

node --experimental-strip-types "$CHECK"

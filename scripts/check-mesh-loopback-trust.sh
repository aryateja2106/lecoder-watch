#!/bin/sh
# Loopback bearer exemption must fail closed when:
#   - spoofable forward headers are present (reverse-proxy footgun), or
#   - MESHD_TRUST_LOOPBACK=0 (operator kill-switch).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-loopback-trust: SKIP (bun not installed)"; exit 0; }

bun loopback-trust.ts --check

grep -q 'loopbackExempt' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route loopback exemption through loopback-trust.ts"
  exit 1
}
if grep -q 'function isLoopback' "$ROOT/install/payload/meshd/server.ts"; then
  echo "FAIL: server.ts still defines a local isLoopback — use loopback-trust.ts"
  exit 1
fi
echo "check-mesh-loopback-trust: server.ts wired"

# End-to-end against a throwaway daemon (same pattern as check-mesh-csrf.sh).
TH="$(mktemp -d)"
PORT=8978
LOG="$TH/meshd.log"
TOKEN=loopback-trust-check
MESHD_TOKEN="$TOKEN" MESHD_PORT="$PORT" MESHD_HOST=127.0.0.1 HOME="$TH" bun run server.ts >"$LOG" 2>&1 &
SRV=$!
trap 'ec=$?; kill "$SRV" 2>/dev/null || true; wait "$SRV" 2>/dev/null || true; rm -rf "$TH"; exit "$ec"' EXIT

up=0
i=0
while [ "$i" -lt 50 ]; do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then up=1; break; fi
  kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited before listening"; cat "$LOG"; exit 1; }
  sleep 0.1; i=$((i + 1))
done
[ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on $PORT"; cat "$LOG"; exit 1; }

code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }

# Plain loopback client with no forward headers — exemption must still work.
got="$(code "http://127.0.0.1:$PORT/stats")"
[ "$got" = "200" ] || { echo "FAIL: plain loopback GET /stats should be 200 without Bearer, got $got"; exit 1; }

# Spoofable forward header — exemption must not apply.
got="$(code -H 'X-Forwarded-For: 203.0.113.1' "http://127.0.0.1:$PORT/stats")"
[ "$got" = "401" ] || { echo "FAIL: X-Forwarded-For must block loopback exemption (401), got $got"; exit 1; }

# Bearer still works when forward header is present.
got="$(code -H 'X-Forwarded-For: 203.0.113.1' -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:$PORT/stats")"
[ "$got" = "200" ] || { echo "FAIL: Bearer must pass with forward header, got $got"; exit 1; }

kill "$SRV" 2>/dev/null || true
wait "$SRV" 2>/dev/null || true
SRV=""

# Kill-switch: every route needs Bearer, including loopback.
MESHD_TOKEN="$TOKEN" MESHD_PORT="$PORT" MESHD_HOST=127.0.0.1 MESHD_TRUST_LOOPBACK=0 HOME="$TH" \
  bun run server.ts >"$LOG" 2>&1 &
SRV=$!
up=0
i=0
while [ "$i" -lt 50 ]; do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then up=1; break; fi
  kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd (trust=0) exited before listening"; cat "$LOG"; exit 1; }
  sleep 0.1; i=$((i + 1))
done
[ "$up" -eq 1 ] || { echo "FAIL: meshd (trust=0) never came up"; cat "$LOG"; exit 1; }

got="$(code "http://127.0.0.1:$PORT/stats")"
[ "$got" = "401" ] || { echo "FAIL: MESHD_TRUST_LOOPBACK=0 must require Bearer on loopback, got $got"; exit 1; }

got="$(code -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:$PORT/stats")"
[ "$got" = "200" ] || { echo "FAIL: Bearer must still work with MESHD_TRUST_LOOPBACK=0, got $got"; exit 1; }

echo "check-mesh-loopback-trust: OK"

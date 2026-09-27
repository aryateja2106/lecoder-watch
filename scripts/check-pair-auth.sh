#!/bin/sh
# check-pair-auth.sh — /pair/new honours the bearer and the MESHD_TRUST_LOOPBACK kill switch (SEC-03, opt-in).
#
# Default (trust on): a loopback process may still mint a pairing code without the token —
# `mesh pair` on a fresh box and scripts/check-token-rotate.sh depend on it, so the default
# was not flipped unattended (that is a test edit for a human). With MESHD_TRUST_LOOPBACK=0
# the exemption is gone everywhere: tokenless loopback /pair/new and /stats are 401, /health
# stays public, the bearer still works, and `mesh pair` (which sends ~/.mesh/token) still mints.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-pair-auth: SKIP (no bun)"; exit 0; }
TMP="$(mktemp -d)"; PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done; rm -rf "$TMP"; }
trap cleanup EXIT
fail() {
  echo "check-pair-auth: FAIL — $1"
  for log in "$TMP"/*/meshd.log; do [ ! -f "$log" ] || sed -n '1,20p' "$log"; done
  exit 1
}
status() {
  if [ -n "$3" ]; then curl -s -o "$2" -w '%{http_code}' -H "Authorization: Bearer $3" "http://127.0.0.1:$1$4"
  else curl -s -o "$2" -w '%{http_code}' "http://127.0.0.1:$1$4"; fi
}
start() {
  port="$1"; trust="$2"; home="$TMP/$port"; mkdir -p "$home/.mesh"
  MESHD_TOKEN=t MESHD_PORT="$port" MESHD_HOST=127.0.0.1 MESHD_TRUST_LOOPBACK="$trust" \
    HOME="$home" MESH_HOME="$home/.mesh" MESHD_EVENTS_PATH="$home/events.jsonl" MESHD_TELEMETRY=off \
    bun "$ROOT/install/payload/meshd/server.ts" >"$home/meshd.log" 2>&1 &
  pid=$!; PIDS="$PIDS $pid"; i=0
  until curl -sf "http://127.0.0.1:$port/health" >/dev/null 2>&1; do
    kill -0 "$pid" 2>/dev/null || fail "daemon on $port exited"
    i=$((i + 1)); [ "$i" -lt 50 ] || fail "daemon on $port did not start"; sleep 0.1
  done
}

bun "$ROOT/install/payload/meshd/loopback-trust.ts" --check >/dev/null || fail "loopback helper self-check"
start 8936 1
[ "$(status 8936 /dev/null '' /pair/new)" = 200 ] || fail "trust on: tokenless loopback /pair/new should still mint (default kept for check-token-rotate.sh)"
[ "$(status 8936 "$TMP/pair.json" t /pair/new)" = 200 ] || fail "authenticated /pair/new was not 200"
CODE="$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' "$TMP/pair.json")"; [ -n "$CODE" ] || fail "pair code missing"
CLAIM="$(curl -s -w '\n%{http_code}' -X POST -H 'content-type: application/json' -d "{\"code\":\"$CODE\"}" "http://127.0.0.1:8936/pair/claim")"
[ "$(printf '%s\n' "$CLAIM" | tail -1)" = 200 ] && printf '%s\n' "$CLAIM" | grep -q '"token":"t"' || fail "tokenless claim failed"
printf 't\n' >"$TMP/8936/.mesh/token"
MESH_HOME="$TMP/8936/.mesh" MESHD_PORT=8936 bun "$ROOT/install/payload/bin/mesh" pair --json >"$TMP/cli.json" || fail "mesh pair failed"
grep -q '"code"' "$TMP/cli.json" || fail "mesh pair returned no code"

start 8937 0
[ "$(status 8937 /dev/null '' /health)" = 200 ] || fail "public health failed"
[ "$(status 8937 /dev/null '' /stats)" = 401 ] || fail "kill switch did not remove exemption"
[ "$(status 8937 /dev/null t /stats)" = 200 ] || fail "bearer /stats failed"
[ "$(status 8937 /dev/null '' /pair/new)" = 401 ] || fail "trust off: tokenless loopback /pair/new must be 401 (SEC-03)"
[ "$(status 8937 "$TMP/pair2.json" t /pair/new)" = 200 ] || fail "trust off: bearer /pair/new must still mint"
printf 't\n' >"$TMP/8937/.mesh/token"
MESH_HOME="$TMP/8937/.mesh" MESHD_PORT=8937 bun "$ROOT/install/payload/bin/mesh" pair --json >"$TMP/cli2.json" || fail "trust off: mesh pair failed"
grep -q '"code"' "$TMP/cli2.json" || fail "trust off: mesh pair returned no code"
echo "check-pair-auth: OK"

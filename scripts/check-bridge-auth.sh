#!/bin/sh
# rmux-bridge auth self-check. The bridge can type into any tmux/rmux session, and until
# 0.6 it answered anyone who could reach port 7820. This starts a throwaway bridge with
# loopback trust OFF (so the check itself is treated like a stranger on the LAN) and
# proves: no token → 401 on the page and on /attach; the bearer header or the
# `mesh_token` cookie → 200; a bridge with no token configured anywhere refuses even a
# matching cookie (fail closed); /health answers without auth so a phone can probe it.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-bridge-auth: SKIP (bun not installed)"; exit 0; }
command -v curl >/dev/null 2>&1 || { echo "check-bridge-auth: SKIP (curl not installed)"; exit 0; }
TMP="$(mktemp -d)"
PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done; rm -rf "$TMP"; }
trap cleanup EXIT
fail=0
expect() { # name expected actual
  if [ "$2" = "$3" ]; then :; else echo "FAIL $1: expected $2 got $3"; fail=1; fi
}
code() { curl -s -o /dev/null -w '%{http_code}' -m 5 "$@"; }
wait_up() { # port
  i=0; while [ $i -lt 50 ]; do
    if curl -s -m 1 -o /dev/null "http://127.0.0.1:$1/health"; then return 0; fi
    i=$((i+1)); sleep 0.1
  done; echo "bridge on :$1 never answered"; exit 1
}
pick_port() { bun -e 'const s=Bun.listen({hostname:"127.0.0.1",port:0,socket:{data(){}}});console.log(s.port);s.stop()'; }

TOKEN="check-bridge-token-0123456789abcdef"
BRIDGE="$ROOT/install/payload/rmux-bridge/src/server.ts"

# --- a bridge with a token, loopback not trusted (we are the stranger) ---
P1="$(pick_port)"
HOME="$TMP/home1" MESH_HOME="$TMP/home1/.mesh" PORT="$P1" MESHD_TOKEN="$TOKEN" BRIDGE_HOST=127.0.0.1 BRIDGE_TRUST_LOOPBACK=0 MUX=/nonexistent-mux \
  bun "$BRIDGE" >"$TMP/b1.log" 2>&1 &
PIDS="$PIDS $!"
wait_up "$P1"
B="http://127.0.0.1:$P1"
expect "health without auth"      200 "$(code "$B/health")"
expect "page without auth"        401 "$(code "$B/")"
expect "asset without auth"       401 "$(code "$B/xterm/xterm.js")"
expect "attach without auth"      401 "$(code "$B/attach?session=x")"
expect "wrong bearer"             401 "$(code -H "Authorization: Bearer nope-nope-nope-nope-nope" "$B/")"
expect "wrong cookie"             401 "$(code -H "Cookie: mesh_token=nope-nope-nope-nope-nope" "$B/")"
expect "token in URL is ignored"  401 "$(code "$B/?token=$TOKEN")"
expect "bearer header"            200 "$(code -H "Authorization: Bearer $TOKEN" "$B/")"
expect "cookie"                   200 "$(code -H "Cookie: other=1; mesh_token=$TOKEN" "$B/")"
expect "cookie on asset"          200 "$(code -H "Cookie: mesh_token=$TOKEN" "$B/xterm/xterm.js")"
# /attach with the cookie gets past auth: the upgrade is attempted (101), and only then
# the missing session closes the socket — auth is proven by not seeing 401 here.
expect "attach with cookie upgrades" 101 "$(code -H "Cookie: mesh_token=$TOKEN" -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" "$B/attach?session=x")"

# --- a bridge with NO token anywhere: fail closed ---
P2="$(pick_port)"
mkdir -p "$TMP/home2"
env -u MESHD_TOKEN HOME="$TMP/home2" MESH_HOME="$TMP/home2/.mesh" PORT="$P2" BRIDGE_HOST=127.0.0.1 BRIDGE_TRUST_LOOPBACK=0 MUX=/nonexistent-mux \
  bun "$BRIDGE" >"$TMP/b2.log" 2>&1 &
PIDS="$PIDS $!"
wait_up "$P2"
B2="http://127.0.0.1:$P2"
expect "no token: health says loopback-only" '{"ok":true,"auth":"loopback-only"}' "$(curl -s -m 5 "$B2/health")"
expect "no token: cookie refused"  401 "$(code -H "Cookie: mesh_token=$TOKEN" "$B2/")"
expect "no token: bearer refused"  401 "$(code -H "Authorization: Bearer $TOKEN" "$B2/")"

# --- token from the file, loopback trusted (the default) ---
P3="$(pick_port)"
mkdir -p "$TMP/home3/.mesh" && printf '%s\n' "$TOKEN" >"$TMP/home3/.mesh/token"
env -u MESHD_TOKEN HOME="$TMP/home3" PORT="$P3" BRIDGE_HOST=127.0.0.1 MUX=/nonexistent-mux \
  bun "$BRIDGE" >"$TMP/b3.log" 2>&1 &
PIDS="$PIDS $!"
wait_up "$P3"
B3="http://127.0.0.1:$P3"
expect "file token: health says token" '{"ok":true,"auth":"token"}' "$(curl -s -m 5 "$B3/health")"
expect "loopback trusted by default" 200 "$(code "$B3/")"

[ "$fail" -eq 0 ] || { echo "check-bridge-auth: FAILED"; cat "$TMP/b1.log" | tail -5; exit 1; }
echo "check-bridge-auth: OK"

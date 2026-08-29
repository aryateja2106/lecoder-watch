#!/bin/sh
# check-host-guard.sh — this machine answers to its own name, and to nobody else's.
#
# meshd rejects a request whose Host header it does not recognise, with 421. That guard
# exists to stop DNS rebinding: a hostile site resolving its own domain to 127.0.0.1 so
# the victim's browser talks to this daemon under `Host: evil.example`. The daemon runs
# shell commands, so this matters.
#
# 0.5.0 shipped that guard comparing the Host against a set of IP ADDRESSES. So a machine
# addressed by its ADDRESS worked and a machine addressed by its NAME never could — and
# the iOS client stores a machine as [ip, host] and falls back to the name, while Tailscale
# MagicDNS makes the bare short name the natural thing to have stored. Every phone holding
# a machine by name got 421 the moment that machine upgraded. Measured on one machine where
# all three strings are the same machine:
#
#     Host: 100.94.221.115                      -> 200
#     Host: arya-macbook-pro.tailaddf1e.ts.net  -> 200
#     Host: arya-macbook-pro                    -> 421   <- what a phone sends
#
# Both halves are asserted here, because widening a security guard is exactly the change
# that quietly stops guarding.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-host-guard: SKIP (no bun)"; exit 0; }

TMP="$(mktemp -d)"
PORT=8892
PID=""
cleanup() { [ -n "$PID" ] && { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }; rm -rf "$TMP"; }
trap cleanup EXIT

TOKEN="check-host-guard-$$"
mkdir -p "$TMP/.mesh"
printf '%s\n' "$TOKEN" > "$TMP/.mesh/token"

HOME="$TMP" MESHD_TOKEN="$TOKEN" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" \
MESHD_EVENTS_PATH="$TMP/events.jsonl" MESHD_TELEMETRY=off \
  bun "$ROOT/install/payload/meshd/server.ts" >"$TMP/meshd.log" 2>&1 &
PID=$!

i=0
up=0
while [ "$i" -lt 60 ]; do
  curl -sf -m 2 -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && { up=1; break; }
  sleep 0.2
  i=$((i + 1))
done
[ "$up" = "1" ] || { echo "FAIL: check-host-guard: daemon never came up"; sed -n '1,15p' "$TMP/meshd.log"; exit 1; }

# The name refresh runs just after the listener opens and shells out to tailscale, so give
# it a moment. Without this the check races the very thing it is testing.
sleep 1.5

code() {
  curl -s -o /dev/null -w '%{http_code}' -m 5 \
    -H "Authorization: Bearer $TOKEN" -H "Host: $1" "http://127.0.0.1:$PORT/health"
}

ok=1
bad() { echo "FAIL: check-host-guard.sh: $1"; ok=0; }

HOST_FQDN="$(hostname 2>/dev/null | tr 'A-Z' 'a-z')"
HOST_SHORT="${HOST_FQDN%%.*}"

# --- must be allowed ---
[ "$(code "127.0.0.1:$PORT")" = "200" ] || bad "loopback was refused"
[ "$(code "localhost:$PORT")" = "200" ] || bad "localhost was refused"
if [ -n "$HOST_FQDN" ]; then
  got="$(code "$HOST_FQDN:$PORT")"
  [ "$got" = "200" ] || bad "this machine's own hostname '$HOST_FQDN' was refused with $got — that is the bug that broke every phone holding a machine by name"
fi
if [ -n "$HOST_SHORT" ] && [ "$HOST_SHORT" != "$HOST_FQDN" ]; then
  got="$(code "$HOST_SHORT:$PORT")"
  [ "$got" = "200" ] || bad "this machine's short name '$HOST_SHORT' was refused with $got — MagicDNS resolves the short name, so this is what a client stores"
fi

# --- must still be refused ---
for evil in "evil.example" "attacker.com" "localhost.evil.example" "127.0.0.1.evil.example"; do
  got="$(code "$evil:$PORT")"
  [ "$got" = "421" ] \
    || bad "a foreign Host '$evil' got $got instead of 421 — the DNS-rebinding guard is not guarding"
done

[ "$ok" -eq 1 ] || exit 1
echo "check-host-guard: OK (own name and short name accepted, foreign hosts still 421)"

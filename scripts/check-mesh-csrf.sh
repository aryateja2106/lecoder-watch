#!/bin/sh
# End-to-end proof of the two browser-facing guards, against a real daemon on a
# throwaway HOME and a loopback port. Static wiring checks can't see reordering or a
# guard that returns the wrong status; this exercises the actual HTTP path.
#
# The holes it pins shut:
#   - A web page the user visits sits on 127.0.0.1 too. Bun parses a text/plain body,
#     so a cross-site POST is a CORS "simple request" — no preflight. Without the
#     guard, the loopback exemption authorizes it: unauthenticated RCE.
#   - DNS rebinding (a domain that resolves to 127.0.0.1) makes the daemon same-origin
#     to the attacker's page, so its replies — including the token — become readable.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/install/payload/meshd"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-csrf: SKIP (bun not installed)"; exit 0; }

TH="$(mktemp -d)"
PORT=8977
LOG="$TH/meshd.log"
MESHD_TOKEN=csrf-check-token MESHD_PORT="$PORT" MESHD_HOST=127.0.0.1 HOME="$TH" bun run server.ts >"$LOG" 2>&1 &
SRV=$!
trap 'ec=$?; kill "$SRV" 2>/dev/null || true; wait "$SRV" 2>/dev/null || true; rm -rf "$TH"; exit "$ec"' EXIT

up=0
i=0
while [ "$i" -lt 50 ]; do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then up=1; break; fi
  # If the port is taken by something else, fail loud rather than probe a stranger.
  kill -0 "$SRV" 2>/dev/null || { echo "FAIL: meshd exited before listening"; cat "$LOG"; exit 1; }
  sleep 0.1; i=$((i + 1))
done
[ "$up" -eq 1 ] || { echo "FAIL: meshd never came up on $PORT"; cat "$LOG"; exit 1; }

code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }

# A legitimate client (URLSession / the mesh CLI) sends no browser headers; on loopback
# it is exempt and must reach the handler. 400 "events required" = it got through auth.
got="$(code -X POST -H 'content-type: text/plain' --data '{"events":[]}' "http://127.0.0.1:$PORT/input")"
[ "$got" = "400" ] || { echo "FAIL: a plain loopback POST should reach the handler, got $got"; exit 1; }

# A browser POST carrying Origin is cross-site by definition — must be rejected before
# the loopback exemption, with no side effect.
got="$(code -X POST -H 'content-type: text/plain' -H 'Origin: https://evil.example' --data '{"key":"x"}' "http://127.0.0.1:$PORT/agents/nope/send")"
[ "$got" = "401" ] || { echo "FAIL: cross-site POST (Origin) must be 401, got $got"; exit 1; }

# Sec-Fetch-Site the browser stamps itself, and the daemon cannot be talked out of it.
got="$(code -X POST -H 'Sec-Fetch-Site: cross-site' --data '{}' "http://127.0.0.1:$PORT/input")"
[ "$got" = "401" ] || { echo "FAIL: Sec-Fetch-Site cross-site must be 401, got $got"; exit 1; }

# A same-origin fetch from the daemon's own /desktop page must still work.
got="$(code -H 'Sec-Fetch-Site: same-origin' "http://127.0.0.1:$PORT/health")"
[ "$got" = "200" ] || { echo "FAIL: same-origin request must pass, got $got"; exit 1; }

# DNS rebinding: an attacker hostname resolving to 127.0.0.1 must be refused up front.
got="$(code -H 'Host: evil.example' "http://127.0.0.1:$PORT/health")"
[ "$got" = "421" ] || { echo "FAIL: rebinding Host must be 421, got $got"; exit 1; }

# The daemon addressing itself by loopback name is fine.
got="$(code -H 'Host: 127.0.0.1' "http://127.0.0.1:$PORT/health")"
[ "$got" = "200" ] || { echo "FAIL: loopback Host must pass, got $got"; exit 1; }

echo "check-mesh-csrf: OK"

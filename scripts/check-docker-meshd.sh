#!/bin/sh
# Build the meshd image, start a throwaway container, hit /health, tear down.
# Skips when docker is not installed (CI agents without Docker).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${MESHD_TEST_PORT:-18999}"
MAX_WAIT_SEC="${MESHD_TEST_WAIT_SEC:-30}"

if ! command -v docker >/dev/null 2>&1; then
  echo "check-docker-meshd: SKIP (no docker)"
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo "check-docker-meshd: SKIP (docker daemon not reachable — try sudo or add user to docker group)"
  exit 0
fi

NAME="meshd-smoke-$$"
cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

log() { printf 'check-docker-meshd: %s\n' "$*"; }

# curl_http URL — prints the HTTP status code (000 on connection failure).
curl_http() {
  curl -sS -o "$2" -w '%{http_code}' "$1" 2>/dev/null || printf '000'
}

log "building image"
docker build -t meshd:smoke "$ROOT" >/dev/null

log "starting container on 127.0.0.1:${PORT}"
docker run -d --name "$NAME" \
  -e MESHD_TELEMETRY=off \
  -e MESHD_CONTAINER=1 \
  -p "127.0.0.1:${PORT}:8899" \
  meshd:smoke >/dev/null

# Wait for a stable /health 200. During startup we have seen transient 403s and
# connection failures even though meshd is healthy a few seconds later.
deadline=$(( $(date +%s) + MAX_WAIT_SEC ))
code="000"
while [ "$(date +%s)" -lt "$deadline" ]; do
  code="$(curl_http "http://127.0.0.1:${PORT}/health" /tmp/meshd-health.json)"
  case "$code" in
    200)
      if grep -q '"ok":true' /tmp/meshd-health.json 2>/dev/null; then
        break
      fi
      ;;
    403|000|421|502|503)
      : # retry — meshd still booting or port not ready
      ;;
    *)
      # Any other non-200: keep trying until the deadline; fail only if it persists.
      :
      ;;
  esac
  sleep 0.5
done

if [ "$code" != "200" ] || ! grep -q '"ok":true' /tmp/meshd-health.json 2>/dev/null; then
  echo "check-docker-meshd: FAIL (/health never returned 200 ok=true within ${MAX_WAIT_SEC}s, last HTTP $code)"
  docker logs "$NAME" 2>&1 | tail -20
  [ -f /tmp/meshd-health.json ] && cat /tmp/meshd-health.json
  exit 1
fi

# Basic shape checks — match what server.ts actually returns.
grep -q '"platform":"linux"' /tmp/meshd-health.json || { echo "check-docker-meshd: FAIL (not linux)"; cat /tmp/meshd-health.json; exit 1; }
grep -q '"meshdVersion"' /tmp/meshd-health.json || { echo "check-docker-meshd: FAIL (no meshdVersion)"; cat /tmp/meshd-health.json; exit 1; }

# Container honesty: no screen peek or desktop input buttons on the phone.
grep -q '"screenPeek"' /tmp/meshd-health.json && { echo "check-docker-meshd: FAIL (advertised screenPeek in container)"; cat /tmp/meshd-health.json; exit 1; }
grep -q '"input"' /tmp/meshd-health.json && { echo "check-docker-meshd: FAIL (advertised input in container)"; cat /tmp/meshd-health.json; exit 1; }

# Pairing mint works on loopback without a bearer token.
pair_code="$(curl_http "http://127.0.0.1:${PORT}/pair/new" /tmp/meshd-pair.json)"
[ "$pair_code" = "200" ] || { echo "check-docker-meshd: FAIL (/pair/new HTTP $pair_code)"; cat /tmp/meshd-pair.json 2>/dev/null; exit 1; }
grep -q '"code"' /tmp/meshd-pair.json || { echo "check-docker-meshd: FAIL (/pair/new body)"; cat /tmp/meshd-pair.json; exit 1; }

log "ok ($(tr -d '\n' < /tmp/meshd-health.json | head -c 120)…)"

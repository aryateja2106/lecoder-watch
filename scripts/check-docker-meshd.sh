#!/bin/sh
# Build the meshd image, start a throwaway container, hit /health, tear down.
# Skips when docker is not installed (CI agents without Docker).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${MESHD_TEST_PORT:-18999}"

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

log "building image"
docker build -t meshd:smoke "$ROOT" >/dev/null

log "starting container on 127.0.0.1:${PORT}"
docker run -d --name "$NAME" \
  -e MESHD_TELEMETRY=off \
  -p "127.0.0.1:${PORT}:8899" \
  meshd:smoke >/dev/null

# Wait for /health (entrypoint + bun startup).
attempt=1
while [ "$attempt" -le 20 ]; do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/tmp/meshd-health.json 2>/dev/null; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.5
done

if [ ! -s /tmp/meshd-health.json ]; then
  echo "check-docker-meshd: FAIL (/health never answered)"
  docker logs "$NAME" 2>&1 | tail -20
  exit 1
fi

# Basic shape checks — match what server.ts actually returns.
grep -q '"ok":true' /tmp/meshd-health.json || { echo "check-docker-meshd: FAIL (ok not true)"; cat /tmp/meshd-health.json; exit 1; }
grep -q '"platform":"linux"' /tmp/meshd-health.json || { echo "check-docker-meshd: FAIL (not linux)"; cat /tmp/meshd-health.json; exit 1; }
grep -q '"meshdVersion"' /tmp/meshd-health.json || { echo "check-docker-meshd: FAIL (no meshdVersion)"; cat /tmp/meshd-health.json; exit 1; }

# Pairing mint works on loopback without a bearer token.
pair_new="$(curl -fsS "http://127.0.0.1:${PORT}/pair/new")"
echo "$pair_new" | grep -q '"code"' || { echo "check-docker-meshd: FAIL (/pair/new)"; echo "$pair_new"; exit 1; }

log "ok ($(tr -d '\n' < /tmp/meshd-health.json | head -c 120)…)"

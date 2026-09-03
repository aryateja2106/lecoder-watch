#!/bin/sh
# Build the meshd image, start a throwaway container, hit /health, pair via
# `docker exec … mesh pair`, tear down. Skips when docker is not usable.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${MESHD_TEST_PORT:-18999}"
MAX_WAIT_SEC="${MESHD_TEST_WAIT_SEC:-45}"

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

curl_http() {
  curl -sS -o "$2" -w '%{http_code}' "$1" 2>/dev/null || printf '000'
}

log "building image"
docker build -t meshd:smoke "$ROOT"

SIZE="$(docker images meshd:smoke --format '{{.Size}}')"
log "image size ${SIZE} (previous proven size was 234MB)"

log "starting container on 127.0.0.1:${PORT}"
docker run -d --name "$NAME" \
  -e MESHD_TELEMETRY=off \
  -e MESHD_CONTAINER=1 \
  -p "127.0.0.1:${PORT}:8899" \
  meshd:smoke >/dev/null

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
    000|421|502|503) : ;;
    *) : ;;
  esac
  sleep 0.5
done

if [ "$code" != "200" ] || ! grep -q '"ok":true' /tmp/meshd-health.json 2>/dev/null; then
  echo "check-docker-meshd: FAIL (/health never returned 200 ok=true within ${MAX_WAIT_SEC}s, last HTTP $code)"
  docker logs "$NAME" 2>&1 | tail -20
  [ -f /tmp/meshd-health.json ] && cat /tmp/meshd-health.json
  exit 1
fi

grep -q '"platform":"linux"' /tmp/meshd-health.json || { echo "check-docker-meshd: FAIL (not linux)"; cat /tmp/meshd-health.json; exit 1; }
grep -q '"meshdVersion"' /tmp/meshd-health.json || { echo "check-docker-meshd: FAIL (no meshdVersion)"; cat /tmp/meshd-health.json; exit 1; }
grep -q '"screenPeek"' /tmp/meshd-health.json && { echo "check-docker-meshd: FAIL (advertised screenPeek in container)"; cat /tmp/meshd-health.json; exit 1; }
grep -q '"input"' /tmp/meshd-health.json && { echo "check-docker-meshd: FAIL (advertised input in container)"; cat /tmp/meshd-health.json; exit 1; }

who="$(docker exec "$NAME" /usr/bin/id -un)"
uid="$(docker exec "$NAME" /usr/bin/id -u)"
[ "$uid" != "0" ] || { echo "check-docker-meshd: FAIL (container runs as root)"; exit 1; }
[ "$who" != "root" ] || { echo "check-docker-meshd: FAIL (whoami is root)"; exit 1; }

# Dockerfile HEALTHCHECK must actually go healthy (not just /health from the host).
health_deadline=$(( $(date +%s) + MAX_WAIT_SEC ))
hc="none"
while [ "$(date +%s)" -lt "$health_deadline" ]; do
  hc="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$NAME")"
  [ "$hc" = "healthy" ] && break
  sleep 1
done
[ "$hc" = "healthy" ] || {
  echo "check-docker-meshd: FAIL (HEALTHCHECK status is ${hc}, want healthy)"
  docker inspect -f '{{json .State.Health}}' "$NAME" 2>/dev/null | head -c 400
  echo
  exit 1
}

# Pairing mint is loopback-only. Host-mapped curl is not enough — run the real CLI
# inside the container, the same command docs tell a user to run.
pair_json="$(docker exec "$NAME" mesh pair --address 127.0.0.1 --json)" \
  || { echo "check-docker-meshd: FAIL (docker exec mesh pair)"; docker logs "$NAME" 2>&1 | tail -20; exit 1; }
echo "$pair_json" | grep -q '"code"' || { echo "check-docker-meshd: FAIL (mesh pair --json missing code)"; echo "$pair_json"; exit 1; }
echo "$pair_json" | grep -q '"pretty"' || { echo "check-docker-meshd: FAIL (mesh pair --json missing pretty)"; echo "$pair_json"; exit 1; }

log "ok user=${who} uid=${uid} health=${hc} size=${SIZE}"

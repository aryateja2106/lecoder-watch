#!/bin/zsh -l
# Inner starter — must run under login zsh so cmux accepts the connection.
set -e
BRIDGE_PORT="${CMUX_BRIDGE_PORT:-8901}"
healthy() {
  curl -sf -X POST "http://127.0.0.1:${BRIDGE_PORT}/cmux" \
    -H 'content-type: application/json' \
    -d '{"args":["tree","--all","--json"]}' \
    | grep -q '"windows"[[:space:]]*:[[:space:]]*\['
}
if curl -sf "http://127.0.0.1:${BRIDGE_PORT}/health" >/dev/null && healthy; then exit 0; fi
lsof -ti ":${BRIDGE_PORT}" | xargs kill -9 2>/dev/null || true
sleep 0.5
MESH_HOME="${MESH_HOME:-$HOME/.mesh}"
CMUX_PORT="${CMUX_PORT:-9160}"
LOG="/tmp/cmux-bridge.log"
nohup launchctl asuser "$(id -u)" /bin/zsh -lc \
  "cd '$MESH_HOME/meshd' && PATH='/Applications/cmux.app/Contents/Resources/bin:/opt/homebrew/bin:/usr/bin:/bin' CMUX_PORT='$CMUX_PORT' exec /opt/homebrew/bin/bun run cmux-bridge.ts >>'$LOG' 2>&1" \
  >/dev/null 2>&1 &
for i in {1..20}; do healthy && exit 0; sleep 0.25; done
echo "cmux-bridge failed to start; see $LOG" >&2
exit 1

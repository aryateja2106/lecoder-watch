#!/bin/zsh -l
# Inner starter — must run under login zsh so cmux accepts the connection.
set -e
BRIDGE_PORT="${CMUX_BRIDGE_PORT:-8901}"
# ponytail: /health is the whole readiness test. The old gate ALSO required cmux to
# report a windows array, which is false whenever the cmux GUI is closed — so this
# tore down a perfectly healthy bridge every time it ran. Zero windows is healthy.
if curl -sf -m 1 "http://127.0.0.1:${BRIDGE_PORT}/health" >/dev/null; then exit 0; fi
# -sTCP:LISTEN is load-bearing. `lsof -i :PORT` matches a socket with that port on
# EITHER end, so the bare form also listed every client CONNECTED to the bridge —
# and meshd is one, because /agents asks the bridge for cmux sessions. Opening any
# new interactive shell while the bridge looked unhealthy therefore kill -9'd the
# user's running meshd. Only the process actually holding the port may be replaced.
lsof -ti "tcp:${BRIDGE_PORT}" -sTCP:LISTEN | xargs kill -9 2>/dev/null || true
sleep 0.5
MESH_HOME="${MESH_HOME:-$HOME/.mesh}"
CMUX_PORT="${CMUX_PORT:-9160}"
LOG="/tmp/cmux-bridge.log"
nohup launchctl asuser "$(id -u)" /bin/zsh -lc \
  "cd '$MESH_HOME/meshd' && PATH='/Applications/cmux.app/Contents/Resources/bin:/opt/homebrew/bin:/usr/bin:/bin' CMUX_PORT='$CMUX_PORT' exec /opt/homebrew/bin/bun run cmux-bridge.ts >>'$LOG' 2>&1" \
  >/dev/null 2>&1 &
for i in {1..20}; do curl -sf -m 1 "http://127.0.0.1:${BRIDGE_PORT}/health" >/dev/null && exit 0; sleep 0.25; done
echo "cmux-bridge failed to start; see $LOG" >&2
exit 1

# Source from ~/.zshrc — bridge must start in the current shell (not a background subshell).
start_cmux_bridge() {
  local port="${CMUX_BRIDGE_PORT:-8901}"
  local mesh_home="${MESH_HOME:-$HOME/.mesh}"
  local cmux_port="${CMUX_PORT:-9160}"
  local log="/tmp/cmux-bridge.log"

  # ponytail: /health is the whole readiness test. The old gate ALSO required cmux to
  # report >=1 window, so with the cmux GUI closed it was false forever: every interactive
  # shell tore the bridge down, respawned it, then blocked ~14s in a 20-round curl+python
  # poll before giving up — and leaked an EADDRINUSE bun process each time. A bridge
  # serving zero windows is a healthy bridge with nothing to show. -m 1 so a wedged
  # bridge costs one second, not a hung prompt.
  curl -sf -m 1 "http://127.0.0.1:${port}/health" >/dev/null 2>&1 && return 0

  # -sTCP:LISTEN is load-bearing. `lsof -i :PORT` matches a socket with that port on
  # EITHER end, so the bare form also listed every client CONNECTED to the bridge —
  # and meshd is one, because /agents asks the bridge for cmux sessions. Opening any
  # new interactive shell while the bridge looked unhealthy therefore kill -9'd the
  # user's running meshd. Only the process actually holding the port may be replaced.
  lsof -ti "tcp:${port}" -sTCP:LISTEN | xargs kill -9 2>/dev/null || true
  sleep 0.5  # ponytail: let the port drain, else the respawn hits EADDRINUSE. Cold path only.
  nohup launchctl asuser "$(id -u)" /bin/zsh -lc \
    "cd '$mesh_home/meshd' && PATH='/Applications/cmux.app/Contents/Resources/bin:/opt/homebrew/bin:/usr/bin:/bin' CMUX_PORT='$cmux_port' exec /opt/homebrew/bin/bun run cmux-bridge.ts >>'$log' 2>&1" \
    >/dev/null 2>&1 &
  # ponytail: no wait loop. The prompt does not need a ready bridge — its clients (meshd,
  # the watch) retry on their own, and the next shell's /health confirms it came up.
}

if [[ -o interactive ]] && command -v cmux >/dev/null 2>&1; then
  start_cmux_bridge >/dev/null 2>&1 || true
fi

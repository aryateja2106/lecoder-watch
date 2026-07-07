# Source from ~/.zshrc — bridge must start in the current shell (not a background subshell).
start_cmux_bridge() {
  local port="${CMUX_BRIDGE_PORT:-8901}"
  local mesh_home="${MESH_HOME:-$HOME/.mesh}"
  local cmux_port="${CMUX_PORT:-9160}"
  local log="/tmp/cmux-bridge.log"

  _cmux_bridge_healthy() {
    curl -sf -X POST "http://127.0.0.1:${port}/cmux" \
      -H 'content-type: application/json' \
      -d '{"args":["tree","--all","--json"]}' \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',{}).get('windows',[])))" 2>/dev/null \
    | grep -qv '^0$'
  }

  if curl -sf "http://127.0.0.1:${port}/health" >/dev/null 2>&1 && _cmux_bridge_healthy; then
    return 0
  fi
  lsof -ti ":${port}" | xargs kill -9 2>/dev/null || true
  sleep 0.5
  nohup launchctl asuser "$(id -u)" /bin/zsh -lc \
    "cd '$mesh_home/meshd' && PATH='/Applications/cmux.app/Contents/Resources/bin:/opt/homebrew/bin:/usr/bin:/bin' CMUX_PORT='$cmux_port' exec /opt/homebrew/bin/bun run cmux-bridge.ts >>'$log' 2>&1" \
    >/dev/null 2>&1 &
  local i=0
  while [ "$i" -lt 20 ]; do
    _cmux_bridge_healthy && return 0
    i=$((i + 1))
    sleep 0.25
  done
  echo "cmux-bridge failed to start; see $log" >&2
  return 1
}

if [[ -o interactive ]] && command -v cmux >/dev/null 2>&1; then
  start_cmux_bridge >/dev/null 2>&1 || true
fi

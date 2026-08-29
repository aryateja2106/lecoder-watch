# Source from ~/.zshrc — bridge must start in the current shell (not a background subshell).
#
# This runs on EVERY interactive shell, so it has one hard budget: it must be
# imperceptible. It used to cost 14.4 seconds, measured, for the reason in
# `_cmux_bridge_healthy` below.
start_cmux_bridge() {
  local port="${CMUX_BRIDGE_PORT:-8901}"
  local mesh_home="${MESH_HOME:-$HOME/.mesh}"
  local cmux_port="${CMUX_PORT:-9160}"
  local log="/tmp/cmux-bridge.log"
  local stamp="${TMPDIR:-/tmp}/.cmux-bridge-restart"

  # Healthy means THE BRIDGE ANSWERS. It used to mean "cmux currently has at least one
  # window open", which is not a property of the bridge at all — it is a property of a
  # separate desktop app. With cmux.app closed the bridge correctly answers /health and
  # correctly returns 502 from /cmux ("connect to cmux.sock: connection refused"), the
  # old gate read that as broken, and so every interactive shell kill -9'd a perfectly
  # working bridge and then sat through a 20 x 0.25s retry loop that could never
  # succeed, because restarting the bridge cannot start cmux. 14.4s per shell, for a
  # question that had no right answer.
  if curl -sf -m 1 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
    return 0
  fi

  # Something holds the port but is not answering: either still booting, or wedged.
  # Shooting it immediately lets a burst of shells kill a bridge that is merely starting;
  # never shooting it leaves a wedged one there forever — an unconditional early return
  # here made the kill below unreachable, because it selects by the very same predicate.
  # So: at most one restart attempt per minute, shared across every shell.
  if lsof -ti "tcp:${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    if [ -f "$stamp" ] && [ -z "$(find "$stamp" -mmin +1 2>/dev/null)" ]; then
      return 0
    fi
  fi
  : > "$stamp" 2>/dev/null || true

  # -sTCP:LISTEN is load-bearing. `lsof -i :PORT` matches a socket with that port on
  # EITHER end, so the bare form also listed every client CONNECTED to the bridge —
  # and meshd is one, because /agents asks the bridge for cmux sessions. Opening any
  # new interactive shell while the bridge looked unhealthy therefore kill -9'd the
  # user's running meshd. Only the process actually holding the port may be replaced.
  lsof -ti "tcp:${port}" -sTCP:LISTEN | xargs kill -9 2>/dev/null || true
  nohup launchctl asuser "$(id -u)" /bin/zsh -lc \
    "cd '$mesh_home/meshd' && PATH='/Applications/cmux.app/Contents/Resources/bin:/opt/homebrew/bin:/usr/bin:/bin' CMUX_PORT='$cmux_port' exec /opt/homebrew/bin/bun run cmux-bridge.ts >>'$log' 2>&1" \
    >/dev/null 2>&1 &
  # Detach, or zsh prints "[4] 2109" at the prompt and "[4] + killed ..." later —
  # job-control noise in the user's terminal for a daemon they did not launch.
  disown 2>/dev/null || true

  # Deliberately no wait loop. A shell must never block on a daemon coming up: if the
  # bridge is broken, `mesh doctor` is where you find out, not the prompt.
  return 0
}

if [[ -o interactive ]] && command -v cmux >/dev/null 2>&1; then
  start_cmux_bridge >/dev/null 2>&1 || true
fi

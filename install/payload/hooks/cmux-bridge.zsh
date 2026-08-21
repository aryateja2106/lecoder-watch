# Source from ~/.zshrc — auto-start cmux-bridge in a detached tmux session (survives Terminal close).
start_cmux_bridge() {
  if [[ ! -o interactive ]]; then
    return 1
  fi
  local MESH_HOME="${MESH_HOME:-$HOME/.mesh}"
  local CMUX_PORT="${CMUX_PORT:-9160}"
  local BUN="${BUN_BIN:-/opt/homebrew/bin/bun}"
  local LOG="/tmp/cmux-bridge.log"
  local PORT="${CMUX_BRIDGE_PORT:-8901}"
  local TMUX_SESSION="${CMUX_BRIDGE_TMUX:-mesh-cmux-bridge}"
  local LOCK="${TMPDIR:-/tmp}/cmux-bridge.hook.lock"
  local PATH_ENV='/Applications/cmux.app/Contents/Resources/bin:/opt/homebrew/bin:/usr/bin:/bin'

  _cmux_probe() {
    curl -sf --max-time 3 -X POST "http://127.0.0.1:${PORT}/cmux" \
      -H 'content-type: application/json' \
      -d '{"args":["tree","--all","--json"]}' \
    | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if len(d.get('data',{}).get('windows',[]))>0 else 1)" 2>/dev/null
  }

  if _cmux_probe; then return 0; fi

  local waited=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    _cmux_probe && return 0
    waited=$((waited + 1))
    [ "$waited" -ge 40 ] && return 1
    sleep 0.15
  done
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM

  if _cmux_probe; then return 0; fi

  if command -v tmux >/dev/null 2>&1; then
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
      local i=0
      while [ "$i" -lt 16 ]; do
        _cmux_probe && return 0
        i=$((i + 1))
        sleep 0.25
      done
      tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
      sleep 0.3
    fi
    tmux new-session -d -s "$TMUX_SESSION" \
      "export PATH='$PATH_ENV' CMUX_PORT='$CMUX_PORT'; cd '$MESH_HOME/meshd' && exec '$BUN' run cmux-bridge.ts >>'$LOG' 2>&1"
  else
    cd "$MESH_HOME/meshd" || return 1
    nohup env PATH="$PATH_ENV" CMUX_PORT="$CMUX_PORT" "$BUN" run cmux-bridge.ts >>"$LOG" 2>&1 &
    disown -h $! 2>/dev/null || disown $! 2>/dev/null || true
  fi

  local i=0
  while [ "$i" -lt 24 ]; do
    _cmux_probe && return 0
    i=$((i + 1))
    sleep 0.25
  done
  return 1
}

if [[ -o interactive ]] && [[ -z "${ZSH_EXECUTION_STRING:-}" ]] && command -v cmux >/dev/null 2>&1; then
  start_cmux_bridge >/dev/null 2>&1 || true
fi

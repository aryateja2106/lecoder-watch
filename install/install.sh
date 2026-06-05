#!/bin/sh

set -e

MESH_HOME="${MESH_HOME:-$HOME/.mesh}"
MESHD_DEFAULT_PORT="8899"
BRIDGE_DEFAULT_PORT="7820"

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: sh install.sh [--token VALUE] [--uninstall] [--help]

Options:
  --token VALUE   Set MESHD_TOKEN for meshd.
  --uninstall     Stop mesh services and remove \$MESH_HOME.
  --help, -h      Show this help text.
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "required command not found: $1"
  fi
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

append_env() {
  if [ -n "$3" ]; then
    printf '%s %s=%s\n' "$1" "$2" "$(shell_quote "$3")"
  else
    printf '%s\n' "$1"
  fi
}

gen_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
    return 0
  fi
  if command -v od >/dev/null 2>&1; then
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
    return 0
  fi
  if command -v hexdump >/dev/null 2>&1; then
    hexdump -vn16 -e '16/1 "%02x"' /dev/urandom
    return 0
  fi
  die "unable to generate token; need openssl, od, or hexdump"
}

wait_http() {
  wait_url="$1"
  wait_attempt=1
  while [ "$wait_attempt" -le 10 ]; do
    if curl -fsS "$wait_url" >/dev/null 2>&1; then
      return 0
    fi
    wait_attempt=$((wait_attempt + 1))
    if sleep 0.5 2>/dev/null; then
      :
    else
      sleep 1
    fi
  done
  return 1
}

kill_session() {
  session_name="$1"
  if tmux has-session -t "$session_name" 2>/dev/null; then
    tmux kill-session -t "$session_name"
  fi
}

start_session() {
  session_name="$1"
  session_dir="$2"
  session_cmd="$3"
  kill_session "$session_name"
  tmux new-session -d -s "$session_name" -c "$session_dir" "$session_cmd"
}

linux_tmux_hint() {
  distro_id=""
  if [ -r /etc/os-release ]; then
    distro_id=$(
      . /etc/os-release
      printf '%s' "${ID:-}"
    )
  fi
  case "$distro_id" in
    ubuntu|debian|raspbian)
      printf '%s\n' "sudo apt-get install tmux"
      ;;
    fedora|rhel|centos|rocky|almalinux)
      printf '%s\n' "sudo dnf install tmux"
      ;;
    arch|manjaro)
      printf '%s\n' "sudo pacman -S tmux"
      ;;
    *)
      printf '%s\n' "install tmux with your distro package manager"
      ;;
  esac
}

ensure_bun() {
  if command -v bun >/dev/null 2>&1; then
    return 0
  fi
  if [ -x "$HOME/.bun/bin/bun" ]; then
    PATH="$HOME/.bun/bin:$PATH"
    export PATH
    return 0
  fi

  need_cmd curl
  bun_installer=$(mktemp "${TMPDIR:-/tmp}/bun-install.XXXXXX")
  log "Installing bun into $HOME/.bun"
  curl -fsSL https://bun.sh/install -o "$bun_installer"
  sh "$bun_installer"
  rm -f "$bun_installer"

  PATH="$HOME/.bun/bin:$PATH"
  export PATH
  if ! command -v bun >/dev/null 2>&1; then
    die "bun install completed but bun is still unavailable"
  fi
}

ensure_tmux() {
  if command -v tmux >/dev/null 2>&1; then
    return 0
  fi
  if [ "$OS_NAME" = "Darwin" ]; then
    die "tmux is required to run mesh services in detached sessions. Install it with: brew install tmux"
  fi
  die "tmux is required to run mesh services in detached sessions. Install it with: $(linux_tmux_hint)"
}

resolve_script_dir() {
  case "$0" in
    */*)
      script_path="$0"
      ;;
    *)
      script_path=$(command -v "$0" 2>/dev/null || printf '%s\n' "$0")
      ;;
  esac

  script_dir=$(
    # shellcheck disable=SC1007  # `CDPATH=` is an intentional command prefix that neutralizes CDPATH for this cd
    CDPATH= cd -- "$(dirname "$script_path")" >/dev/null 2>&1 && pwd
  ) || die "unable to resolve installer directory"
  printf '%s\n' "$script_dir"
}

install_payload() {
  mkdir -p "$MESH_HOME"
  rm -rf "$MESH_HOME/meshd" "$MESH_HOME/rmux-bridge"
  cp -R "$PAYLOAD_DIR/meshd" "$MESH_HOME/"
  cp -R "$PAYLOAD_DIR/rmux-bridge" "$MESH_HOME/"
}

install_deps() {
  deps_dir="$1"
  (
    cd "$deps_dir"
    bun install
  )
}

parse_args() {
  TOKEN_FLAG=""
  DO_UNINSTALL="0"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --token)
        shift
        [ "$#" -gt 0 ] || die "--token requires a value"
        TOKEN_FLAG="$1"
        ;;
      --uninstall)
        DO_UNINSTALL="1"
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown flag: $1"
        ;;
    esac
    shift
  done
}

parse_args "$@"

OS_NAME=$(uname -s 2>/dev/null || printf '%s\n' "")
ARCH_NAME=$(uname -m 2>/dev/null || printf '%s\n' "")

case "$OS_NAME" in
  Darwin|Linux)
    ;;
  *)
    die "unsupported operating system: ${OS_NAME:-unknown}. Expected Darwin or Linux."
    ;;
esac

case "$ARCH_NAME" in
  arm64|aarch64|x86_64)
    ;;
  *)
    die "unsupported architecture: ${ARCH_NAME:-unknown}. Expected arm64, aarch64, or x86_64."
    ;;
esac

if [ "$DO_UNINSTALL" = "1" ]; then
  if command -v tmux >/dev/null 2>&1; then
    kill_session "meshd" || true
    kill_session "rmux-bridge" || true
  fi
  rm -rf "$MESH_HOME"
  log "Removed tmux sessions: meshd rmux-bridge"
  log "Removed directory: $MESH_HOME"
  exit 0
fi

need_cmd cp
need_cmd curl
need_cmd head
need_cmd rm
need_cmd uname

ensure_bun
ensure_tmux

SCRIPT_DIR=$(resolve_script_dir)
PAYLOAD_DIR="$SCRIPT_DIR/payload"

[ -f "$PAYLOAD_DIR/meshd/server.ts" ] || die "missing payload file: $PAYLOAD_DIR/meshd/server.ts"
[ -f "$PAYLOAD_DIR/meshd/package.json" ] || die "missing payload file: $PAYLOAD_DIR/meshd/package.json"
[ -f "$PAYLOAD_DIR/rmux-bridge/src/server.ts" ] || die "missing payload file: $PAYLOAD_DIR/rmux-bridge/src/server.ts"
[ -f "$PAYLOAD_DIR/rmux-bridge/package.json" ] || die "missing payload file: $PAYLOAD_DIR/rmux-bridge/package.json"
[ -f "$PAYLOAD_DIR/rmux-bridge/public/index.html" ] || die "missing payload file: $PAYLOAD_DIR/rmux-bridge/public/index.html"
[ -f "$PAYLOAD_DIR/rmux-bridge/public/vendor/xterm.js" ] || die "missing payload file: $PAYLOAD_DIR/rmux-bridge/public/vendor/xterm.js"

TOKEN_VALUE="${TOKEN_FLAG:-${MESHD_TOKEN:-}}"
if [ -z "$TOKEN_VALUE" ]; then
  TOKEN_VALUE=$(gen_token)
fi

MESHD_PORT_VALUE="${MESHD_PORT:-$MESHD_DEFAULT_PORT}"
BRIDGE_PORT_VALUE="${PORT:-$BRIDGE_DEFAULT_PORT}"
EFFECTIVE_MESHD_MUX="${MESH_MUX:-}"
EFFECTIVE_BRIDGE_MUX="${MUX:-}"

if [ "$OS_NAME" = "Darwin" ]; then
  if command -v rmux >/dev/null 2>&1; then
    log "rmux detected; services will use their macOS default multiplexer."
  else
    log "rmux not found; forcing services to use tmux."
    if [ -z "$EFFECTIVE_MESHD_MUX" ]; then
      EFFECTIVE_MESHD_MUX="tmux"
    fi
    if [ -z "$EFFECTIVE_BRIDGE_MUX" ]; then
      EFFECTIVE_BRIDGE_MUX="tmux"
    fi
  fi
fi

install_payload
install_deps "$MESH_HOME/meshd"
install_deps "$MESH_HOME/rmux-bridge"

meshd_cmd="env PATH=$(shell_quote "$PATH") MESHD_TOKEN=$(shell_quote "$TOKEN_VALUE") MESHD_PORT=$(shell_quote "$MESHD_PORT_VALUE")"
meshd_cmd=$(append_env "$meshd_cmd" "MESH_MUX" "$EFFECTIVE_MESHD_MUX")
meshd_cmd="$meshd_cmd bun run server.ts"

bridge_cmd="env PATH=$(shell_quote "$PATH") PORT=$(shell_quote "$BRIDGE_PORT_VALUE")"
bridge_cmd=$(append_env "$bridge_cmd" "BRIDGE_HOST" "${BRIDGE_HOST:-}")
bridge_cmd=$(append_env "$bridge_cmd" "MUX" "$EFFECTIVE_BRIDGE_MUX")
bridge_cmd="$bridge_cmd bun run src/server.ts"

start_session "meshd" "$MESH_HOME/meshd" "$meshd_cmd"
start_session "rmux-bridge" "$MESH_HOME/rmux-bridge" "$bridge_cmd"

MESHD_STATUS="down"
BRIDGE_STATUS="down"

if wait_http "http://127.0.0.1:${MESHD_PORT_VALUE}/health"; then
  MESHD_STATUS="up"
fi
if wait_http "http://127.0.0.1:${BRIDGE_PORT_VALUE}/"; then
  BRIDGE_STATUS="up"
fi

TAILSCALE_IP=""
if command -v tailscale >/dev/null 2>&1; then
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1)
fi

printf '\n'
printf 'meshd: %s\n' "$MESHD_STATUS"
printf 'rmux-bridge: %s\n' "$BRIDGE_STATUS"
if [ -n "$TAILSCALE_IP" ]; then
  printf 'Tailscale IPv4: %s\n' "$TAILSCALE_IP"
  printf 'meshd URL: http://%s:%s\n' "$TAILSCALE_IP" "$MESHD_PORT_VALUE"
  printf 'bridge URL: http://%s:%s\n' "$TAILSCALE_IP" "$BRIDGE_PORT_VALUE"
else
  printf 'Tailscale IPv4: unavailable (run "tailscale ip -4" after Tailscale is connected)\n'
fi
printf 'MESHD token: %s\n' "$TOKEN_VALUE"

if [ "$MESHD_STATUS" != "up" ] || [ "$BRIDGE_STATUS" != "up" ]; then
  exit 1
fi

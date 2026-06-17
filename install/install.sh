#!/bin/sh
# Mesh installer — one command to install or uninstall the mesh stack
# (meshd, rmux-bridge, agent hook tools) on any macOS or Linux machine.
#
# Detects OS + arch + multiplexer, fetches the payload (remote tarball or a
# local checkout), installs under $MESH_HOME, and starts detached tmux services.
# Curl-friendly:
#   curl -fsSL <host>/install.sh | sh
#   curl -fsSL <host>/install.sh | sh -s -- --only meshd --token T
#   curl -fsSL <host>/install.sh | sh -s -- --uninstall --purge
#
# Nothing is hardcoded: source, components, prefix, ports and token are all
# overridable via flags or environment.

set -eu

# Baked in at package time (packager rewrites the placeholder). May be a base
# URL (we fetch $BASE/mesh-install.tgz), a direct .tgz/.tar.gz URL, or a local
# tarball path. Left as the placeholder = no default source (use --src or a
# local ./payload checkout).
MESH_SRC_DEFAULT="__MESH_SRC__"

MESH_HOME="${MESH_HOME:-$HOME/.mesh}"
MESHD_DEFAULT_PORT="8899"
BRIDGE_DEFAULT_PORT="7820"
ALL_COMPONENTS="meshd bridge tools"

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Mesh installer — meshd, rmux-bridge, and agent hook tools.

Usage:
  install.sh [options]
  curl -fsSL <host>/install.sh | sh -s -- [options]

Options:
  --token VALUE    Auth token for meshd (default: \$MESHD_TOKEN or generated).
  --src SRC        Payload source: a base URL (fetches SRC/mesh-install.tgz),
                   a direct .tgz/.tar.gz URL, or a local tarball path.
                   Default: baked-in source, else a local ./payload checkout.
  --only LIST      Install only these components (comma list).
  --without LIST   Install everything except these components.
  --prefix DIR     Install location (default: \$MESH_HOME or ~/.mesh).
  --no-start       Install but do not launch services.
  --list           Show what is installed under the prefix, then exit.
  --uninstall      Stop services and remove the selected components.
  --purge          With --uninstall, also remove the token and the prefix dir.
  --help, -h       Show this help.

Components: $ALL_COMPONENTS
  meshd  = stats/sessions/events daemon (:$MESHD_DEFAULT_PORT)
  bridge = rmux-bridge live terminal stream (:$BRIDGE_DEFAULT_PORT)
  tools  = mesh-event/mesh-hook/mesh-agent-run/mesh-self-check + hook examples
EOF
}

# ---------- small helpers (unchanged behaviour) ----------

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

append_env() {
  if [ -n "$3" ]; then printf '%s %s=%s\n' "$1" "$2" "$(shell_quote "$3")"
  else printf '%s\n' "$1"; fi
}

gen_token() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 16; return 0; fi
  if command -v od >/dev/null 2>&1; then od -An -N16 -tx1 /dev/urandom | tr -d ' \n'; return 0; fi
  if command -v hexdump >/dev/null 2>&1; then hexdump -vn16 -e '16/1 "%02x"' /dev/urandom; return 0; fi
  die "unable to generate token; need openssl, od, or hexdump"
}

wait_http() {
  wait_attempt=1
  while [ "$wait_attempt" -le 10 ]; do
    if curl -fsS "$1" >/dev/null 2>&1; then return 0; fi
    wait_attempt=$((wait_attempt + 1))
    sleep 0.5 2>/dev/null || sleep 1
  done
  return 1
}

kill_session() {
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$1" 2>/dev/null; then
    tmux kill-session -t "$1" 2>/dev/null || true
    return 0
  fi
  return 1
}

start_session() {
  kill_session "$1" >/dev/null 2>&1 || true
  tmux new-session -d -s "$1" -c "$2" "$3"
}

linux_tmux_hint() {
  distro_id=""
  if [ -r /etc/os-release ]; then distro_id=$(. /etc/os-release; printf '%s' "${ID:-}"); fi
  case "$distro_id" in
    ubuntu|debian|raspbian) printf 'sudo apt-get install tmux\n';;
    fedora|rhel|centos|rocky|almalinux) printf 'sudo dnf install tmux\n';;
    arch|manjaro) printf 'sudo pacman -S tmux\n';;
    *) printf 'install tmux with your distro package manager\n';;
  esac
}

ensure_bun() {
  if command -v bun >/dev/null 2>&1; then return 0; fi
  if [ -x "$HOME/.bun/bin/bun" ]; then PATH="$HOME/.bun/bin:$PATH"; export PATH; return 0; fi
  need_cmd curl
  bun_installer=$(mktemp "${TMPDIR:-/tmp}/bun-install.XXXXXX")
  log "Installing bun into $HOME/.bun"
  curl -fsSL https://bun.sh/install -o "$bun_installer"
  sh "$bun_installer"
  rm -f "$bun_installer"
  PATH="$HOME/.bun/bin:$PATH"; export PATH
  command -v bun >/dev/null 2>&1 || die "bun install completed but bun is still unavailable"
}

ensure_tmux() {
  if command -v tmux >/dev/null 2>&1; then return 0; fi
  if [ "$OS_NAME" = "Darwin" ]; then
    die "tmux is required. Install it with: brew install tmux"
  fi
  die "tmux is required. Install it with: $(linux_tmux_hint)"
}

resolve_script_dir() {
  case "$0" in
    */*) script_path="$0";;
    *)   script_path=$(command -v "$0" 2>/dev/null || printf '%s\n' "$0");;
  esac
  # shellcheck disable=SC1007
  ( CDPATH= cd -- "$(dirname "$script_path")" >/dev/null 2>&1 && pwd ) \
    || die "unable to resolve installer directory"
}

# ---------- component selection ----------

want_component() {
  case " $SELECTED_COMPONENTS " in *" $1 "*) return 0;; *) return 1;; esac
}

validate_components() {
  for c in $1; do
    case " $ALL_COMPONENTS " in *" $c "*) ;; *) die "unknown component: $c (valid: $ALL_COMPONENTS)";; esac
  done
}

compute_components() {
  if [ -n "$ONLY_LIST" ]; then
    SELECTED_COMPONENTS=$(printf '%s' "$ONLY_LIST" | tr ',' ' ')
    validate_components "$SELECTED_COMPONENTS"
    return
  fi
  SELECTED_COMPONENTS="$ALL_COMPONENTS"
  if [ -n "$WITHOUT_LIST" ]; then
    drop=$(printf '%s' "$WITHOUT_LIST" | tr ',' ' ')
    validate_components "$drop"
    kept=""
    for c in $ALL_COMPONENTS; do
      skip=0
      for d in $drop; do [ "$c" = "$d" ] && skip=1; done
      [ "$skip" = 0 ] && kept="$kept $c"
    done
    SELECTED_COMPONENTS=$(printf '%s' "$kept" | sed 's/^ *//')
  fi
}

# ---------- payload source ----------

TMP_FETCH=""
cleanup() { [ -n "$TMP_FETCH" ] && rm -rf "$TMP_FETCH" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

resolve_payload() {
  src="$1"
  if [ -z "$src" ]; then
    SCRIPT_DIR=$(resolve_script_dir)
    PAYLOAD_DIR="$SCRIPT_DIR/payload"
    [ -d "$PAYLOAD_DIR" ] \
      || die "no payload found. Pass --src <URL|tarball>, set MESH_SRC, or run from a checkout containing payload/."
    return
  fi
  need_cmd tar
  TMP_FETCH=$(mktemp -d "${TMPDIR:-/tmp}/mesh-src.XXXXXX")
  if [ -f "$src" ]; then
    log "Using local payload tarball: $src"
    cp "$src" "$TMP_FETCH/payload.tgz"
  else
    case "$src" in
      *.tgz|*.tar.gz) url="$src";;
      *) url="${src%/}/mesh-install.tgz";;
    esac
    need_cmd curl
    log "Fetching payload: $url"
    curl -fsSL "$url" -o "$TMP_FETCH/payload.tgz" || die "failed to download $url"
  fi
  ( cd "$TMP_FETCH" && tar -xzf payload.tgz ) || die "failed to extract payload"
  if [ -d "$TMP_FETCH/install/payload" ]; then SCRIPT_DIR="$TMP_FETCH/install"
  elif [ -d "$TMP_FETCH/payload" ]; then SCRIPT_DIR="$TMP_FETCH"
  else die "downloaded payload has unexpected layout (no install/payload or payload/)"; fi
  PAYLOAD_DIR="$SCRIPT_DIR/payload"
}

validate_payload() {
  if want_component meshd; then
    [ -f "$PAYLOAD_DIR/meshd/server.ts" ] || die "missing payload: meshd/server.ts"
    [ -f "$PAYLOAD_DIR/meshd/package.json" ] || die "missing payload: meshd/package.json"
  fi
  if want_component bridge; then
    [ -f "$PAYLOAD_DIR/rmux-bridge/src/server.ts" ] || die "missing payload: rmux-bridge/src/server.ts"
    [ -f "$PAYLOAD_DIR/rmux-bridge/package.json" ] || die "missing payload: rmux-bridge/package.json"
    [ -f "$PAYLOAD_DIR/rmux-bridge/public/index.html" ] || die "missing payload: rmux-bridge/public/index.html"
  fi
  if want_component tools; then
    for f in mesh-event mesh-hook mesh-agent-run mesh-codex-notify mesh-self-check; do
      [ -f "$PAYLOAD_DIR/bin/$f" ] || die "missing payload: bin/$f"
    done
  fi
}

install_components() {
  mkdir -p "$MESH_HOME"
  if want_component meshd; then
    rm -rf "$MESH_HOME/meshd"; cp -R "$PAYLOAD_DIR/meshd" "$MESH_HOME/"
  fi
  if want_component bridge; then
    rm -rf "$MESH_HOME/rmux-bridge"; cp -R "$PAYLOAD_DIR/rmux-bridge" "$MESH_HOME/"
  fi
  if want_component tools; then
    rm -rf "$MESH_HOME/bin"; cp -R "$PAYLOAD_DIR/bin" "$MESH_HOME/"
    chmod +x "$MESH_HOME"/bin/* 2>/dev/null || true
    if [ -d "$SCRIPT_DIR/hooks" ]; then rm -rf "$MESH_HOME/hooks"; cp -R "$SCRIPT_DIR/hooks" "$MESH_HOME/"; fi
  fi
}

install_deps() { ( cd "$1" && bun install ); }

# ---------- actions ----------

do_list() {
  log "Prefix: $MESH_HOME"
  [ -d "$MESH_HOME" ] || { log "  (nothing installed)"; return; }
  for item in meshd rmux-bridge bin hooks token; do
    [ -e "$MESH_HOME/$item" ] && log "  present: $item"
  done
  if command -v tmux >/dev/null 2>&1; then
    tmux has-session -t meshd 2>/dev/null && log "  running: meshd session" || true
    tmux has-session -t rmux-bridge 2>/dev/null && log "  running: rmux-bridge session" || true
  fi
}

do_uninstall() {
  removed=""
  if want_component meshd; then
    kill_session meshd && removed="$removed meshd(service)" || true
    [ -e "$MESH_HOME/meshd" ] && { rm -rf "$MESH_HOME/meshd"; removed="$removed meshd"; }
  fi
  if want_component bridge; then
    kill_session rmux-bridge && removed="$removed bridge(service)" || true
    [ -e "$MESH_HOME/rmux-bridge" ] && { rm -rf "$MESH_HOME/rmux-bridge"; removed="$removed bridge"; }
  fi
  if want_component tools; then
    [ -e "$MESH_HOME/bin" ] && { rm -rf "$MESH_HOME/bin"; removed="$removed tools"; }
    [ -e "$MESH_HOME/hooks" ] && { rm -rf "$MESH_HOME/hooks"; removed="$removed hooks"; }
  fi
  if [ "$DO_PURGE" = "1" ]; then
    rm -rf "$MESH_HOME"; removed="$removed prefix($MESH_HOME)"
  fi
  if [ -n "$removed" ]; then log "Removed:$removed"; else log "Nothing to remove under $MESH_HOME"; fi
}

# ---------- arg parsing ----------

TOKEN_FLAG=""; SRC_FLAG=""; ONLY_LIST=""; WITHOUT_LIST=""
DO_UNINSTALL="0"; DO_PURGE="0"; DO_LIST="0"; NO_START="0"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --token) shift; [ "$#" -gt 0 ] || die "--token requires a value"; TOKEN_FLAG="$1";;
    --src) shift; [ "$#" -gt 0 ] || die "--src requires a value"; SRC_FLAG="$1";;
    --only) shift; [ "$#" -gt 0 ] || die "--only requires a value"; ONLY_LIST="$1";;
    --without) shift; [ "$#" -gt 0 ] || die "--without requires a value"; WITHOUT_LIST="$1";;
    --prefix) shift; [ "$#" -gt 0 ] || die "--prefix requires a value"; MESH_HOME="$1";;
    --no-start) NO_START="1";;
    --list) DO_LIST="1";;
    --uninstall) DO_UNINSTALL="1";;
    --purge) DO_PURGE="1";;
    --help|-h) usage; exit 0;;
    *) usage >&2; die "unknown flag: $1";;
  esac
  shift
done

compute_components

# ---------- detect environment ----------

OS_NAME=$(uname -s 2>/dev/null || printf '')
ARCH_NAME=$(uname -m 2>/dev/null || printf '')
case "$OS_NAME" in Darwin|Linux) ;; *) die "unsupported OS: ${OS_NAME:-unknown} (expected Darwin or Linux)";; esac
case "$ARCH_NAME" in arm64|aarch64|x86_64) ;; *) die "unsupported arch: ${ARCH_NAME:-unknown}";; esac

# list / uninstall are pure local operations — handle before any fetch
if [ "$DO_LIST" = "1" ]; then do_list; exit 0; fi
if [ "$DO_UNINSTALL" = "1" ]; then do_uninstall; exit 0; fi

# default multiplexer ("which terminal filesystem to drive")
MUX_DEFAULT="tmux"
if [ "$OS_NAME" = "Darwin" ] && command -v rmux >/dev/null 2>&1; then MUX_DEFAULT="rmux"; fi
log "Detected: $OS_NAME/$ARCH_NAME · mux=$MUX_DEFAULT · components=[$SELECTED_COMPONENTS] · prefix=$MESH_HOME"

# ---------- install ----------

need_cmd cp; need_cmd curl; need_cmd rm; need_cmd uname

SRC="${SRC_FLAG:-${MESH_SRC:-}}"
if [ -z "$SRC" ] && [ "$MESH_SRC_DEFAULT" != "__MESH_SRC__" ]; then SRC="$MESH_SRC_DEFAULT"; fi
resolve_payload "$SRC"
validate_payload

if want_component meshd || want_component bridge; then
  ensure_bun
  [ "$NO_START" = "1" ] || ensure_tmux
fi

TOKEN_VALUE="${TOKEN_FLAG:-${MESHD_TOKEN:-}}"
[ -n "$TOKEN_VALUE" ] || TOKEN_VALUE=$(gen_token)

MESHD_PORT_VALUE="${MESHD_PORT:-$MESHD_DEFAULT_PORT}"
BRIDGE_PORT_VALUE="${PORT:-$BRIDGE_DEFAULT_PORT}"
EFFECTIVE_MESHD_MUX="${MESH_MUX:-}"
EFFECTIVE_BRIDGE_MUX="${MUX:-}"
if [ "$MUX_DEFAULT" = "tmux" ]; then
  [ -n "$EFFECTIVE_MESHD_MUX" ] || EFFECTIVE_MESHD_MUX="tmux"
  [ -n "$EFFECTIVE_BRIDGE_MUX" ] || EFFECTIVE_BRIDGE_MUX="tmux"
fi

install_components
printf '%s\n' "$TOKEN_VALUE" > "$MESH_HOME/token"
chmod 600 "$MESH_HOME/token" 2>/dev/null || true
want_component meshd && install_deps "$MESH_HOME/meshd"
want_component bridge && install_deps "$MESH_HOME/rmux-bridge"

MESHD_STATUS="skipped"; BRIDGE_STATUS="skipped"
if [ "$NO_START" = "1" ]; then
  log "Installed (services not started: --no-start)."
else
  if want_component meshd; then
    meshd_cmd="env PATH=$(shell_quote "$PATH") MESHD_TOKEN=$(shell_quote "$TOKEN_VALUE") MESHD_PORT=$(shell_quote "$MESHD_PORT_VALUE")"
    meshd_cmd=$(append_env "$meshd_cmd" "MESHD_HOST" "${MESHD_HOST:-}")
    meshd_cmd=$(append_env "$meshd_cmd" "MESH_MUX" "$EFFECTIVE_MESHD_MUX")
    meshd_cmd="$meshd_cmd bun run server.ts"
    start_session "meshd" "$MESH_HOME/meshd" "$meshd_cmd"
    MESHD_STATUS="down"; wait_http "http://127.0.0.1:${MESHD_PORT_VALUE}/health" && MESHD_STATUS="up"
  fi
  if want_component bridge; then
    bridge_cmd="env PATH=$(shell_quote "$PATH") PORT=$(shell_quote "$BRIDGE_PORT_VALUE")"
    bridge_cmd=$(append_env "$bridge_cmd" "BRIDGE_HOST" "${BRIDGE_HOST:-}")
    bridge_cmd=$(append_env "$bridge_cmd" "MUX" "$EFFECTIVE_BRIDGE_MUX")
    bridge_cmd="$bridge_cmd bun run src/server.ts"
    start_session "rmux-bridge" "$MESH_HOME/rmux-bridge" "$bridge_cmd"
    BRIDGE_STATUS="down"; wait_http "http://127.0.0.1:${BRIDGE_PORT_VALUE}/" && BRIDGE_STATUS="up"
  fi
fi

TAILSCALE_IP=""
command -v tailscale >/dev/null 2>&1 && TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1)

printf '\n'
want_component meshd  && printf 'meshd: %s\n' "$MESHD_STATUS"
want_component bridge && printf 'rmux-bridge: %s\n' "$BRIDGE_STATUS"
if [ -n "$TAILSCALE_IP" ]; then
  printf 'Tailscale IPv4: %s\n' "$TAILSCALE_IP"
  want_component meshd  && printf 'meshd URL: http://%s:%s\n' "$TAILSCALE_IP" "$MESHD_PORT_VALUE"
  want_component bridge && printf 'bridge URL: http://%s:%s\n' "$TAILSCALE_IP" "$BRIDGE_PORT_VALUE"
else
  printf 'Tailscale IPv4: unavailable (run "tailscale ip -4" once Tailscale is connected)\n'
fi
printf 'MESHD token: %s\n' "$TOKEN_VALUE"
if want_component tools; then
  printf 'Self-check: %s/bin/mesh-self-check\n' "$MESH_HOME"
  printf 'Notify test: %s/bin/mesh-event codex "Needs input" "phone/watch smoke test"\n' "$MESH_HOME"
fi
printf 'Uninstall: sh install.sh --uninstall   (add --purge to remove the token + %s)\n' "$MESH_HOME"

if [ "$NO_START" != "1" ]; then
  want_component meshd  && [ "$MESHD_STATUS" != "up" ] && exit 1
  want_component bridge && [ "$BRIDGE_STATUS" != "up" ] && exit 1
fi
exit 0

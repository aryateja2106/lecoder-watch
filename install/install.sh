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
  --user NAME      (Linux) Provision an isolated agent: create Unix user NAME and
                   run its own meshd on a free port (8901+). Add --uninstall to tear
                   it down (--purge also deletes the user). Sandboxes risky work.
  --src SRC        Payload source: a base URL (fetches SRC/mesh-install.tgz),
                   a direct .tgz/.tar.gz URL, or a local tarball path.
                   Default: baked-in source, else a local ./payload checkout.
  --only LIST      Install only these components (comma list).
  --without LIST   Install everything except these components.
  --prefix DIR     Install location (default: \$MESH_HOME or ~/.mesh).
  --no-start       Install but do not launch services.
  --upgrade        Fetch the latest and reinstall in place, preserving the existing
  --update         token and config (same as re-running install; clearer intent).
  --list           Show what is installed under the prefix, then exit.
  --uninstall      Stop services and remove the selected components.
  --purge          With --uninstall, also remove the token and the prefix dir.
  --help, -h       Show this help.

Components: $ALL_COMPONENTS
  meshd  = stats/sessions/events daemon (:$MESHD_DEFAULT_PORT)
  bridge = rmux-bridge live terminal stream (:$BRIDGE_DEFAULT_PORT)
  tools  = mesh CLI + mesh-event/mesh-hook/mesh-agent-run/mesh-self-check + hooks

After install:
  ~/.mesh/bin/mesh setup       first run: permissions + pair your phone
  ~/.mesh/bin/mesh --help      every command (man: mesh man)
PATH is wired into ~/.zshrc or ~/.bashrc automatically; the manual line is
  eval "\$(~/.mesh/bin/mesh shellenv)"
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
  # bun's installer is a bash script (uses pipefail/arrays) — sh/dash can't run it.
  if command -v bash >/dev/null 2>&1; then bash "$bun_installer"
  else die "installing bun requires bash; install bash or bun first"; fi
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

# ---------- reboot-persistent services (launchd / systemd-user / tmux fallback) ----------
#
# meshd + rmux-bridge are long-lived; tmux sessions die on reboot, which is what
# made the mesh "go dark". We register a real supervisor so services come back
# automatically: launchd on macOS, systemd --user (with linger) on Linux/WSL,
# falling back to a detached tmux session only where neither exists.

# Label/unit base name; override MESH_LABEL_PREFIX to test without touching prod.
LABEL_PREFIX="${MESH_LABEL_PREFIX:-ai.lesearch}"

# Choose the supervisor. Override with MESH_SERVICE=launchd|systemd|tmux.
detect_service_mgr() {
  if [ -n "${MESH_SERVICE:-}" ]; then printf '%s' "$MESH_SERVICE"; return; fi
  if [ "$OS_NAME" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then printf 'launchd'; return; fi
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then printf 'systemd'; return; fi
  printf 'tmux'
}

mux_session()   { printf '%s-%s' "$LABEL_PREFIX" "$1"; }   # tmux session name, label-isolated
launchd_label() { printf '%s.%s' "$LABEL_PREFIX" "$1"; }
launchd_plist() { printf '%s/Library/LaunchAgents/%s.%s.plist' "$HOME" "$LABEL_PREFIX" "$1"; }
systemd_unit()  { printf '%s/.config/systemd/user/%s-%s.service' "$HOME" "$LABEL_PREFIX" "$1"; }
systemd_name()  { printf '%s-%s.service' "$LABEL_PREFIX" "$1"; }

# Minimal XML escaping for plist string values (token/path are normally clean).
xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# emit_launchd_plist LABEL WORKDIR BUN ENTRY LOGPATH  (env "KEY=VALUE" lines on stdin)
emit_launchd_plist() {
  el_label="$1"; el_workdir="$2"; el_bun="$3"; el_entry="$4"; el_log="$5"
  el_env=$(while IFS= read -r kv; do
    [ -n "$kv" ] || continue
    printf '        <key>%s</key>\n        <string>%s</string>\n' \
      "$(xml_escape "${kv%%=*}")" "$(xml_escape "${kv#*=}")"
  done)
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$el_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$el_bun</string>
        <string>run</string>
        <string>$el_entry</string>
    </array>
    <key>WorkingDirectory</key><string>$el_workdir</string>
    <key>EnvironmentVariables</key>
    <dict>
$el_env
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardOutPath</key><string>$el_log</string>
    <key>StandardErrorPath</key><string>$el_log</string>
</dict>
</plist>
EOF
}

# emit_systemd_unit DESC WORKDIR BUN ENTRY  (env "KEY=VALUE" lines on stdin)
emit_systemd_unit() {
  su_desc="$1"; su_workdir="$2"; su_bun="$3"; su_entry="$4"
  su_env=$(while IFS= read -r kv; do [ -n "$kv" ] || continue; printf 'Environment="%s"\n' "$kv"; done)
  cat <<EOF
[Unit]
Description=$su_desc
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$su_workdir
$su_env
ExecStart=$su_bun run $su_entry
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF
}

# systemctl --user needs a runtime dir; set it for headless/ssh sessions.
systemd_user_env() { [ -n "${XDG_RUNTIME_DIR:-}" ] || { XDG_RUNTIME_DIR="/run/user/$(id -u)"; export XDG_RUNTIME_DIR; }; }

# service_start NAME WORKDIR ENTRY HEALTH_URL  (env "KEY=VALUE" lines on stdin)
# Installs + (re)starts under the detected supervisor. Echoes nothing; sets no globals.
service_start() {
  ss_name="$1"; ss_workdir="$2"; ss_entry="$3"; ss_env=$(cat)
  # Drop our own prior (prefixed) tmux session so test installs never touch prod.
  kill_session "$(mux_session "$ss_name")" >/dev/null 2>&1 || true
  # ponytail: only a real default-prefix install migrates a legacy deploy.sh "meshd"
  # tmux session (plain name). A custom MESH_LABEL_PREFIX stays fully isolated.
  [ "$LABEL_PREFIX" = "ai.lesearch" ] && kill_session "$ss_name" >/dev/null 2>&1 || true
  case "$SERVICE_MGR" in
    launchd)
      ss_plist=$(launchd_plist "$ss_name"); ss_label=$(launchd_label "$ss_name")
      mkdir -p "$(dirname "$ss_plist")"
      printf '%s\n' "$ss_env" | emit_launchd_plist "$ss_label" "$ss_workdir" "$BUN_BIN" "$ss_entry" "${TMPDIR:-/tmp}/${ss_name}.log" > "$ss_plist"
      chmod 600 "$ss_plist"   # the plist embeds MESHD_TOKEN; keep it off other users
      launchctl bootout "gui/$(id -u)/$ss_label" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$ss_plist" 2>/dev/null || launchctl load "$ss_plist" 2>/dev/null || \
        warn "launchctl could not load $ss_label; check $ss_plist"
      ;;
    systemd)
      systemd_user_env
      ss_unit=$(systemd_unit "$ss_name")
      mkdir -p "$(dirname "$ss_unit")"
      printf '%s\n' "$ss_env" | emit_systemd_unit "mesh $ss_name" "$ss_workdir" "$BUN_BIN" "$ss_entry" > "$ss_unit"
      chmod 600 "$ss_unit"    # the unit embeds MESHD_TOKEN; keep it off other users
      loginctl enable-linger "$(id -un)" 2>/dev/null || sudo loginctl enable-linger "$(id -un)" 2>/dev/null || \
        warn "could not enable linger; services may stop when you log out (run: sudo loginctl enable-linger $(id -un))"
      systemctl --user daemon-reload 2>/dev/null || true
      systemctl --user enable --now "$(systemd_name "$ss_name")" 2>/dev/null || \
        warn "systemctl --user could not start $(systemd_name "$ss_name"); check: systemctl --user status $(systemd_name "$ss_name")"
      # `enable --now` is a no-op on an already-active unit, so an upgrade left the OLD
      # daemon running out of memory with the new files on disk and no error anywhere —
      # that is how the fleet stayed on 0.2.x. Restart explicitly to load the new code.
      systemctl --user restart "$(systemd_name "$ss_name")" 2>/dev/null || \
        warn "systemctl --user could not restart $(systemd_name "$ss_name"); it may still be running the previous build"
      ;;
    *)  # tmux fallback (does NOT survive reboot)
      # The environment goes into a 0600 file and is sourced, never passed as argv:
      # `env MESHD_TOKEN=<secret> bun run server.ts` in a command line is readable by
      # every other local user through `ps`, and that token is a shell on this machine.
      # The launchd and systemd paths above already keep their env out of `ps`; this
      # fallback was the one that did not. server.ts is unchanged — still process.env.
      ss_envfile="$MESH_HOME/$ss_name.env"
      mkdir -p "$MESH_HOME"
      ( umask 077
        printf '%s\n' "$ss_env" | while IFS= read -r kv; do
          [ -n "$kv" ] || continue
          printf '%s=%s\n' "${kv%%=*}" "$(shell_quote "${kv#*=}")"
        done > "$ss_envfile" )
      chmod 600 "$ss_envfile" 2>/dev/null || true
      # sh -c explicitly: tmux runs commands through default-shell, which may be fish or
      # csh, and neither speaks `set -a`. Paths arrive as $0/$1/$2 so spaces survive, and
      # `exec` leaves a process whose argv holds no secret.
      start_session "$(mux_session "$ss_name")" "$ss_workdir" \
        "sh -c 'set -a; . \"\$0\"; set +a; exec \"\$1\" run \"\$2\"' $(shell_quote "$ss_envfile") $(shell_quote "$BUN_BIN") $(shell_quote "$ss_entry")"
      ;;
  esac
}

# service_stop NAME — stop + remove the supervisor entry, whatever manages it.
service_stop() {
  st_name="$1"; st_removed=1
  if [ "$OS_NAME" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
    st_plist=$(launchd_plist "$st_name"); st_label=$(launchd_label "$st_name")
    if [ -f "$st_plist" ] || launchctl print "gui/$(id -u)/$st_label" >/dev/null 2>&1; then
      launchctl bootout "gui/$(id -u)/$st_label" 2>/dev/null || launchctl unload "$st_plist" 2>/dev/null || true
      rm -f "$st_plist"; st_removed=0
    fi
  fi
  if command -v systemctl >/dev/null 2>&1; then
    st_unit=$(systemd_unit "$st_name")
    if [ -f "$st_unit" ]; then
      systemd_user_env
      systemctl --user disable --now "$(systemd_name "$st_name")" 2>/dev/null || true
      rm -f "$st_unit"; systemctl --user daemon-reload 2>/dev/null || true; st_removed=0
    fi
  fi
  kill_session "$(mux_session "$st_name")" >/dev/null 2>&1 && st_removed=0 || true
  rm -f "$MESH_HOME/$st_name.env"   # holds MESHD_TOKEN; nothing should outlive the service
  return $st_removed
}

# ---------- isolated agent users (--user) ----------
#
# Sandbox an agent on a Linux box: create a separate Unix user that runs its OWN
# meshd on its own port. Standard Unix permissions then keep that agent out of
# your real user's files. Linux-only (the sandbox target is a server/VPS).

port_in_use() {
  if command -v ss >/dev/null 2>&1; then ss -ltn 2>/dev/null | grep -q "[:.]$1 " && return 0; fi
  if command -v lsof >/dev/null 2>&1; then lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1 && return 0; fi
  return 1
}

find_free_port() {  # first free port in [$1,$2]
  ffp=$1
  while [ "$ffp" -le "$2" ]; do port_in_use "$ffp" || { printf '%s' "$ffp"; return 0; }; ffp=$((ffp + 1)); done
  return 1
}

# Resolve the installer source the per-user install should re-fetch from.
provision_source() {
  ps_src="${SRC_FLAG:-${MESH_SRC:-}}"
  { [ -z "$ps_src" ] && [ "$MESH_SRC_DEFAULT" != "__MESH_SRC__" ]; } && ps_src="$MESH_SRC_DEFAULT"
  [ -n "$ps_src" ] || die "--user needs a release installer (baked source) or --src URL"
  case "$ps_src" in *install.sh) printf '%s' "$ps_src";; *) printf '%s/install.sh' "${ps_src%/}";; esac
}

provision_privilege() {  # echoes "" if root, "sudo" if usable, else dies
  if [ "$(id -u)" = 0 ]; then return 0; fi
  command -v sudo >/dev/null 2>&1 || die "--user needs root or sudo"
  printf 'sudo'
}

provision_user() {
  pu_name="$1"
  [ "$OS_NAME" = "Linux" ] || die "--user is Linux-only (sandbox an agent on a Linux/WSL box); create the user manually on macOS"
  case "$pu_name" in ''|*[!a-z0-9_-]*) die "--user name must be lowercase letters, digits, '_' or '-'";; esac
  SUDO=$(provision_privilege)
  pu_url=$(provision_source)
  if ! id "$pu_name" >/dev/null 2>&1; then
    log "Creating isolated user '$pu_name'"
    $SUDO useradd -m -s /bin/bash "$pu_name" || die "useradd failed for $pu_name"
  fi
  $SUDO loginctl enable-linger "$pu_name" 2>/dev/null || warn "could not enable linger for $pu_name (services may stop on logout)"
  pu_port="${MESHD_PORT:-$(find_free_port 8901 8999)}"
  [ -n "$pu_port" ] || die "no free port in 8901-8999 for the sandbox"
  pu_token="${TOKEN_FLAG:-${MESHD_TOKEN:-}}"; [ -n "$pu_token" ] || pu_token=$(gen_token)
  log "Installing isolated meshd as '$pu_name' on port $pu_port"
  $SUDO -u "$pu_name" --login env MESHD_PORT="$pu_port" MESH_SRC="${SRC_FLAG:-${MESH_SRC:-$MESH_SRC_DEFAULT}}" \
    sh -c "curl -fsSL '$pu_url' | MESHD_PORT='$pu_port' sh -s -- --only meshd --token '$pu_token'" \
    || die "per-user install failed for $pu_name"
  pu_ip=""; command -v tailscale >/dev/null 2>&1 && pu_ip=$(tailscale ip -4 2>/dev/null | head -1)
  printf '\nIsolated agent box ready:\n'
  printf '  user:  %s\n  port:  %s\n  token: %s\n' "$pu_name" "$pu_port" "$pu_token"
  [ -n "$pu_ip" ] && printf '  add in app: host=<name> ip=%s port=%s token=<above>\n' "$pu_ip" "$pu_port"
  printf '  remove: sh install.sh --user %s --uninstall --purge\n' "$pu_name"
}

deprovision_user() {
  du_name="$1"
  [ "$OS_NAME" = "Linux" ] || die "--user is Linux-only"
  case "$du_name" in ''|*[!a-z0-9_-]*) die "invalid --user name";; esac
  SUDO=$(provision_privilege)
  if id "$du_name" >/dev/null 2>&1; then
    du_url=$(provision_source)
    $SUDO -u "$du_name" --login sh -c "curl -fsSL '$du_url' | sh -s -- --only meshd --uninstall --purge" 2>/dev/null || true
    if [ "$DO_PURGE" = "1" ]; then
      # Stop the user's systemd manager + any stragglers, or userdel refuses.
      $SUDO loginctl disable-linger "$du_name" 2>/dev/null || true
      $SUDO loginctl terminate-user "$du_name" 2>/dev/null || true
      $SUDO pkill -KILL -u "$du_name" 2>/dev/null || true
      sleep 1
      $SUDO userdel -rf "$du_name" 2>/dev/null && log "Removed user $du_name" || warn "userdel failed for $du_name (try: sudo userdel -rf $du_name)"
    else
      log "Stopped $du_name's mesh (user kept; add --purge to delete the user)"
    fi
  else
    log "No such user: $du_name"
  fi
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
    # Refuse a plaintext source: whoever controls any hop then runs code as you (and,
    # on --user, as another user via sudo). HTTPS or a local file only.
    case "$url" in http://*) die "refusing plaintext payload source (use https): $url";; esac
    need_cmd curl
    log "Fetching payload: $url"
    # --progress-bar, not -s: with the script itself piped through `curl | sh`, this
    # download is the one silent stretch, and people reasonably assume a hung install.
    curl -fL --progress-bar "$url" -o "$TMP_FETCH/payload.tgz" || die "failed to download $url"
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
    for f in mesh mesh-event mesh-hook mesh-agent-run mesh-codex-notify mesh-self-check; do
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
    if [ -d "$PAYLOAD_DIR/share" ]; then rm -rf "$MESH_HOME/share"; cp -R "$PAYLOAD_DIR/share" "$MESH_HOME/"; fi
  fi
  if want_component meshd && [ "$OS_NAME" = "Darwin" ] && [ -f "$PAYLOAD_DIR/hooks/cmux-bridge.zsh" ]; then
    mkdir -p "$MESH_HOME/hooks"
    cp "$PAYLOAD_DIR/hooks/cmux-bridge.zsh" "$MESH_HOME/hooks/cmux-bridge.zsh"
    _hook='[ -f "$HOME/.mesh/hooks/cmux-bridge.zsh" ] && source "$HOME/.mesh/hooks/cmux-bridge.zsh"'
    if [ -f "$HOME/.zshrc" ] && ! grep -Fq 'cmux-bridge.zsh' "$HOME/.zshrc" 2>/dev/null; then
      printf '\n# MeshWatch cmux bridge (auto-start in interactive shells)\n%s\n' "$_hook" >> "$HOME/.zshrc"
      log "Added cmux-bridge hook to ~/.zshrc"
    fi
  fi
}

# Wire agent alerts into Claude Code. Everything the watch does about agents -- the
# notification with its reply buttons, the live card, the face complication -- hangs off
# one event an agent posts when it stops and waits for a human. Without this the tools
# are installed and nothing ever fires them, which reads as "the app does not do that".
# Merges into an existing settings.json (other tools own hooks there too) and is a
# no-op when already present.
install_agent_hooks() {
  want_component tools || return 0
  command -v bun >/dev/null 2>&1 || return 0
  [ -x "$MESH_HOME/bin/mesh" ] || return 0
  if "$MESH_HOME/bin/mesh" hooks install >/dev/null 2>&1; then
    log "Wired agent alerts into Claude Code (mesh hooks status to check)"
  else
    log "Could not wire Claude Code hooks — run: $MESH_HOME/bin/mesh hooks install"
  fi
}

install_deps() { ( cd "$1" && bun install ); }

# ---------- PATH onboarding ----------
#
# An install nobody can invoke is not an install: every previous run ended by printing
# "~/.mesh/bin/mesh pair" and left the user to work out the PATH themselves, so `mesh`
# did not exist in their next terminal. Add ONE homebrew-shaped eval line to the right
# rc file, exactly once. A child process cannot change the parent shell, so the last
# thing this installer prints is how to pick it up in the shell they are standing in.
PATH_RC=""; PATH_LINE=""; PATH_STATE="ok"   # ok | added | present | manual

setup_path() {
  want_component tools || return 0
  case ":${PATH}:" in *":$MESH_HOME/bin:"*) return 0;; esac   # already usable
  PATH_LINE="eval \"\$($MESH_HOME/bin/mesh shellenv)\""
  case "${SHELL##*/}" in
    zsh)  PATH_RC="$HOME/.zshrc";;
    bash) PATH_RC="$HOME/.bashrc";;
    *)    PATH_STATE="manual"; return 0;;      # fish/csh/unknown: tell, don't guess
  esac
  if [ -f "$PATH_RC" ] && grep -Fq 'mesh shellenv' "$PATH_RC" 2>/dev/null; then
    PATH_STATE="present"; return 0
  fi
  if printf '\n# MeshWatch CLI on PATH\n%s\n' "$PATH_LINE" >> "$PATH_RC" 2>/dev/null; then
    PATH_STATE="added"
  else
    PATH_STATE="manual"
  fi
}

report_path() {
  case "$PATH_STATE" in
    added)
      printf '\nAdded to %s:\n    %s\n' "$PATH_RC" "$PATH_LINE"
      printf 'Run this now so "mesh" works in THIS terminal (new terminals get it automatically):\n    source %s\n' "$PATH_RC";;
    present)
      printf '\n"mesh" is already wired into %s. Pick it up in THIS terminal with:\n    source %s\n' "$PATH_RC" "$PATH_RC";;
    manual)
      printf '\nPut "mesh" on your PATH by adding this line to your shell startup file:\n    %s\n' "$PATH_LINE";;
    *)  printf '\nNext: mesh setup\n';;
  esac
}

# ---------- actions ----------

service_state() {  # prints launchd|systemd|tmux supervisor state for a service name
  if [ "$OS_NAME" = "Darwin" ] && [ -f "$(launchd_plist "$1")" ]; then printf 'launchd'; return; fi
  [ -f "$(systemd_unit "$1")" ] && { printf 'systemd'; return; }
  command -v tmux >/dev/null 2>&1 && tmux has-session -t "$(mux_session "$1")" 2>/dev/null && { printf 'tmux'; return; }
  printf 'none'
}

do_list() {
  log "Prefix: $MESH_HOME"
  [ -d "$MESH_HOME" ] || { log "  (nothing installed)"; return; }
  for item in meshd rmux-bridge bin share hooks token; do
    [ -e "$MESH_HOME/$item" ] && log "  present: $item"
  done
  for svc in meshd cmux-bridge rmux-bridge; do
    st=$(service_state "$svc")
    [ "$st" = "none" ] || log "  service: $svc ($st)"
  done
}

do_uninstall() {
  removed=""
  if want_component meshd; then
    service_stop cmux-bridge && removed="$removed cmux-bridge(service)" || true
    service_stop meshd && removed="$removed meshd(service)" || true
    [ -e "$MESH_HOME/meshd" ] && { rm -rf "$MESH_HOME/meshd"; removed="$removed meshd"; }
  fi
  if want_component bridge; then
    service_stop rmux-bridge && removed="$removed bridge(service)" || true
    [ -e "$MESH_HOME/rmux-bridge" ] && { rm -rf "$MESH_HOME/rmux-bridge"; removed="$removed bridge"; }
  fi
  if want_component tools; then
    [ -e "$MESH_HOME/bin" ] && { rm -rf "$MESH_HOME/bin"; removed="$removed tools"; }
    [ -e "$MESH_HOME/hooks" ] && { rm -rf "$MESH_HOME/hooks"; removed="$removed hooks"; }
    [ -e "$MESH_HOME/share" ] && { rm -rf "$MESH_HOME/share"; removed="$removed man"; }
  fi
  if [ "$DO_PURGE" = "1" ]; then
    rm -rf "$MESH_HOME"; removed="$removed prefix($MESH_HOME)"
  fi
  if [ -n "$removed" ]; then log "Removed:$removed"; else log "Nothing to remove under $MESH_HOME"; fi
}

# ---------- arg parsing ----------

TOKEN_FLAG=""; SRC_FLAG=""; ONLY_LIST=""; WITHOUT_LIST=""; USER_FLAG=""
DO_UNINSTALL="0"; DO_PURGE="0"; DO_LIST="0"; NO_START="0"; DO_UPGRADE="0"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --token) shift; [ "$#" -gt 0 ] || die "--token requires a value"; TOKEN_FLAG="$1";;
    --user) shift; [ "$#" -gt 0 ] || die "--user requires a name"; USER_FLAG="$1";;
    --src) shift; [ "$#" -gt 0 ] || die "--src requires a value"; SRC_FLAG="$1";;
    --only) shift; [ "$#" -gt 0 ] || die "--only requires a value"; ONLY_LIST="$1";;
    --without) shift; [ "$#" -gt 0 ] || die "--without requires a value"; WITHOUT_LIST="$1";;
    --prefix) shift; [ "$#" -gt 0 ] || die "--prefix requires a value"; MESH_HOME="$1";;
    --no-start) NO_START="1";;
    --list) DO_LIST="1";;
    --upgrade|--update) DO_UPGRADE="1";;
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

SERVICE_MGR=$(detect_service_mgr)

# --user: provision (or with --uninstall, tear down) an isolated agent user that
# runs its own meshd on its own port. Meta-operation — handle before anything else.
if [ -n "$USER_FLAG" ]; then
  if [ "$DO_UNINSTALL" = "1" ]; then deprovision_user "$USER_FLAG"; else provision_user "$USER_FLAG"; fi
  exit $?
fi

# list / uninstall are pure local operations — handle before any fetch
if [ "$DO_LIST" = "1" ]; then do_list; exit 0; fi
if [ "$DO_UNINSTALL" = "1" ]; then do_uninstall; exit 0; fi

# default multiplexer ("which terminal filesystem to drive")
MUX_DEFAULT="tmux"
if [ "$OS_NAME" = "Darwin" ] && command -v rmux >/dev/null 2>&1; then MUX_DEFAULT="rmux"; fi
log "Detected: $OS_NAME/$ARCH_NAME · mux=$MUX_DEFAULT · service=$SERVICE_MGR · components=[$SELECTED_COMPONENTS] · prefix=$MESH_HOME"
if [ "$DO_UPGRADE" = "1" ]; then
  [ -d "$MESH_HOME/meshd" ] || warn "no existing install under $MESH_HOME — doing a fresh install"
  log "Upgrade: fetching latest, reinstalling in place (token + config preserved)"
fi

# ---------- install ----------

need_cmd cp; need_cmd curl; need_cmd rm; need_cmd uname

SRC="${SRC_FLAG:-${MESH_SRC:-}}"
if [ -z "$SRC" ] && [ "$MESH_SRC_DEFAULT" != "__MESH_SRC__" ]; then SRC="$MESH_SRC_DEFAULT"; fi
resolve_payload "$SRC"
validate_payload

if want_component meshd || want_component bridge; then
  ensure_bun
  BUN_BIN=$(command -v bun)
  [ "$NO_START" = "1" ] || ensure_tmux
fi

TOKEN_VALUE="${TOKEN_FLAG:-${MESHD_TOKEN:-}}"
# Preserve an existing token on re-install/upgrade so saved app/CLI host configs keep working.
if [ -z "$TOKEN_VALUE" ] && [ -f "$MESH_HOME/token" ]; then TOKEN_VALUE=$(tr -d '\n' < "$MESH_HOME/token" 2>/dev/null); fi
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
install_agent_hooks

MESHD_STATUS="skipped"; BRIDGE_STATUS="skipped"
if [ "$NO_START" = "1" ]; then
  log "Installed (services not started: --no-start)."
else
  if want_component meshd; then
    {
      printf 'PATH=%s\n' "$PATH"
      printf 'HOME=%s\n' "$HOME"
      printf 'USER=%s\n' "$(id -un)"
      printf 'MESHD_TOKEN=%s\n' "$TOKEN_VALUE"
      printf 'MESHD_PORT=%s\n' "$MESHD_PORT_VALUE"
      [ -n "${MESHD_HOST:-}" ] && printf 'MESHD_HOST=%s\n' "$MESHD_HOST"
      [ -n "$EFFECTIVE_MESHD_MUX" ] && printf 'MESH_MUX=%s\n' "$EFFECTIVE_MESHD_MUX"
      [ -n "${CMUX_PORT:-}" ] && printf 'CMUX_PORT=%s\n' "$CMUX_PORT"
    } | service_start meshd "$MESH_HOME/meshd" server.ts
    MESHD_STATUS="down"; wait_http "http://127.0.0.1:${MESHD_PORT_VALUE}/health" && MESHD_STATUS="up"
  fi
  if want_component bridge; then
    {
      printf 'PATH=%s\n' "$PATH"
      printf 'PORT=%s\n' "$BRIDGE_PORT_VALUE"
      [ -n "${BRIDGE_HOST:-}" ] && printf 'BRIDGE_HOST=%s\n' "$BRIDGE_HOST"
      [ -n "$EFFECTIVE_BRIDGE_MUX" ] && printf 'MUX=%s\n' "$EFFECTIVE_BRIDGE_MUX"
    } | service_start rmux-bridge "$MESH_HOME/rmux-bridge" src/server.ts
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
# Never print the token: terminals get screenshotted, scrolled back, and pasted
# into AI sessions — which is exactly how two of these leaked. Pairing hands it
# to the phone; nothing else ever needs to see it.
printf 'MESHD token: minted at ~/.mesh/token (never printed — "mesh pair" hands it to your phone)\n'
# Watch pointer/keyboard control on Linux rides on xdotool + xclip (X11/Xvfb).
# Non-fatal: /input reports exactly what is missing until they are installed.
if [ "$OS_NAME" != "Darwin" ] && ! command -v xdotool >/dev/null 2>&1; then
  printf 'Watch input control (optional): %s\n' "$(linux_tmux_hint | sed 's/tmux/xdotool xclip/')"
fi
if want_component tools; then
  printf 'Self-check: %s/bin/mesh-self-check\n' "$MESH_HOME"
  printf 'Notify test: %s/bin/mesh-event codex "Needs input" "phone/watch smoke test"\n' "$MESH_HOME"
  printf 'Agent alerts: %s/bin/mesh hooks status\n' "$MESH_HOME"
  printf '\nFirst time? One command walks you through the rest (permissions + pairing):\n  %s/bin/mesh setup\n' "$MESH_HOME"
fi
if [ "$OS_NAME" = "Darwin" ] && command -v cmux >/dev/null 2>&1 && want_component meshd; then
  printf 'cmux-bridge: source ~/.mesh/hooks/cmux-bridge.zsh (auto via ~/.zshrc in new terminals)\n'
fi
printf 'Uninstall: sh install.sh --uninstall   (add --purge to remove the token + %s)\n' "$MESH_HOME"

# Last, because it is the one instruction the user has to act on themselves.
setup_path
report_path
printf '\nThen let the wizard finish the job (permissions, QR pairing, fleet check):\n    mesh setup\n'

if [ "$NO_START" != "1" ]; then
  want_component meshd  && [ "$MESHD_STATUS" != "up" ] && exit 1
  want_component bridge && [ "$BRIDGE_STATUS" != "up" ] && exit 1
fi
exit 0

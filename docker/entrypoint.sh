#!/bin/sh
# meshd container entrypoint — persist ~/.mesh state on a volume and mint a bearer
# token on first boot when MESHD_TOKEN is not provided.
set -eu

MESH_HOME="${MESH_HOME:-/data/.mesh}"
export MESH_HOME
export HOME="${HOME:-/data}"

mkdir -p "$MESH_HOME"
chmod 700 "$MESH_HOME" 2>/dev/null || true

if [ -z "${MESHD_TOKEN:-}" ]; then
  if [ -f "$MESH_HOME/token" ]; then
    MESHD_TOKEN="$(tr -d '\n' < "$MESH_HOME/token")"
    export MESHD_TOKEN
  else
    if command -v openssl >/dev/null 2>&1; then
      MESHD_TOKEN="$(openssl rand -hex 16)"
    else
      MESHD_TOKEN="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    fi
    printf '%s\n' "$MESHD_TOKEN" > "$MESH_HOME/token"
    chmod 600 "$MESH_HOME/token" 2>/dev/null || true
    export MESHD_TOKEN
  fi
else
  printf '%s\n' "$MESHD_TOKEN" > "$MESH_HOME/token"
  chmod 600 "$MESH_HOME/token" 2>/dev/null || true
fi

exec "$@"

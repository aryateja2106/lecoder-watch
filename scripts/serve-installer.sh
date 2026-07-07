#!/bin/sh
# Serve the mesh installer over the tailnet so any machine installs with ONE curl.
# Repackages from THIS checkout every run (always latest) and bakes the tailscale
# URL into install.sh so `curl .../install.sh | sh` needs no extra flags.
#
#   sh scripts/serve-installer.sh [PORT]        # default port 8890
#
# On a new tailnet machine:
#   curl -fsSL http://<mac-tailscale-ip>:PORT/install.sh | sh -s -- --token testtoken
# Later:  ... | sh -s -- --upgrade      Remove:  ... | sh -s -- --uninstall --purge
set -eu

PORT="${1:-8890}"
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)

command -v tailscale >/dev/null 2>&1 || { echo "error: tailscale not found" >&2; exit 1; }
IP=$(tailscale ip -4 2>/dev/null | head -1)
[ -n "$IP" ] || { echo "error: no tailscale IPv4 (is tailscale up?)" >&2; exit 1; }

DIST="${MESH_DIST:-$ROOT/install/dist}"
mkdir -p "$DIST"
URL="http://$IP:$PORT"
sh "$ROOT/scripts/package-mesh-install.sh" "$DIST/mesh-install.tgz" "$URL" >/dev/null
echo "Serving latest mesh installer at $URL  (from $ROOT)"
echo
echo "Install on any tailnet machine:"
echo "  curl -fsSL $URL/install.sh | sh -s -- --token testtoken"
echo "Or over SSH in one shot:"
echo "  ssh <user>@<host> 'curl -fsSL $URL/install.sh | sh -s -- --token testtoken'"
echo "Upgrade:   curl -fsSL $URL/install.sh | sh -s -- --upgrade"
echo "Uninstall: curl -fsSL $URL/install.sh | sh -s -- --uninstall --purge"
echo
echo "(Ctrl-C to stop)"
cd "$DIST"
if command -v python3 >/dev/null 2>&1; then exec python3 -m http.server "$PORT" --bind "$IP"
elif command -v bun >/dev/null 2>&1; then exec bun -e "Bun.serve({hostname:process.env.IP,port:Number(process.env.PORT),fetch(r){const p=new URL(r.url).pathname.slice(1)||'install.sh';const f=Bun.file(p);return new Response(f);}})"
else echo "error: need python3 or bun to serve" >&2; exit 1; fi

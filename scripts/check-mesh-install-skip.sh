#!/bin/sh
# Re-running install.sh against a tree that already has this payload's VERSION must
# not recopy files. The failure mode is a second curl|sh on a working machine that
# restarts services, rewrites the token file, and looks like "the install hung".
# --upgrade is the explicit escape hatch and must still replace the tree.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$ROOT/install/install.sh"
PAYLOAD="$ROOT/install/payload/meshd/server.ts"
[ -f "$INSTALL" ] && [ -f "$PAYLOAD" ] || { echo "FAIL: missing installer or payload"; exit 1; }

VER=$(sed -n 's/^[[:space:]]*const VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$PAYLOAD" | head -1)
[ -n "$VER" ] || { echo "FAIL: no VERSION in payload meshd/server.ts"; exit 1; }

TH=$(mktemp -d)
trap 'rm -rf "$TH"' EXIT
PREFIX="$TH/mesh"
mkdir -p "$PREFIX/meshd" "$PREFIX/bin" "$PREFIX/rmux-bridge"
printf 'const VERSION = "%s";\n' "$VER" > "$PREFIX/meshd/server.ts"
printf 'sentinel\n' > "$PREFIX/meshd/SENTINEL"
printf '#!/bin/sh\necho mesh\n' > "$PREFIX/bin/mesh"
chmod +x "$PREFIX/bin/mesh"
echo 'existing-token' > "$PREFIX/token"

run_install() {
  HOME="$TH/home" MESH_HOME="$PREFIX" PATH="/usr/bin:/bin:/usr/sbin:/sbin${PATH+:$PATH}" \
    sh "$INSTALL" --prefix "$PREFIX" --no-start "$@" >"$TH/log" 2>&1
}

run_install || { cat "$TH/log"; echo "FAIL: matching-version install exited nonzero"; exit 1; }
grep -q "Already installed meshd $VER" "$TH/log" \
  || { cat "$TH/log"; echo "FAIL: skip log line missing"; exit 1; }
[ -f "$PREFIX/meshd/SENTINEL" ] || { echo "FAIL: skip recopied meshd (sentinel gone)"; exit 1; }
[ "$(cat "$PREFIX/token")" = "existing-token" ] || { echo "FAIL: skip rewrote the token"; exit 1; }

run_install --upgrade || { cat "$TH/log"; echo "FAIL: --upgrade exited nonzero"; exit 1; }
grep -q "Already installed" "$TH/log" && { cat "$TH/log"; echo "FAIL: --upgrade still skipped"; exit 1; }
[ ! -f "$PREFIX/meshd/SENTINEL" ] || { echo "FAIL: --upgrade left the sentinel in place"; exit 1; }

echo "check-mesh-install-skip: OK (matching $VER is a no-op; --upgrade recopies)"

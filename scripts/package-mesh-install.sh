#!/bin/sh
# Package the mesh installer for hosting.
#   sh scripts/package-mesh-install.sh [OUT_TGZ] [SRC_URL]
# Produces OUT_TGZ (the payload tarball). If SRC_URL is given, also writes a
# standalone install.sh next to it with the source URL baked in, so a bare
#   curl -fsSL SRC_URL/install.sh | sh
# fetches SRC_URL/mesh-install.tgz with no extra flags.

set -eu

OUT="${1:-/tmp/mesh-install.tgz}"
SRC_URL="${2:-}"
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)

python3 - "$ROOT" "$OUT" <<'PY'
import pathlib, sys, tarfile
root = pathlib.Path(sys.argv[1]); out = pathlib.Path(sys.argv[2])
keep = ["install/README.md", "install/install.sh", "install/hooks", "install/payload"]
out.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(out, "w:gz") as tar:
    for rel in keep:
        p = root / rel
        if p.exists():
            tar.add(p, arcname=rel)
print(out)
PY

if [ -n "$SRC_URL" ]; then
  STAMPED=$(dirname "$OUT")/install.sh
  sed "s#__MESH_SRC__#${SRC_URL}#" "$ROOT/install/install.sh" > "$STAMPED"
  chmod +x "$STAMPED"
  printf '%s\n' "$STAMPED"
  printf 'Host both files at %s and users run:\n' "$SRC_URL"
  printf '  curl -fsSL %s/install.sh | sh\n' "$SRC_URL"
fi

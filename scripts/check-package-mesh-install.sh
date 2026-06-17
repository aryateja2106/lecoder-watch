#!/bin/sh

set -eu

OUT="${TMPDIR:-/tmp}/mesh-install-check.tgz"
rm -f "$OUT"
sh scripts/package-mesh-install.sh "$OUT" >/dev/null

python3 - "$OUT" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as tar:
    names = set(tar.getnames())

required = {
    "install/install.sh",
    "install/payload/meshd/server.ts",
    "install/payload/rmux-bridge/src/server.ts",
    "install/payload/bin/mesh-event",
    "install/hooks/claude-settings.meshwatch.example.json",
}
missing = required - names
assert not missing, missing
assert not any(name.startswith("install/.omx/") for name in names)
PY

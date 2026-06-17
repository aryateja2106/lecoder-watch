#!/bin/sh

set -eu

OUT="${1:-/tmp/mesh-install.tgz}"
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)

python3 - "$ROOT" "$OUT" <<'PY'
import pathlib
import sys
import tarfile

root = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
keep = [
    "install/README.md",
    "install/install.sh",
    "install/hooks",
    "install/payload",
]

out.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(out, "w:gz") as tar:
    for rel in keep:
        path = root / rel
        if path.exists():
            tar.add(path, arcname=rel)

print(out)
PY

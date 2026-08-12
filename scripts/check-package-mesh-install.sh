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

# v0.2.1 shipped install/payload/meshd/.omc/state/... because the packager walked
# the working tree. Reject ANY dot-entry, not just the one path that bit us.
junk = sorted(n for n in names if any(part.startswith(".") for part in n.split("/")))
assert not junk, f"untracked/dot entries in payload: {junk}"

# Belt and braces: nothing outside the intended prefixes.
allowed = ("install/README.md", "install/install.sh", "install/hooks/", "install/payload/")
stray = sorted(n for n in names if not n.startswith(allowed) and n not in {"install", "install/"})
assert not stray, f"unexpected entries: {stray}"
PY

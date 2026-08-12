#!/bin/sh
# Package the mesh installer for hosting.
#   sh scripts/package-mesh-install.sh [OUT_TGZ] [SRC_URL]
# Produces OUT_TGZ (the payload tarball). If SRC_URL is given, also writes a
# standalone install.sh next to it with the source URL baked in, so a bare
#   curl -fsSL SRC_URL/install.sh | sh
# fetches SRC_URL/mesh-install.tgz with no extra flags.
#
# Membership comes from `git ls-files`, never from a directory walk: v0.2.1 was
# published with two untracked .omc/ tool-state files because the walk swept the
# working tree. Anything not committed does not ship.

set -eu

OUT="${1:-/tmp/mesh-install.tgz}"
SRC_URL="${2:-}"
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)

python3 - "$ROOT" "$OUT" <<'PY'
import gzip, pathlib, subprocess, sys, tarfile
root = pathlib.Path(sys.argv[1]); out = pathlib.Path(sys.argv[2])
keep = ["install/README.md", "install/install.sh", "install/hooks", "install/payload"]

listing = subprocess.run(
    ["git", "-C", str(root), "ls-files", "-z", "--", *keep],
    check=True, capture_output=True,
).stdout
files = sorted(p for p in listing.decode().split("\0") if p)
if not files:
    sys.exit("no tracked files matched; run from a git checkout")

def reset(info: tarfile.TarInfo) -> tarfile.TarInfo:
    # Fixed metadata so the same commit always produces the same bytes.
    info.mtime = 0
    info.uid = info.gid = 0
    info.uname = info.gname = "root"
    return info

out.parent.mkdir(parents=True, exist_ok=True)
# gzip stamps its own mtime into the header, so drive it explicitly rather than
# using tarfile's "w:gz" — otherwise the same commit yields different bytes.
with open(out, "wb") as raw:
    with gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w") as tar:
            for rel in files:
                tar.add(root / rel, arcname=rel, filter=reset)
print(out)
PY

if [ -n "$SRC_URL" ]; then
  STAMPED=$(dirname "$OUT")/install.sh
  # Only stamp the assignment line — NOT the `!= "__MESH_SRC__"` guard, which must
  # keep the literal placeholder so the baked default actually gets used.
  sed "s#^MESH_SRC_DEFAULT=\"__MESH_SRC__\"#MESH_SRC_DEFAULT=\"${SRC_URL}\"#" "$ROOT/install/install.sh" > "$STAMPED"
  chmod +x "$STAMPED"
  printf '%s\n' "$STAMPED"
  printf 'Host both files at %s and users run:\n' "$SRC_URL"
  printf '  curl -fsSL %s/install.sh | sh\n' "$SRC_URL"
fi

#!/bin/sh
# release-mesh-install.sh — cut a daemon release to LeSearch-AI/mesh-install.
#
#   sh scripts/release-mesh-install.sh              # build + verify, publish nothing
#   sh scripts/release-mesh-install.sh --publish     # …and create the GitHub release
#
# Why this exists. The fleet does not run this repo — it runs whatever mesh-install last
# released. On 2026-08-27 that was v0.4.1 from 21 Aug against a 0.5.0 daemon here, so
# seven capabilities the apps call every day were answered by nothing, and every new user
# installed a daemon that SIGKILLed itself whenever a shell opened. Nobody decided that.
# Releasing was four manual steps in the right order with a checksum in the middle, so it
# quietly did not happen for a week.
#
# The tag comes from the daemon itself. There is no --version flag on purpose: a release
# named differently from the code inside it is the bug this whole file is here to stop.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="LeSearch-AI/mesh-install"
SRC_URL="https://github.com/$REPO/releases/latest/download"
PUBLISH=0
[ "${1:-}" = "--publish" ] && PUBLISH=1

VERSION="$(sed -n 's/^[[:space:]]*const VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$ROOT/install/payload/meshd/server.ts" | head -1)"
[ -n "$VERSION" ] || { echo "FAIL: no VERSION in install/payload/meshd/server.ts"; exit 1; }
TAG="v$VERSION"

echo "==> releasing meshd $VERSION as $TAG to $REPO"

# 1. The gate. A release is the one artifact nobody re-reads before running it, so it does
#    not get cut from a tree whose own checks are failing.
echo "==> self-checks"
sh "$ROOT/scripts/check-all.sh" >/dev/null || { echo "FAIL: check-all.sh is red — not releasing"; exit 1; }
echo "    all self-checks passed"

# 2. Build.
OUT="$ROOT/build/release-$TAG"
rm -rf "$OUT"; mkdir -p "$OUT"
sh "$ROOT/scripts/package-mesh-install.sh" "$OUT/mesh-install.tgz" "$SRC_URL" >/dev/null
echo "==> built $(wc -c < "$OUT/mesh-install.tgz" | tr -d ' ') bytes, $(tar -tzf "$OUT/mesh-install.tgz" | wc -l | tr -d ' ') files"

# 3. Prove the tarball contains the version we are about to name it after. Packaging reads
#    the working tree, so an uncommitted or half-staged edit can otherwise ship under a tag
#    that describes something else.
STAGE="$(mktemp -d)"
tar -xzf "$OUT/mesh-install.tgz" -C "$STAGE"
INNER="$(sed -n 's/^[[:space:]]*const VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$STAGE/install/payload/meshd/server.ts" | head -1)"
[ "$INNER" = "$VERSION" ] || { rm -rf "$STAGE"; echo "FAIL: tarball contains $INNER, tag says $VERSION"; exit 1; }

# 4. The published v0.4.1 server.ts carries two NUL bytes, which makes `file` call it data
#    and makes grep silently refuse to match it — a whole class of "I searched and found
#    nothing" that is not evidence of anything. Never ship that again.
nulls=""
for f in "$STAGE"/install/payload/meshd/*.ts "$STAGE"/install/payload/bin/*; do
  [ -f "$f" ] || continue
  raw=$(wc -c < "$f" | tr -d ' ')
  stripped=$(LC_ALL=C tr -d '\000' < "$f" | wc -c | tr -d ' ')
  [ "$raw" = "$stripped" ] || nulls="$nulls $(basename "$f")"
done
if [ -n "$nulls" ]; then
  rm -rf "$STAGE"; echo "FAIL: NUL bytes in the packaged payload:$nulls"; exit 1
fi
rm -rf "$STAGE"
echo "    tarball verified: meshd $INNER, no NUL bytes"

# 5. Checksums, in both shapes the installer and humans already expect.
( cd "$OUT" && shasum -a 256 mesh-install.tgz > mesh-install.tgz.sha256 \
    && cp mesh-install.tgz.sha256 SHA256SUMS.txt )

echo "==> artifacts in $OUT"
for f in install.sh mesh-install.tgz mesh-install.tgz.sha256 SHA256SUMS.txt; do
  [ -f "$OUT/$f" ] && echo "    $f  ($(wc -c < "$OUT/$f" | tr -d ' ') bytes)"
done

if [ "$PUBLISH" -eq 0 ]; then
  cat <<MSG

Nothing was published. To cut the release:

  sh scripts/release-mesh-install.sh --publish

MSG
  exit 0
fi

command -v gh >/dev/null 2>&1 || { echo "FAIL: gh is not installed"; exit 1; }
gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 \
  && { echo "FAIL: $TAG already exists on $REPO — bump VERSION in meshd/server.ts"; exit 1; }

# Release notes come from CHANGELOG's Unreleased block, which is written as it ships and is
# already the source for TestFlight's "What to Test". One description, not two that drift.
NOTES="$OUT/notes.md"
awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f' "$ROOT/CHANGELOG.md" > "$NOTES"
[ -s "$NOTES" ] || echo "See CHANGELOG.md." > "$NOTES"

echo "==> publishing $TAG"
gh release create "$TAG" -R "$REPO" \
  --title "mesh $VERSION" --notes-file "$NOTES" \
  "$OUT/mesh-install.tgz" "$OUT/install.sh" \
  "$OUT/mesh-install.tgz.sha256" "$OUT/SHA256SUMS.txt"

echo "==> published: https://github.com/$REPO/releases/tag/$TAG"
echo "    users upgrade with:  mesh upgrade"
echo "    new machines:        curl -fsSL $SRC_URL/install.sh | sh"

#!/bin/sh
# check-product-spec.sh — docs/product/PRODUCT.md is the one place the product is
# defined, so it must name every screen file, every daemon module, every helper and
# every capability the daemon advertises. A PR that adds one without editing the spec
# fails here. Reads the tree only; runs in under a second.
set -eu
cd "$(dirname "$0")/.."
SPEC=docs/product/PRODUCT.md
[ -f "$SPEC" ] || { echo "check-product-spec: $SPEC missing"; exit 1; }
fail=0
miss() { printf 'check-product-spec: %s is not named in %s\n' "$1" "$SPEC"; fail=1; }

for f in iOS/*.swift Watch/*.swift MeshDesktop/*.swift MeshWatchWidgets/*.swift \
         WatchWidgets/*.swift Shared/*.swift \
         install/payload/meshd/*.ts install/payload/meshd/*.html install/payload/bin/*; do
  n=$(basename "$f")
  grep -qF "$n" "$SPEC" || miss "$n"
done

# The daemon's own capability list, one line in server.ts. Each must appear in backticks.
sed -n 's/^const CAPABILITIES = \[\(.*\)\];.*/\1/p' install/payload/meshd/server.ts \
  | tr -d '" ' | tr ',' '\n' | while read -r c; do
  [ -n "$c" ] || continue
  grep -qF "\`$c\`" "$SPEC" || { miss "capability $c"; }
done | tee /tmp/check-product-spec.$$
[ -s /tmp/check-product-spec.$$ ] && fail=1
rm -f /tmp/check-product-spec.$$

[ "$fail" = 0 ] && echo "check-product-spec: ok" || exit 1

#!/bin/sh
# check-web-docs.sh — web/getting-started.html is the rendering of docs/getting-started.md
# (one source; the page lesearch.ai serves cannot drift from the doc in the repo), every
# screenshot the doc embeds exists under docs/product/shots/ and is a real capture (>10 KB),
# and the landing page links the page, the installer and the reported-problems list.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-web-docs: SKIP (bun not installed)"; exit 0; }
fail=0
say() { echo "FAIL: check-web-docs: $*"; fail=1; }
(cd "$ROOT" && bun scripts/build-web-docs.ts --check >/dev/null 2>&1) || say "web/getting-started.html is stale — run: bun scripts/build-web-docs.ts"
for img in $(grep -oE '!\[[^]]*\]\(product/shots/[^)]+\)' "$ROOT/docs/getting-started.md" | sed 's/.*(\(.*\))/\1/'); do
  f="$ROOT/docs/$img"
  [ -f "$f" ] || { say "getting-started.md embeds $img which does not exist"; continue; }
  [ "$(wc -c <"$f" | tr -d ' ')" -gt 10000 ] || say "$img is under 10 KB — not a real screenshot"
  [ -f "$ROOT/web/shots/$(basename "$img")" ] || say "web/shots/$(basename "$img") missing — run: bun scripts/build-web-docs.ts"
done
grep -q 'href="/getting-started"' "$ROOT/web/index.html" || say "web/index.html does not link /getting-started"
grep -q 'href="/install.sh"' "$ROOT/web/index.html" || say "web/index.html does not link /install.sh"
grep -q 'label%3Afrom-users' "$ROOT/web/index.html" || say "web/index.html does not link the from-users issues"
grep -q 'Report a problem' "$ROOT/web/privacy.html" || say "web/privacy.html does not describe Report a problem"
[ "$fail" -eq 0 ] || exit 1
echo "check-web-docs: OK — getting-started rendered from the doc, screenshots real, landing links present"

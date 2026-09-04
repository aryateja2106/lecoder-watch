#!/bin/sh
# `mesh apps` is what both app-building skills end on: publish a PWA, register a native
# build, install it. Every mutating command runs entirely inside a throwaway HOME so this
# never touches the real ~/.mesh/apps. Slug validation matters more than most of this
# CLI — a slug becomes a directory name under ~/.mesh/apps/ and a URL path segment the
# daemon will one day serve without auth, so a path-traversal slug has to be refused, not
# merely discouraged.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MESH="$ROOT/install/payload/bin/mesh"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-apps: SKIP (no bun)"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP" MESH_HOME="$TMP/.mesh"
run() { bun "$MESH" "$@"; }

fail=0
bad() { echo "FAIL: $1"; fail=1; }

# ---- 1. config: unset by default, round-trips through --team/--prefix ----
out="$(run apps config)"
printf '%s' "$out" | grep -q '(not set)' || bad "apps config did not report unset team/prefix on a fresh HOME"

run apps config --team AB12CD34EF --prefix com.example.checks >/dev/null
[ -f "$TMP/.mesh/apps.json" ] || bad "apps config --team/--prefix did not write apps.json"
perm=$(stat -f '%Lp' "$TMP/.mesh/apps.json" 2>/dev/null || stat -c '%a' "$TMP/.mesh/apps.json" 2>/dev/null || echo '?')
[ "$perm" = "600" ] || bad "apps.json is mode $perm, want 600"
out="$(run apps config)"
printf '%s' "$out" | grep -q 'AB12CD34EF' || bad "apps config did not persist --team"
printf '%s' "$out" | grep -q 'com.example.checks' || bad "apps config did not persist --prefix"

# ---- 2. publish: a 2-file site, assert meta.json fields + the printed URL ----
mkdir -p "$TMP/site"
printf '<h1>hi</h1>' > "$TMP/site/index.html"
printf 'body{color:red}' > "$TMP/site/styles.css"

out="$(run apps publish "$TMP/site" --slug check-pwa --name "Check PWA")"
printf '%s' "$out" | grep -q '^ok publish check-pwa$' || bad "publish did not end on 'ok publish check-pwa': $out"

META="$TMP/.mesh/apps/check-pwa/meta.json"
[ -f "$META" ] || bad "publish did not write $META"
if [ -f "$META" ]; then
  perm=$(stat -f '%Lp' "$META" 2>/dev/null || stat -c '%a' "$META" 2>/dev/null || echo '?')
  [ "$perm" = "600" ] || bad "meta.json is mode $perm, want 600"
  grep -q '"slug": "check-pwa"' "$META" || bad "meta.json missing slug"
  grep -q '"name": "Check PWA"' "$META" || bad "meta.json missing name"
  grep -q '"kind": "pwa"' "$META" || bad "meta.json missing kind=pwa"
  grep -qE '"key": "[0-9a-f]{8}"' "$META" || bad "meta.json missing an 8-hex key"
  url=$(grep -oE '"url": "[^"]+"' "$META" | cut -d'"' -f4)
  case "$url" in
    http://*:8899/a/check-pwa-*/) : ;;
    *) bad "meta.json url looks wrong: $url" ;;
  esac
fi
[ -f "$TMP/.mesh/apps/check-pwa/site/index.html" ] || bad "publish did not copy the site into place"
[ -f "$TMP/.mesh/apps/check-pwa/site/styles.css" ] || bad "publish did not copy every file in the site"

# --json carries the same url as meta.json.
json_out="$(run apps publish "$TMP/site" --slug check-pwa2 --name "Check PWA 2" --json)"
printf '%s' "$json_out" | grep -q '"ok": true' || bad "publish --json missing ok:true"
printf '%s' "$json_out" | grep -qE '"url": "http://[^"]+:8899/a/check-pwa2-[0-9a-f]{8}/"' || bad "publish --json url shape wrong: $json_out"

# ---- 3. add: a fake .app dir is enough (add stores a path, copies nothing) ----
mkdir -p "$TMP/Fake.app"
out="$(run apps add check-native --name "Check Native" --app "$TMP/Fake.app" --bundle-id com.example.checks.native)"
printf '%s' "$out" | grep -q '^ok add check-native$' || bad "add did not end on 'ok add check-native': $out"
META2="$TMP/.mesh/apps/check-native/meta.json"
grep -q '"kind": "native"' "$META2" || bad "native meta.json missing kind=native"
grep -q "\"app\": \"$TMP/Fake.app\"" "$META2" || bad "native meta.json missing the app path"
grep -q '"bundleId": "com.example.checks.native"' "$META2" || bad "native meta.json missing bundleId"
# add must not have copied the bundle anywhere.
[ -d "$TMP/.mesh/apps/check-native/site" ] && bad "add copied a site/ directory — it should only store a path"

# ---- 4. list: both apps show up ----
out="$(run apps list)"
printf '%s' "$out" | grep -q 'check-pwa' || bad "list is missing check-pwa"
printf '%s' "$out" | grep -q 'check-native' || bad "list is missing check-native"

# ---- 5. slug validation rejects path traversal (and everything else the regex bars) ----
for bad_slug in '../x' '../../etc/passwd' 'UPPER' 'has space' '.hidden' '-leading-dash' ''; do
  set +e
  out=$(run apps add "$bad_slug" --name X --app "$TMP/Fake.app" --bundle-id com.x.y 2>&1)
  code=$?
  set -e
  [ "$code" -eq 0 ] && bad "apps add accepted invalid slug '$bad_slug'"
  printf '%s' "$out" | grep -qi 'invalid' || bad "apps add on bad slug '$bad_slug' did not say invalid: $out"
done
# A path-traversal slug must never have touched the filesystem outside ~/.mesh/apps.
[ -e "$TMP/.mesh/apps/../etc" ] && bad "a path-traversal slug actually created something outside apps/"
[ -e "$TMP/etc" ] && bad "a path-traversal slug escaped the apps directory"

set +e
out=$(run apps publish "$TMP/site" --slug '../x' --name X 2>&1); code=$?
set -e
[ "$code" -eq 0 ] && bad "apps publish accepted a path-traversal slug"

# ---- 6. remove: forgets an app; errors are on stdout, last line machine-readable ----
out="$(run apps remove check-native)"
printf '%s' "$out" | grep -q '^ok remove check-native$' || bad "remove did not end on 'ok remove check-native': $out"
[ -e "$TMP/.mesh/apps/check-native" ] && bad "remove left check-native's directory behind"

set +e
out=$(run apps remove no-such-app 2>&1); code=$?
set -e
[ "$code" -eq 0 ] && bad "removing a nonexistent app exited 0"
printf '%s' "$out" | grep -q '^error ' || bad "remove error did not end on an 'error ...' line: $out"

# ---- 7. real ~/.mesh was never touched ----
[ -d "$HOME/.mesh/apps" ] && [ "$HOME" != "$TMP" ] && bad "a real ~/.mesh/apps exists and this check ran outside its sandbox"

if [ "$fail" -eq 0 ]; then
  echo "check-mesh-apps: OK (config/publish/add/list/remove verified, path-traversal slugs rejected)"
else
  exit 1
fi

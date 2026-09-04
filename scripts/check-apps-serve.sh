#!/bin/sh
# apps.ts self-check: a registered web app is served token-free at /a/<slug>-<key>/ with
# the right content types, the bare path redirects to the slash form, a wrong key, an
# unknown slug and every path-traversal spelling answer 404, GET /built-apps lists the app
# without leaking its key or a Mac path, and a native app refuses to be "opened" while a
# web app refuses to be "installed". Runs a throwaway daemon on a free port against a
# temp MESH_HOME; nothing touches ~/.mesh.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-apps-serve: SKIP (bun not installed)"; exit 0; }
command -v curl >/dev/null 2>&1 || { echo "check-apps-serve: SKIP (curl not installed)"; exit 0; }
TMP="$(mktemp -d)"
PID=""
cleanup() { [ -n "$PID" ] && { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }; rm -rf "$TMP"; }
trap cleanup EXIT
fail=0
expect() { if [ "$2" = "$3" ]; then :; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
code() { curl -s -o /dev/null -w '%{http_code}' -m 5 "$@"; }
hdr() { curl -s -o /dev/null -w "%{$1}" -m 5 "$2"; }

HOME_DIR="$TMP/home"; MESH="$HOME_DIR/.mesh"
mkdir -p "$MESH/apps/notes/site/css" "$MESH/apps/counter" "$TMP/outside"
printf '<!doctype html><title>Notes</title><link rel=stylesheet href=css/a.css>' >"$MESH/apps/notes/site/index.html"
printf 'body{margin:0}' >"$MESH/apps/notes/site/css/a.css"
printf '{"name":"Notes"}' >"$MESH/apps/notes/site/manifest.webmanifest"
printf 'SECRET OUTSIDE' >"$TMP/outside/secret.txt"
ln -s "$TMP/outside/secret.txt" "$MESH/apps/notes/site/link.txt"
printf '{"slug":"notes","name":"Notes","kind":"pwa","key":"0123abcd","updated":"2026-09-04T00:00:00Z"}' >"$MESH/apps/notes/meta.json"
printf '{"slug":"counter","name":"Counter","kind":"native","app":"/Users/nobody/build/Counter.app","bundleId":"com.example.counter","updated":"2026-09-03T00:00:00Z"}' >"$MESH/apps/counter/meta.json"
mkdir -p "$MESH/apps/bad-meta" && printf 'not json' >"$MESH/apps/bad-meta/meta.json"
printf '#!/bin/sh\necho "ok fake-install $*"\n' >"$TMP/mesh"; chmod +x "$TMP/mesh"

PORT="$(bun -e 'const s=Bun.listen({hostname:"127.0.0.1",port:0,socket:{data(){}}});console.log(s.port);s.stop()')"
TOKEN="check-apps-token-0123456789abcdef"
HOME="$HOME_DIR" MESH_HOME="$MESH" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" MESHD_TOKEN="$TOKEN" MESH_BIN="$TMP/mesh" \
  MESHD_EVENTS_PATH="$TMP/events.jsonl" MESHD_EXPOSURES_PATH="$TMP/exposures.json" MESHD_TELEMETRY=off \
  bun "$ROOT/install/payload/meshd/server.ts" >"$TMP/meshd.log" 2>&1 &
PID=$!
i=0; until curl -s -m 1 -o /dev/null "http://127.0.0.1:$PORT/health"; do i=$((i+1)); [ $i -lt 60 ] || { echo "daemon never answered"; cat "$TMP/meshd.log"; exit 1; }; sleep 0.1; done
B="http://127.0.0.1:$PORT"

expect "capability apps"        1   "$(curl -s -m 5 "$B/health" | grep -c '"apps"')"
expect "index served"           200 "$(code "$B/a/notes-0123abcd/")"
expect "index is html"          "text/html; charset=utf-8" "$(hdr content_type "$B/a/notes-0123abcd/")"
expect "index body"             "Notes" "$(curl -s -m 5 "$B/a/notes-0123abcd/" | sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p')"
expect "css served"             "text/css; charset=utf-8" "$(hdr content_type "$B/a/notes-0123abcd/css/a.css")"
expect "manifest type"          "application/manifest+json; charset=utf-8" "$(hdr content_type "$B/a/notes-0123abcd/manifest.webmanifest")"
expect "bare path redirects"    302 "$(code "$B/a/notes-0123abcd")"
expect "redirect target"        "/a/notes-0123abcd/" "$(hdr redirect_url "$B/a/notes-0123abcd" | sed 's#http://[^/]*##')"
expect "wrong key"              404 "$(code "$B/a/notes-deadbeef/")"
expect "unknown slug"           404 "$(code "$B/a/nothing-0123abcd/")"
expect "native slug not served" 404 "$(code "$B/a/counter-0123abcd/")"
expect "missing file"           404 "$(code "$B/a/notes-0123abcd/nope.js")"
expect "traversal ../"          404 "$(code --path-as-is "$B/a/notes-0123abcd/../meta.json")"
expect "traversal encoded"      404 "$(code --path-as-is "$B/a/notes-0123abcd/..%2Fmeta.json")"
expect "traversal double"       404 "$(code --path-as-is "$B/a/notes-0123abcd/css/../../meta.json")"
expect "symlink out of site"    404 "$(code "$B/a/notes-0123abcd/link.txt")"
expect "meta.json not reachable" 404 "$(code "$B/a/notes-0123abcd/../../notes/meta.json")"

A="Authorization: Bearer $TOKEN"
LIST="$(curl -s -m 5 -H "$A" "$B/built-apps")"
expect "list has both apps"     2 "$(printf '%s' "$LIST" | grep -o '"slug"' | wc -l | tr -d ' ')"
expect "list skips bad meta"    0 "$(printf '%s' "$LIST" | grep -c 'bad-meta')"
expect "list carries pwa url"   1 "$(printf '%s' "$LIST" | grep -c '/a/notes-0123abcd/')"
expect "list hides .app path"   0 "$(printf '%s' "$LIST" | grep -c 'Counter.app')"
expect "list hides raw key"     0 "$(printf '%s' "$LIST" | grep -c '"key"')"
expect "newest first"           "notes" "$(printf '%s' "$LIST" | sed -n 's/.*"apps":\[{"slug":"\([a-z]*\)".*/\1/p')"
expect "install native via cli" 200 "$(code -H "$A" -X POST -d '{"target":"sim"}' "$B/built-apps/counter/install")"
expect "install passes --sim"   1 "$(curl -s -m 20 -H "$A" -X POST -d '{"target":"sim"}' "$B/built-apps/counter/install" | grep -c 'fake-install apps install counter --sim')"
expect "install pwa refused"    400 "$(code -H "$A" -X POST -d '{}' "$B/built-apps/notes/install")"
expect "install unknown 400"    400 "$(code -H "$A" -X POST -d '{}' "$B/built-apps/nothing/install")"

[ "$fail" -eq 0 ] || { echo "check-apps-serve: FAILED"; tail -5 "$TMP/meshd.log"; exit 1; }
echo "check-apps-serve: OK"

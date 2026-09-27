#!/bin/sh
# Wireless (OTA) install self-check: `mesh apps add --app` on a device build packages a
# valid .ipa (Payload/<App>.app at the zip root) and keeps its key across re-adds; the
# daemon serves manifest.plist with absolute HTTPS URLs from otaBase, the .ipa as an
# octet-stream, an install page carrying the itms-services link, and nothing else from
# the folder (meta.json stays private); GET /built-apps carries `install` only when an
# .ipa AND an HTTPS origin exist; a native app without an .ipa is not served at all; and
# a request that arrived through a reverse proxy (X-Forwarded-For) no longer enjoys the
# loopback token exemption — Tailscale Serve connects from 127.0.0.1 on behalf of the
# whole tailnet. Throwaway daemon on a free port, temp MESH_HOME; nothing touches ~/.mesh.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-apps-ota: SKIP (bun not installed)"; exit 0; }
command -v curl >/dev/null 2>&1 || { echo "check-apps-ota: SKIP (curl not installed)"; exit 0; }
command -v zip >/dev/null 2>&1 || { echo "check-apps-ota: SKIP (zip not installed)"; exit 0; }
[ -x /usr/libexec/PlistBuddy ] || { echo "check-apps-ota: SKIP (PlistBuddy: macOS only)"; exit 0; }
TMP="$(mktemp -d)"
PID=""
cleanup() { [ -n "$PID" ] && { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }; rm -rf "$TMP"; }
trap cleanup EXIT
fail=0
expect() { if [ "$2" = "$3" ]; then :; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
code() { curl -s -o /dev/null -w '%{http_code}' -m 5 "$@"; }
hdr() { curl -s -o /dev/null -w "%{$1}" -m 5 "$2"; }

HOME_DIR="$TMP/home"; MESH="$HOME_DIR/.mesh"
mkdir -p "$MESH" "$TMP/build/Tally.app"
cat >"$TMP/build/Tally.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.tally</string>
<key>CFBundleShortVersionString</key><string>1.2</string>
<key>CFBundleVersion</key><string>7</string>
<key>DTPlatformName</key><string>iphoneos</string>
</dict></plist>
PLIST
printf 'fake-binary' >"$TMP/build/Tally.app/Tally"
printf 'fake-profile' >"$TMP/build/Tally.app/embedded.mobileprovision"
printf '\211PNG-fake' >"$TMP/build/Tally.app/AppIcon60x60@2x.png"
mkdir -p "$TMP/build/SimOnly.app"
sed 's/iphoneos/iphonesimulator/; s/com.example.tally/com.example.simonly/' "$TMP/build/Tally.app/Info.plist" >"$TMP/build/SimOnly.app/Info.plist"

MESH_CLI="$ROOT/install/payload/bin/mesh"
run_mesh() { HOME="$HOME_DIR" MESH_HOME="$MESH" bun "$MESH_CLI" "$@"; }

# 1. Packaging on add, before any HTTPS origin exists.
OUT="$(run_mesh apps add tally --name Tally --app "$TMP/build/Tally.app" --bundle-id com.example.tally 2>&1 || true)"
expect "add ok"                 "ok add tally" "$(printf '%s\n' "$OUT" | tail -1)"
expect "ipa written"            1 "$([ -f "$MESH/apps/tally/tally.ipa" ] && echo 1 || echo 0)"
expect "ipa root is Payload"    1 "$(unzip -l "$MESH/apps/tally/tally.ipa" | grep -c ' Payload/Tally.app/Info.plist$')"
expect "ipa keeps profile"      1 "$(unzip -l "$MESH/apps/tally/tally.ipa" | grep -c ' Payload/Tally.app/embedded.mobileprovision$')"
expect "icon copied"            1 "$([ -f "$MESH/apps/tally/icon.png" ] && echo 1 || echo 0)"
expect "stage removed"          0 "$([ -e "$MESH/apps/tally/.ipa-stage" ] && echo 1 || echo 0)"
expect "meta has version"       1 "$(grep -c '"version": "1.2"' "$MESH/apps/tally/meta.json")"
expect "add mentions ota"       1 "$(printf '%s\n' "$OUT" | grep -c 'mesh apps ota --enable')"
KEY="$(sed -n 's/.*"key": "\([0-9a-f]*\)".*/\1/p' "$MESH/apps/tally/meta.json")"
expect "key minted"             8 "$(printf '%s' "$KEY" | wc -c | tr -d ' ')"
OUT2="$(run_mesh apps add simonly --name SimOnly --app "$TMP/build/SimOnly.app" --bundle-id com.example.simonly 2>&1 || true)"
expect "sim build add ok"       "ok add simonly" "$(printf '%s\n' "$OUT2" | tail -1)"
expect "sim build not packaged" 0 "$([ -f "$MESH/apps/simonly/simonly.ipa" ] && echo 1 || echo 0)"

# 2. An HTTPS origin, as `mesh apps ota --url` would store it (no tailscale in a check).
OUT3="$(run_mesh apps ota --url https://mac.example.ts.net/ 2>&1 || true)"
expect "ota --url ok"           "ok ota enabled" "$(printf '%s\n' "$OUT3" | tail -1)"
expect "ota base stored"        1 "$(grep -c '"otaBase": "https://mac.example.ts.net"' "$MESH/apps.json")"
expect "ota --url rejects http" "error" "$(run_mesh apps ota --url http://mac.example.ts.net 2>&1 | tail -1 | cut -d' ' -f1)"
expect "ota status lists app"   1 "$(run_mesh apps ota 2>&1 | grep -c "https://mac.example.ts.net/a/tally-$KEY/")"
# Re-add keeps the key, so a link already on the phone keeps working.
run_mesh apps add tally --name Tally --app "$TMP/build/Tally.app" --bundle-id com.example.tally >/dev/null 2>&1 || true
expect "re-add keeps key"       "$KEY" "$(sed -n 's/.*"key": "\([0-9a-f]*\)".*/\1/p' "$MESH/apps/tally/meta.json")"
# --ipa: an .ipa built elsewhere (the Linux-host story).
cp "$MESH/apps/tally/tally.ipa" "$TMP/elsewhere.ipa"
OUT4="$(run_mesh apps add ported --name Ported --ipa "$TMP/elsewhere.ipa" --bundle-id com.example.ported --app-version 3.0 2>&1 || true)"
expect "add --ipa ok"           "ok add ported" "$(printf '%s\n' "$OUT4" | tail -1)"
expect "add --ipa copied"       1 "$([ -f "$MESH/apps/ported/ported.ipa" ] && echo 1 || echo 0)"
expect "add --ipa prints link"  1 "$(printf '%s\n' "$OUT4" | grep -c 'install wirelessly: https://mac.example.ts.net/a/ported-')"

# 3. The daemon serves the folder.
PORT="$(bun -e 'const s=Bun.listen({hostname:"127.0.0.1",port:0,socket:{data(){}}});console.log(s.port);s.stop()')"
TOKEN="check-ota-token-0123456789abcdef"
HOME="$HOME_DIR" MESH_HOME="$MESH" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" MESHD_TOKEN="$TOKEN" MESH_BIN="$MESH_CLI" \
  MESHD_EVENTS_PATH="$TMP/events.jsonl" MESHD_EXPOSURES_PATH="$TMP/exposures.json" MESHD_TELEMETRY=off \
  bun "$ROOT/install/payload/meshd/server.ts" >"$TMP/meshd.log" 2>&1 &
PID=$!
i=0; until curl -s -m 1 -o /dev/null "http://127.0.0.1:$PORT/health"; do i=$((i+1)); [ $i -lt 60 ] || { echo "daemon never answered"; cat "$TMP/meshd.log"; exit 1; }; sleep 0.1; done
B="http://127.0.0.1:$PORT"; R="$B/a/tally-$KEY"

MANIFEST="$(curl -s -m 5 "$R/manifest.plist")"
expect "manifest 200"           200 "$(code "$R/manifest.plist")"
expect "manifest is xml"        "application/xml; charset=utf-8" "$(hdr content_type "$R/manifest.plist")"
expect "manifest valid plist"   0 "$(printf '%s' "$MANIFEST" | plutil -lint -s - >/dev/null 2>&1; echo $?)"
expect "manifest package url"   1 "$(printf '%s' "$MANIFEST" | grep -c "<string>https://mac.example.ts.net/a/tally-$KEY/tally.ipa</string>")"
expect "manifest icon url"      2 "$(printf '%s' "$MANIFEST" | grep -o "https://mac.example.ts.net/a/tally-$KEY/icon.png" | wc -l | tr -d ' ')"
expect "manifest bundle id"     1 "$(printf '%s' "$MANIFEST" | grep -c '<string>com.example.tally</string>')"
expect "manifest version"       1 "$(printf '%s' "$MANIFEST" | grep -c '<string>1.2</string>')"
expect "manifest no http url"   0 "$(printf '%s' "$MANIFEST" | grep -c '<string>http://')"
expect "ipa 200"                200 "$(code "$R/tally.ipa")"
expect "ipa octet-stream"       "application/octet-stream" "$(hdr content_type "$R/tally.ipa")"
expect "ipa byte-exact"         "$(cksum <"$MESH/apps/tally/tally.ipa")" "$(curl -s -m 5 "$R/tally.ipa" | cksum)"
expect "icon 200"               200 "$(code "$R/icon.png")"
expect "icon png"               "image/png" "$(hdr content_type "$R/icon.png")"
expect "page 200"               200 "$(code "$R/")"
expect "page has itms link"     1 "$(curl -s -m 5 "$R/" | grep -c "itms-services://?action=download-manifest&amp;url=https%3A%2F%2Fmac.example.ts.net%2Fa%2Ftally-$KEY%2Fmanifest.plist")"
expect "page no http warning"   0 "$(curl -s -m 5 "$R/" | grep -c 'plain HTTP')"
expect "bare path redirects"    302 "$(code "$R")"
expect "meta.json private"      404 "$(code "$R/meta.json")"
expect "traversal ../"          404 "$(code --path-as-is "$R/../simonly/meta.json")"
expect "wrong key"              404 "$(code "$B/a/tally-deadbeef/manifest.plist")"
expect "no-ipa native 404"      404 "$(code "$B/a/simonly-$(sed -n 's/.*"key": "\([0-9a-f]*\)".*/\1/p' "$MESH/apps/simonly/meta.json")/")"

A="Authorization: Bearer $TOKEN"
LIST="$(curl -s -m 5 -H "$A" "$B/built-apps")"
expect "list install for tally" 1 "$(printf '%s' "$LIST" | grep -c "\"install\":\"itms-services://?action=download-manifest&url=https%3A%2F%2Fmac.example.ts.net%2Fa%2Ftally-$KEY%2Fmanifest.plist\"")"
expect "list url for tally"     1 "$(printf '%s' "$LIST" | grep -c "\"url\":\"https://mac.example.ts.net/a/tally-$KEY/\"")"
expect "list no install simonly" 0 "$(printf '%s' "$LIST" | sed 's/{"slug"/\n{"slug"/g' | grep '"slug":"simonly"' | grep -c '"install"')"
expect "list hides ipa file"    0 "$(printf '%s' "$LIST" | grep -c '"ipa"')"
expect "list hides key"         0 "$(printf '%s' "$LIST" | grep -c '"key"')"
expect "list otaBase"           1 "$(printf '%s' "$LIST" | grep -c '"otaBase":"https://mac.example.ts.net"')"

# 4. A proxied request (X-Forwarded-For) gets no loopback exemption; a direct one still does.
expect "loopback direct ok"     200 "$(code "$B/health")"
expect "loopback direct agents" 200 "$(code "$B/agents")"
expect "proxied needs token"    401 "$(code -H 'X-Forwarded-For: 100.64.0.9' "$B/agents")"
expect "proxied + token ok"     200 "$(code -H 'X-Forwarded-For: 100.64.0.9' -H "$A" "$B/agents")"
expect "proxied ota still open" 200 "$(code -H 'X-Forwarded-For: 100.64.0.9' "$R/manifest.plist")"

# 5. Without an HTTPS origin: served from the request's own origin, page warns, list has no install.
run_mesh apps ota --disable >/dev/null 2>&1 || true
expect "ota disabled"           0 "$(grep -c otaBase "$MESH/apps.json")"
expect "manifest falls back"    1 "$(curl -s -m 5 -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: proxy.example' "$R/manifest.plist" | grep -c "https://proxy.example/a/tally-$KEY/tally.ipa")"
expect "page warns on http"     1 "$(curl -s -m 5 "$R/" | grep -c 'plain HTTP')"
expect "list drops install"     0 "$(curl -s -m 5 -H "$A" "$B/built-apps" | grep -c '"install"')"

[ "$fail" -eq 0 ] || { echo "check-apps-ota: FAILED"; tail -5 "$TMP/meshd.log"; exit 1; }
echo "check-apps-ota: OK"

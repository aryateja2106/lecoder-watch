#!/bin/sh
# check-watch-smoke.sh — the watch app must LAUNCH on a watch simulator, not merely compile.
#
# CI builds "MeshWatch Watch App" and never runs it (publish-plan T26). This launches the
# built watch app on the newest paired watchOS simulator and asserts a live process, the
# same bar check-ios-smoke.sh sets for the phone. Opt-in like the phone smoke: without
# xcrun/a watch sim it SKIPs (exit 0) unless MESH_SMOKE_REQUIRED=1.
#
#   MESH_WATCH_UDID=<udid>  pick a specific booted watch (default: newest available paired watch)
#   MESH_APP_DIR=<path>     a built MeshWatch.app (default: build/DerivedData/.../Debug-iphonesimulator/MeshWatch.app;
#                           built here with xcodebuild when absent — that is the slow path)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUIRED="${MESH_SMOKE_REQUIRED:-0}"
skip() { echo "check-watch-smoke: SKIP — $1"; [ "$REQUIRED" = "1" ] && exit 1; exit 0; }

command -v xcrun >/dev/null 2>&1 || skip "no xcrun"
xcrun simctl list devices available -j >/tmp/check-watch-smoke-$$.json 2>/dev/null || skip "simctl not answering"

UDID="${MESH_WATCH_UDID:-}"
if [ -z "$UDID" ]; then
  UDID=$(python3 - /tmp/check-watch-smoke-$$.json <<'PY'
import json, sys, re
d = json.load(open(sys.argv[1]))["devices"]
best = None
for rt, devs in d.items():
    if "watchOS" not in rt: continue
    m = re.search(r"watchOS-(\d+)-(\d+)", rt)
    ver = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    for dev in devs:
        if not dev.get("isAvailable"): continue
        key = (dev.get("state") == "Booted", ver)
        if best is None or key > best[0]: best = (key, dev["udid"])
print(best[1] if best else "")
PY
)
fi
rm -f /tmp/check-watch-smoke-$$.json
[ -n "$UDID" ] || skip "no watchOS simulator"

APP="${MESH_APP_DIR:-$ROOT/build/DerivedData/Build/Products/Debug-iphonesimulator/MeshWatch.app}"
WATCH_APP="$APP/Watch/MeshWatch Watch App.app"
if [ ! -d "$WATCH_APP" ]; then
  echo "check-watch-smoke: building the phone+watch app (no build at $APP)…"
  (cd "$ROOT" && xcodegen generate >/dev/null && xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build >/dev/null) \
     || { echo "check-watch-smoke: FAIL — xcodebuild failed"; exit 1; }
fi
[ -d "$WATCH_APP" ] || { echo "check-watch-smoke: FAIL — no embedded watch app at $WATCH_APP"; exit 1; }
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$WATCH_APP/Info.plist")

xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$WATCH_APP" || { echo "check-watch-smoke: FAIL — install failed on $UDID"; exit 1; }
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
PID=$(xcrun simctl launch "$UDID" "$BUNDLE" 2>/dev/null | sed -n 's/.*: \([0-9]*\)$/\1/p')
[ -n "$PID" ] || { echo "check-watch-smoke: FAIL — launch printed no pid"; exit 1; }
sleep 5
# Still alive five seconds later: a crash-on-launch exits before this and launchctl forgets it.
if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "UIKitApplication:$BUNDLE"; then
  NAME=$(xcrun simctl list devices | grep "$UDID" | sed 's/ (.*//; s/^ *//')
  echo "check-watch-smoke: OK — $BUNDLE pid $PID alive on $NAME ($UDID)"
else
  echo "check-watch-smoke: FAIL — $BUNDLE launched (pid $PID) but is gone after 5s (crash on launch?)"
  exit 1
fi

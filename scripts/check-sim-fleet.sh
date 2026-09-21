#!/bin/sh
# check-sim-fleet.sh — the app runs on an iPhone, an iPad and a paired Watch simulator, and the
# Mac menu bar app launches — all four surfaces alive at once, with a screenshot of each.
#
# Nothing here ever launched the watch app, the iPad (compat mode: TARGETED_DEVICE_FAMILY is
# "1") or MeshDesktop; the phone smoke was the only surface anyone saw. This one reuses the
# devices that already exist on the Mac (never creates or deletes a simulator) and leaves
# PNGs in $MESH_SHOTS_DIR (default docs/overnight/<today>/shots) so a person can look.
#
# Live only, opt-in: MESH_SIM_LIVE=1. Without it (or without xcrun) prints SKIP and exits 0,
# because check-all runs in CI where no simulator has a paired watch.
#   MESH_IPHONE_UDID / MESH_IPAD_UDID / MESH_WATCH_UDID   pick devices (default: newest booted, else newest available)
#   MESH_APP_DIR   a built MeshWatch.app for the simulator; MESH_MAC_APP a built MeshDesktop (MeshWatch.app for macOS)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ "${MESH_SIM_LIVE:-}" = "1" ] || { echo "check-sim-fleet: SKIP (set MESH_SIM_LIVE=1 to launch on the simulators)"; exit 0; }
command -v xcrun >/dev/null 2>&1 || { echo "check-sim-fleet: SKIP — no xcrun"; exit 0; }

SHOTS="${MESH_SHOTS_DIR:-$ROOT/docs/overnight/$(date +%Y-%m-%d)/shots}"
mkdir -p "$SHOTS"
J=/tmp/check-sim-fleet-$$.json
xcrun simctl list devices available -j >"$J"
pick() { # $1 = iPhone|iPad|Watch  → udid (booted preferred, newest runtime)
  python3 - "$J" "$1" <<'PY'
import json, sys, re
d = json.load(open(sys.argv[1]))["devices"]; kind = sys.argv[2]
best = None
for rt, devs in d.items():
    if kind == "Watch" and "watchOS" not in rt: continue
    if kind != "Watch" and "iOS" not in rt: continue
    m = re.search(r"-(\d+)-(\d+)$", rt); ver = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    for dev in devs:
        if not dev.get("isAvailable"): continue
        t = dev.get("deviceTypeIdentifier", "")
        if kind == "iPhone" and "iPhone" not in t: continue
        if kind == "iPad" and "iPad" not in t: continue
        key = (dev.get("state") == "Booted", ver)
        if best is None or key > best[0]: best = (key, dev["udid"])
print(best[1] if best else "")
PY
}
IPHONE="${MESH_IPHONE_UDID:-$(pick iPhone)}"; IPAD="${MESH_IPAD_UDID:-$(pick iPad)}"; WATCH="${MESH_WATCH_UDID:-$(pick Watch)}"
rm -f "$J"
[ -n "$IPHONE" ] && [ -n "$IPAD" ] && [ -n "$WATCH" ] || { echo "check-sim-fleet: SKIP — need an iPhone, an iPad and a watch simulator (have: '$IPHONE' '$IPAD' '$WATCH')"; exit 0; }

APP="${MESH_APP_DIR:-$ROOT/build/DerivedData/Build/Products/Debug-iphonesimulator/MeshWatch.app}"
MACAPP="${MESH_MAC_APP:-$ROOT/build/DerivedData/Build/Products/Debug/MeshWatch.app}"
[ -d "$APP" ] || { echo "check-sim-fleet: FAIL — no simulator build at $APP (xcodebuild -scheme MeshWatch -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData)"; exit 1; }
[ -d "$MACAPP" ] || { echo "check-sim-fleet: FAIL — no Mac build at $MACAPP (xcodebuild -scheme MeshDesktop -destination 'platform=macOS' -derivedDataPath build/DerivedData)"; exit 1; }
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
MACBUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$MACAPP/Contents/Info.plist")

fail=0
alive() { xcrun simctl spawn "$1" launchctl list 2>/dev/null | grep -q "UIKitApplication:$2"; }
for pair in "iphone:$IPHONE" "ipad:$IPAD"; do
  name=${pair%%:*}; udid=${pair#*:}
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP" || { echo "check-sim-fleet: FAIL — install on $name failed"; fail=1; continue; }
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  # The passcode gate is off so the screenshot shows the app, not a lock screen.
  xcrun simctl launch "$udid" "$BUNDLE" -mesh.requireBiometrics.v1 '<false/>' >/dev/null || { echo "check-sim-fleet: FAIL — launch on $name failed"; fail=1; continue; }
  sleep 5
  if alive "$udid" "$BUNDLE"; then
    xcrun simctl io "$udid" screenshot "$SHOTS/$name.png" >/dev/null 2>&1 || true
    size=$(wc -c <"$SHOTS/$name.png" 2>/dev/null || echo 0)
    [ "$size" -gt 20000 ] && echo "check-sim-fleet: ok   $name ($udid) $BUNDLE alive, screenshot ${size}B" \
      || { echo "check-sim-fleet: FAIL — $name screenshot missing or tiny (${size}B)"; fail=1; }
  else
    echo "check-sim-fleet: FAIL — $name: $BUNDLE gone 5s after launch"; fail=1
  fi
done

MESH_WATCH_UDID="$WATCH" MESH_APP_DIR="$APP" MESH_SMOKE_REQUIRED=1 sh "$ROOT/scripts/check-watch-smoke.sh" || fail=1
xcrun simctl io "$WATCH" screenshot "$SHOTS/watch.png" >/dev/null 2>&1 || true

# Mac menu bar app: open it, then find its process by bundle path (LSUIElement — no window to see).
open "$MACAPP" || { echo "check-sim-fleet: FAIL — could not open $MACAPP"; fail=1; }
sleep 4
if pgrep -f "$MACAPP/Contents/MacOS/" >/dev/null; then
  echo "check-sim-fleet: ok   mac $MACBUNDLE running from $MACAPP"
  /usr/sbin/screencapture -x -R0,0,1800,40 "$SHOTS/mac-menubar.png" 2>/dev/null || true
else
  echo "check-sim-fleet: FAIL — $MACBUNDLE not running after open"; fail=1
fi

[ "$fail" -eq 0 ] && echo "check-sim-fleet: OK — iPhone, iPad, Watch and Mac all alive; shots in $SHOTS"
exit "$fail"

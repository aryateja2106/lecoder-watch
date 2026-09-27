#!/bin/sh
# check-clean-install.sh — the published app installs and launches on a device that has never
# seen it: a brand-new simulator is created, `mesh apps install … --sim` puts the current
# simulator build on it through the same command a user runs, the app comes up in the
# foreground, its version matches the daemon's, and the simulator is deleted again.
#
# Live only (it creates a simulator and needs a build):
#   MESH_CLEAN_INSTALL_LIVE=1 sh scripts/check-clean-install.sh
# Without the flag it says SKIP and exits 0, like every other live check under check-all.
# The registration happens in a throwaway MESH_HOME so the Mac's own app list is untouched.
# Prints the new simulator's udid and the app version on its last line — that line is the
# "Clean-device install:" evidence PUBLISHED.md carries.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ "${MESH_CLEAN_INSTALL_LIVE:-}" = "1" ] || { echo "check-clean-install: SKIP (set MESH_CLEAN_INSTALL_LIVE=1 to create a fresh simulator and install)"; exit 0; }
APP="${MESH_APP_DIR:-$ROOT/build/DerivedData/Build/Products/Debug-iphonesimulator/MeshWatch.app}"
[ -d "$APP" ] || { echo "FAIL: check-clean-install: no simulator build at $APP"; exit 1; }
MESH_BIN="${MESH_BIN:-$ROOT/install/payload/bin/mesh}"
want="$(sed -n 's/^[[:space:]]*const VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/install/payload/meshd/server.ts" | head -1)"
have="$(defaults read "$APP/Info.plist" CFBundleShortVersionString 2>/dev/null || plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")"
[ "$have" = "$want" ] || { echo "FAIL: check-clean-install: build is $have, daemon is $want"; exit 1; }
bundle="$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"

runtime="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x["isAvailable"] and x["platform"]=="iOS"]; r.sort(key=lambda x:[int(p) for p in x["version"].split(".")]); print(r[-1]["identifier"])')"
devtype="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
name="clean-install-$(date +%s)"
udid="$(xcrun simctl create "$name" "$devtype" "$runtime")"
HOME_TMP="$(mktemp -d)"
cleanup() { xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" >/dev/null 2>&1 || true; rm -rf "$HOME_TMP"; }
trap cleanup EXIT
xcrun simctl boot "$udid" >/dev/null 2>&1
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
# never seen the app: prove it before installing
if xcrun simctl listapps "$udid" 2>/dev/null | grep -q "\"$bundle\""; then echo "FAIL: check-clean-install: the fresh simulator already has $bundle"; exit 1; fi

# Register the build in a throwaway home and install with the user's command, aimed at
# the fresh simulator by udid so the Mac's other booted simulators are left alone.
MESH_HOME="$HOME_TMP" bun "$MESH_BIN" apps add clean-install --name "LeSearch AI" --app "$APP" --bundle-id "$bundle" >/dev/null 2>&1 \
  || { echo "FAIL: check-clean-install: mesh apps add refused the simulator build"; exit 1; }
out="$(MESH_HOME="$HOME_TMP" bun "$MESH_BIN" apps install clean-install --sim --device "$udid" 2>&1)" \
  || { echo "FAIL: check-clean-install: mesh apps install --sim failed: $(printf '%s' "$out" | tail -1)"; exit 1; }
xcrun simctl listapps "$udid" 2>/dev/null | grep -q "\"$bundle\"" || { echo "FAIL: check-clean-install: app not on the simulator after install"; exit 1; }
pid="$(xcrun simctl launch "$udid" "$bundle" 2>/dev/null | awk -F': ' '{print $2}')"
sleep 5
xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -q "$bundle" || { echo "FAIL: check-clean-install: app did not stay running (pid $pid)"; exit 1; }
[ -n "${MESH_SHOTS_DIR:-}" ] && xcrun simctl io "$udid" screenshot --type=png "$MESH_SHOTS_DIR/clean-install-first-launch.png" >/dev/null 2>&1 || true
echo "check-clean-install: OK — fresh simulator $udid ($name, iPhone 17 Pro) had never seen $bundle; mesh apps install --sim --device installed LeSearch AI $have and it launched (pid $pid)"

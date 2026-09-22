#!/bin/sh
# product-shots.sh — regenerate docs/product/shots/*.png from the current build: the iPhone
# screens through UITests/ScreenshotTests (real taps, real captures) and the watch screens
# straight off the booted watch simulator. Never a mock.
#
#   sh scripts/product-shots.sh [iphone-udid] [watch-udid]
# Defaults: the first booted iPhone-type simulator and the first booted Apple Watch simulator.
# Needs xcodegen + xcodebuild; the iPhone run takes ~2 minutes.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/docs/product/shots"
mkdir -p "$OUT"
booted() { xcrun simctl list devices booted -j | python3 -c "
import json,sys
kind=sys.argv[1]
for rt,devs in json.load(sys.stdin)['devices'].items():
    for d in devs:
        if d.get('state')=='Booted' and kind in d.get('deviceTypeIdentifier',''): print(d['udid']); raise SystemExit
" "$1"; }
IPHONE="${1:-$(booted iPhone)}"
WATCH="${2:-$(booted Watch)}"
[ -n "$IPHONE" ] || { echo "product-shots: no booted iPhone simulator"; exit 1; }

xcodegen generate >/dev/null 2>&1
RES="$ROOT/build/shots.xcresult"; rm -rf "$RES"
# A pairing link makes the screens show a real machine instead of empty states. The
# simulator loses its Keychain on every reinstall, so this is minted fresh each run;
# MESH_NO_PAIR=1 skips it.
PAIR=""
if [ -z "${MESH_NO_PAIR:-}" ] && command -v bun >/dev/null 2>&1; then
  PAIR="$(bun "$ROOT/install/payload/bin/mesh" pair --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("url",""))' 2>/dev/null || true)"
fi
xcrun simctl bootstatus "$IPHONE" -b >/dev/null 2>&1 || true
TEST_RUNNER_MESH_PAIR_URL="$PAIR" TEST_RUNNER_MESH_SHOTS=1 xcodebuild test -project MeshWatch.xcodeproj -scheme MeshWatch \
  -destination "id=$IPHONE" -derivedDataPath build/Smoke \
  -only-testing:MeshWatchUITests/ScreenshotTests -resultBundlePath "$RES" >"$ROOT/build/shots.log" 2>&1 \
  || { echo "product-shots: ScreenshotTests failed — see build/shots.log"; grep -E "error:" "$ROOT/build/shots.log" | head -5; exit 1; }
TMP="$(mktemp -d)"
xcrun xcresulttool export attachments --path "$RES" --output-path "$TMP" >/dev/null 2>&1
python3 - "$TMP" "$OUT" <<'EOF'
import json, re, shutil, sys, os
tmp, out = sys.argv[1], sys.argv[2]
n = 0
for t in json.load(open(os.path.join(tmp, "manifest.json"))):
    for a in t["attachments"]:
        name = a.get("suggestedHumanReadableName", "")
        # xcresulttool suffixes a duplicate-proof id: "iphone-apps_0_<uuid>.png".
        if name.startswith("iphone-") and name.endswith(".png"):
            clean = re.sub(r"_\d+_[0-9A-F-]{36}\.png$", ".png", name)
            shutil.copyfile(os.path.join(tmp, a["exportedFileName"]), os.path.join(out, clean)); n += 1
print(f"product-shots: {n} iPhone screens exported")
EOF
rm -rf "$TMP"
if [ -n "$WATCH" ]; then
  # The watch app's first screen is the machine list; launch it fresh and shoot.
  xcrun simctl terminate "$WATCH" com.lecoder.meshwatch.watchkitapp >/dev/null 2>&1 || true
  xcrun simctl launch "$WATCH" com.lecoder.meshwatch.watchkitapp >/dev/null 2>&1 || true
  sleep 4
  xcrun simctl io "$WATCH" screenshot --type=png "$OUT/watch-machines.png" >/dev/null 2>&1 && echo "product-shots: watch-machines.png"
fi
# A modal that refuses to close turns every later capture into the same picture; the run
# is worthless then, and silently so.
dupes="$(md5 -q "$OUT"/iphone-*.png | sort | uniq -d | wc -l | tr -d ' ')"
[ "$dupes" -eq 0 ] || { echo "FAIL: product-shots: $dupes iPhone screens are identical — a sheet stayed open, or a tab never switched"; exit 1; }
# Leave the device as this script found it. A paired, polling app makes XCUITest's
# "wait for idle" time out, which is how check-ios-smoke's first test hung for ten
# minutes after a capture run (2026-09-22); the smoke installs its own build anyway.
xcrun simctl uninstall "$IPHONE" com.lecoder.meshwatch >/dev/null 2>&1 || true
ls -la "$OUT"/*.png | awk '{print $5, $NF}'

#!/bin/sh
# Launch the iOS app and put a text field on screen.
#
# This exists because 0.5.0 shipped a crash that every static check in this directory
# was blind to. `UITextField.appearance().smartQuotesType = .no` compiled, read as
# obviously-correct input hygiene, and killed the app on every screen that contained a
# TextField — UIKit replays a stored appearance invocation onto each field entering a
# window, and replaying a UITextInputTraits setter onto a UITextField throws. Nothing
# that reads source can see that. Only running it can.
#
# Skips loudly (exit 0) when there is no simulator new enough to run the app, so CI on a
# runner with an older Xcode reports "not covered here" rather than a false green.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

note() { echo "check-ios-smoke: $1"; }

MIN_MAJOR=26   # the app's deployment target; older runtimes cannot install it at all

udid=$(xcrun simctl list devices available -j 2>/dev/null | python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)["devices"]
except Exception:
    print(""); raise SystemExit
best = None
for runtime, devs in devices.items():
    if "iOS" not in runtime:
        continue
    try:
        version = tuple(int(x) for x in runtime.split("iOS-")[1].split("-"))
    except Exception:
        continue
    if version[0] < '"$MIN_MAJOR"':
        continue
    for dev in devs:
        # Match the device TYPE, not the display name: a simulator can be called
        # anything ("iOS27-repro"), and filtering on the name silently found nothing
        # on the very machine this was written on.
        if not dev.get("isAvailable"):
            continue
        if "iPhone" not in dev.get("deviceTypeIdentifier", ""):
            continue
        if best is None or version > best[0]:
            best = (version, dev["udid"], dev["name"], runtime)
print(best[1] if best else "")
' 2>/dev/null || true)

if [ -z "$udid" ]; then
  note "SKIP — no available iOS ${MIN_MAJOR}+ iPhone simulator on this machine, so the app cannot be launched here."
  note "      This check is a release gate; run it somewhere with a current Xcode before shipping."
  exit 0
fi

note "running UI smoke tests on simulator $udid"
xcodegen generate >/dev/null 2>&1 || { note "FAIL: xcodegen could not generate the project"; exit 1; }

log=$(mktemp -t mesh-ios-smoke)
if xcodebuild test \
     -project MeshWatch.xcodeproj -scheme "MeshWatch" \
     -destination "id=$udid" -derivedDataPath build/Smoke >"$log" 2>&1; then
  grep -E "Test Case .*passed" "$log" | sed 's/^/  /'
  note "OK — the app launches, every tab renders, and a text field can appear"
  rm -f "$log"
  exit 0
fi

note "FAIL: the app did not survive the smoke test"
grep -E "Test Case .*failed|error:|Crash|crashed" "$log" | head -20 | sed 's/^/  /'
note "full log: $log"
exit 1

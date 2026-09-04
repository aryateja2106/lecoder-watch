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
# Skips loudly (exit 0) when there is no simulator new enough to run the app, so a
# developer machine with an older Xcode reports "not covered here" rather than a false green.
#
# MESH_SMOKE_REQUIRED=1 turns every one of those skips into a failure. Set it wherever the
# green tick is being read as "the app was launched" — CI's macOS job, the release script.
# A skip is honest on a laptop and a lie in a release gate: "no simulator here" and "the app
# runs" produce the same exit 0, and 0.5.0 is what that costs. Nothing about the default
# path changes; the strictness is opt-in by the caller that needs it.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

note() { echo "check-ios-smoke: $1"; }

# One place decides what "cannot run here" means, so a skip path added later cannot forget
# to honour the strict flag — that is the whole failure this guard is for.
skip() {
  if [ "${MESH_SMOKE_REQUIRED:-}" = "1" ]; then
    note "FAIL: the smoke test was REQUIRED (MESH_SMOKE_REQUIRED=1) and DID NOT RUN."
    note "      $1"
    note "      The app was never launched, so nothing here says it can open. Do not read"
    note "      a green suite around this as evidence — that is the exact shape of 0.5.0,"
    note "      which shipped an app that died on every screen with a text field while"
    note "      every check in scripts/ passed."
    note "      Run this on a machine with a current Xcode and an iOS ${MIN_MAJOR}+ simulator."
    exit 1
  fi
  note "SKIP — $1"
  note "      This check is a release gate; run it somewhere with a current Xcode before shipping."
  note "      Set MESH_SMOKE_REQUIRED=1 to make this skip a failure instead."
  exit 0
}

MIN_MAJOR=26   # the app's deployment target; older runtimes cannot install it at all

command -v xcrun >/dev/null 2>&1 \
  || skip "xcrun is not on PATH — there is no Xcode on this machine to launch the app with."

# Prints "udid|name|iOS X.Y" for the newest usable iPhone simulator, or nothing.
sim=$(xcrun simctl list devices available -j 2>/dev/null | python3 -c '
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
            best = (version, dev["udid"], dev["name"])
print("%s|%s|iOS %s" % (best[1], best[2], ".".join(str(x) for x in best[0])) if best else "")
' 2>/dev/null || true)

if [ -z "$sim" ]; then
  skip "no available iOS ${MIN_MAJOR}+ iPhone simulator on this machine, so the app cannot be launched here."
fi

udid="${sim%%|*}"
rest="${sim#*|}"
SIM_NAME="${rest%%|*}"
SIM_RUNTIME="${rest#*|}"

note "running UI smoke tests on $SIM_NAME ($SIM_RUNTIME), simulator $udid"
xcodegen generate >/dev/null 2>&1 || { note "FAIL: xcodegen could not generate the project"; exit 1; }

log=$(mktemp -t mesh-ios-smoke)
if xcodebuild test \
     -project MeshWatch.xcodeproj -scheme "MeshWatch" \
     -destination "id=$udid" -derivedDataPath build/Smoke >"$log" 2>&1; then
  grep -E "Test Case .*passed" "$log" | sed 's/^/  /'
  # Name the device and the runtime in the PASS line, not only in the "running" line above.
  # A log tail that says only "OK" cannot answer "on what?" months later, and the answer
  # decides whether the pass covers the OS your testers are actually on.
  note "OK — the app launches, every tab renders, and a text field can appear"
  note "     ran on: $SIM_NAME · $SIM_RUNTIME · $udid"
  rm -f "$log"
  exit 0
fi

# Distinguish "the app died" from "the harness never started". A runner killed before
# it connects proves nothing at all, and reporting that as an app crash sends you
# hunting a bug that is not there — which is exactly the failure mode this whole check
# exists to end. Both still exit non-zero: a gate that proved nothing must not pass.
if grep -q "before establishing connection\|never finished bootstrapping" "$log"; then
  note "INCONCLUSIVE: the test runner was killed before it connected — nothing was proven about the app."
  note "             Usually another xcodebuild or simulator run was competing for the same device."
  note "             Re-run this alone; do not read it as a pass or a failure."
  note "full log: $log"
  exit 1
fi

note "FAIL: the app did not survive the smoke test"
grep -E "Test Case .*failed|error:|Crash|crashed" "$log" | head -20 | sed 's/^/  /'
note "full log: $log"
exit 1

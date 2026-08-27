#!/bin/sh
# release-testflight-asc.sh — build, upload and distribute the app to TestFlight.
#
#   sh scripts/release-testflight-asc.sh                 # build, upload, give it to INTERNAL testers
#   sh scripts/release-testflight-asc.sh --external      # …and to the public link, via Beta App Review
#   sh scripts/release-testflight-asc.sh --dry-run       # say what it would do, touch nothing
#
# Uses `asc`, which holds the App Store Connect credentials in the system keychain. That
# is not a preference: asc never prints the issuer id, and raw `xcodebuild` refuses
# `-authenticationKeyPath` without `-authenticationKeyIssuerID` beside it. Hence
# scripts/release-testflight.sh needs ASC_ISSUER_ID passed in and this one needs nothing.
#
# ---------------------------------------------------------------------------
# THE TRAP THIS SCRIPT EXISTS TO REMOVE
#
# `asc publish testflight --upload-only` stops after the upload. The build processes,
# goes VALID, and belongs to NO BETA GROUP — so nobody can install it. Not external
# testers, not internal ones, not you. Every list view shows it as a healthy build.
#
# That is exactly what happened on 2026-08-27: build 202608270920 uploaded and VALID,
# and the answer to "I cannot find the update in TestFlight" was that it was in zero
# groups. A build must be ADDED TO A GROUP, and the two kinds of group behave differently:
#
#   Internal group  — App Store Connect team members, up to 100. Installable the moment
#                     processing finishes. NO review. This is the fast path, and it is
#                     the one you want for yourself.
#   External group  — everyone holding the public link. Only after BETA APP REVIEW. A
#                     build sitting at externalBuildState READY_FOR_BETA_SUBMISSION has
#                     been uploaded, processed and validated, and is reaching nobody.
#
# So this script always does internal, and does external only when asked.
# ---------------------------------------------------------------------------
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP_ID="6803438426"
EXTERNAL=0
DRY=0
for a in "$@"; do
  case "$a" in
    --external) EXTERNAL=1 ;;
    --dry-run)  DRY=1 ;;
    *) echo "unknown argument: $a"; exit 1 ;;
  esac
done

command -v asc >/dev/null 2>&1 || { echo "FAIL: asc is not installed (brew install asc)"; exit 1; }
asc auth status >/dev/null 2>&1 || { echo "FAIL: asc is not authenticated — run: asc doctor"; exit 1; }

# The stable Xcode, never the beta. App Store Connect accepts a beta-built upload and then
# fails processing with 90534 "Unsupported SDK or Xcode version" — verified the hard way.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' project.yml | head -1)"
[ -n "$VERSION" ] || { echo "FAIL: no MARKETING_VERSION in project.yml"; exit 1; }
BUILD="$(date -u +%Y%m%d%H%M)"    # App Store Connect refuses a reused build number

echo "==> LeSearch Mesh $VERSION, build $BUILD"

# Going backwards is allowed by App Store Connect and punished by iOS: a tester on a
# HIGHER pre-release version reads this one as older and may be asked to delete and
# reinstall, which wipes the app's Keychain and un-pairs every machine they had.
# App Store Connect list endpoints do hang — measured 2026-08-27, this exact call sat
# for five minutes and a 60s probe returned zero bytes. Without a bound, one Apple-side
# hiccup wedges the whole release on a single line of output and looks like a hung build.
# POSIX rather than `timeout`, which is not on a stock macOS.
run_bounded() {
  _secs="$1"; shift
  _tmp="$(mktemp)"
  "$@" >"$_tmp" 2>/dev/null &
  _pid=$!
  _i=0
  while kill -0 "$_pid" 2>/dev/null && [ "$_i" -lt "$_secs" ]; do sleep 1; _i=$((_i + 1)); done
  if kill -0 "$_pid" 2>/dev/null; then
    kill "$_pid" 2>/dev/null; wait "$_pid" 2>/dev/null
    rm -f "$_tmp"; return 124
  fi
  wait "$_pid" 2>/dev/null
  cat "$_tmp"; rm -f "$_tmp"; return 0
}

PRERELEASE_JSON="$(run_bounded 90 asc testflight pre-release list --app "$APP_ID")" || {
  echo "FAIL: could not read the highest existing pre-release version within 90s."
  echo ""
  # Two very different causes look identical from here, and guessing wrong sends you to
  # Apple's status page for an hour over a dialog on your own screen. Ask.
  if curl -s -o /dev/null -m 15 "https://api.appstoreconnect.apple.com/v1/apps" 2>/dev/null; then
    echo "      App Store Connect itself IS reachable, so this is almost certainly local:"
    echo "      \`brew upgrade asc\` re-signs the binary, which invalidates the macOS"
    echo "      Keychain ACL on the stored API key. Every asc call that decrypts the key"
    echo "      then waits on a \"asc wants to use your confidential information\" dialog"
    echo "      that a non-interactive shell can never answer."
    if pgrep -qf SecurityAgent 2>/dev/null; then
      echo "      SecurityAgent is running right now — there is a dialog waiting for you."
    fi
    echo ""
    echo "      Fix, once: run \`asc auth status && asc apps list --limit 1\` in a real"
    echo "      terminal and choose ALWAYS ALLOW. Then re-run this script."
  else
    echo "      App Store Connect is not reachable from here either — this one really is"
    echo "      Apple. Try again later."
  fi
  echo ""
  echo "      That check is not cosmetic: uploading a version LOWER than one already on"
  echo "      TestFlight makes iOS treat this build as older, and testers get asked to"
  echo "      delete and reinstall — which wipes the app Keychain and un-pairs every"
  echo "      machine they had. Shipping blind is the one thing worth refusing here."
  echo ""
  echo "      Re-run when App Store Connect responds. If you have confirmed in the"
  echo "      TestFlight UI that $VERSION is not lower than what is already there:"
  echo "          MESH_SKIP_VERSION_CHECK=1 sh scripts/release-testflight-asc.sh"
  [ "${MESH_SKIP_VERSION_CHECK:-}" = "1" ] || exit 1
  echo "      MESH_SKIP_VERSION_CHECK=1 set — continuing without the check."
  PRERELEASE_JSON=""
}

HIGHEST="$(printf '%s' "$PRERELEASE_JSON" \
  | /usr/bin/python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit()
vs=[v["attributes"].get("version","") for v in d.get("data",[])]
def key(v):
    try: return tuple(int(x) for x in v.split("."))
    except Exception: return (0,)
print(max(vs, key=key) if vs else "")' 2>/dev/null || true)"
if [ -n "$HIGHEST" ] && [ "$HIGHEST" != "$VERSION" ]; then
  NEWER="$(printf '%s\n%s\n' "$HIGHEST" "$VERSION" | sort -V | tail -1)"
  if [ "$NEWER" = "$HIGHEST" ]; then
    echo "    WARNING: App Store Connect already holds $HIGHEST, which is newer than $VERSION."
    echo "             Testers on $HIGHEST may have to delete and reinstall to take $VERSION,"
    echo "             and that wipes the Keychain — every machine they paired is un-paired."
  fi
fi

if [ "$DRY" -eq 1 ]; then
  echo "==> --dry-run: would upload $VERSION ($BUILD), add it to the internal group,"
  [ "$EXTERNAL" -eq 1 ] && echo "    add it to the public group and submit for Beta App Review,"
  echo "    and set What to Test from CHANGELOG.md. Nothing was done."
  exit 0
fi

echo "==> regenerating the Xcode project"
xcodegen generate >/dev/null

echo "==> self-checks"
sh "$ROOT/scripts/check-all.sh" >/dev/null || { echo "FAIL: check-all.sh is red — not shipping"; exit 1; }
echo "    all self-checks passed"

# 0.5.0 passed every check above and still could not show a text field without dying.
# A build that has not been launched has not been tested, so launch it before shipping it.
echo "==> smoke test (launches the app on a simulator)"
sh "$ROOT/scripts/check-ios-smoke.sh" || { echo "FAIL: the app did not survive being launched — not shipping"; exit 1; }

echo "==> archive + upload (this takes a few minutes)"
OUT="$(asc publish testflight --app "$APP_ID" \
  --project MeshWatch.xcodeproj --scheme MeshWatch \
  --version "$VERSION" --build-number "$BUILD" --configuration Release \
  --upload-only --wait --output json 2>&1 | tail -1)"
BUILD_ID="$(printf '%s' "$OUT" | /usr/bin/python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("buildId",""))
except Exception: print("")' 2>/dev/null || true)"
[ -n "$BUILD_ID" ] || { echo "FAIL: upload did not return a build id:"; printf '%s\n' "$OUT" | tail -5; exit 1; }
echo "    uploaded: build id $BUILD_ID"

# Groups are looked up by name, not hardcoded: an id pasted into a script outlives the
# group it named, and then this silently distributes to nothing.
group_id() {
  asc testflight groups list --app "$APP_ID" 2>/dev/null | /usr/bin/python3 -c 'import sys,json
want=sys.argv[1]
try: d=json.load(sys.stdin)
except Exception: sys.exit()
for g in d.get("data",[]):
    a=g.get("attributes",{})
    if (a.get("name") or "").lower()==want.lower(): print(g.get("id")); break' "$1"
}

INTERNAL_ID="$(group_id Internal)"
[ -n "$INTERNAL_ID" ] || { echo "FAIL: no TestFlight group named 'Internal'"; exit 1; }
echo "==> adding to the internal group (installable immediately, no review)"
asc publish testflight --app "$APP_ID" --build "$BUILD_ID" --group "$INTERNAL_ID" --notify --output json >/dev/null
echo "    done — it will appear in your TestFlight once processing finishes"

# What to Test comes from CHANGELOG's Unreleased block, which is written as each slice
# ships. One description of the release, not a second one that drifts from the first.
NOTES="$(mktemp)"
/usr/bin/python3 - "$ROOT/CHANGELOG.md" "$VERSION" > "$NOTES" <<'PY'
import re, sys, pathlib
s = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r'^## \[Unreleased\]\s*$(.*?)^## \[', s, re.S | re.M)
items = re.findall(r'^- \*\*(.+?)\*\*', m.group(1), re.M) if m else []
print("LeSearch Mesh %s\n" % sys.argv[2])
print("FIRST: update the daemon on each machine too, or most of this does nothing:\n")
print("    mesh upgrade\n")
if items:
    print("NEW")
    for i in items[:25]:
        print("- " + i.rstrip("."))
PY
asc builds test-notes update --build-id "$BUILD_ID" --locale en-US --whats-new "$(cat "$NOTES")" >/dev/null 2>&1 \
  || asc builds test-notes create --build-id "$BUILD_ID" --locale en-US --whats-new "$(cat "$NOTES")" >/dev/null 2>&1 \
  || echo "    (could not set What to Test — set it in App Store Connect)"
rm -f "$NOTES"
echo "    What to Test set from CHANGELOG"

if [ "$EXTERNAL" -eq 1 ]; then
  BETA_ID="$(group_id Beta)"
  [ -n "$BETA_ID" ] || { echo "FAIL: no TestFlight group named 'Beta'"; exit 1; }
  echo "==> adding to the public group and submitting for Beta App Review"
  asc publish testflight --app "$APP_ID" --build "$BUILD_ID" --group "$BETA_ID" --notify --output json >/dev/null
  asc testflight review submit --build-id "$BUILD_ID" --confirm >/dev/null
  echo "    submitted — usually hours. Expect questions: the app injects keystrokes and"
  echo "    sets NSAllowsArbitraryLoads. The reviewer notes on file already explain both."
fi

echo
echo "==> state now"
asc testflight distribution view --build-id "$BUILD_ID" 2>/dev/null | /usr/bin/python3 -c 'import sys,json
a=json.load(sys.stdin)["data"][0]["attributes"]
print("    internal:", a.get("internalBuildState"))
print("    external:", a.get("externalBuildState"))' 2>/dev/null || true
echo "    build id: $BUILD_ID"
echo "    public link: https://testflight.apple.com/join/pVYPTxc7"

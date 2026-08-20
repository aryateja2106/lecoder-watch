#!/bin/sh
# Archive MeshWatch (iOS + embedded watch app) and upload it to TestFlight.
#
#   ASC_KEY_ID=Y4MR7X24UL ASC_ISSUER_ID=<uuid> sh scripts/release-testflight.sh
#
# The key must be at ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8 —
# xcodebuild and altool both look there by convention. The issuer id is the UUID on
# App Store Connect › Users and Access › Integrations › App Store Connect API.
#
# Why TestFlight rather than sideloading: a development-signed build has to verify its
# certificate with Apple on every fresh install, which is the "Unable to Verify App"
# dead end, and each re-sign resets the app's privacy grants (Local Network, and with
# it the whole tailnet). TestFlight builds are Apple-signed — none of that applies, and
# other people can install them.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${ASC_KEY_ID:?set ASC_KEY_ID (e.g. Y4MR7X24UL)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (uuid from App Store Connect > Integrations)}"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
[ -f "$KEY" ] || { echo "FAIL: no key at $KEY"; exit 1; }

# Xcode 27 beta: the devices run iOS/watchOS 27 and 26.x cannot build for them.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

BUILD="$(date +%Y%m%d%H%M)"        # monotonic and obvious; App Store Connect rejects reuse
ARCHIVE="$ROOT/build/MeshWatch-$BUILD.xcarchive"
EXPORT="$ROOT/build/export-$BUILD"

echo "==> regenerating project"
xcodegen generate >/dev/null

echo "==> self-checks"
sh "$ROOT/scripts/check-all.sh"

echo "==> archiving (build $BUILD)"
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  archive

cat > "$ROOT/build/ExportOptions-$BUILD.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>B5B87F7AXF</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "==> exporting and uploading to TestFlight"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/build/ExportOptions-$BUILD.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo
echo "Uploaded build $BUILD."
echo "It appears in App Store Connect > TestFlight after processing (usually 5-15 min)."
echo "Internal testers (your team) can install immediately; external testers need a"
echo "one-time Beta App Review."

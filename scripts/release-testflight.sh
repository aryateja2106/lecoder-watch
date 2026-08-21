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

# STABLE Xcode, not the beta. App Store Connect accepts a beta-built upload and then
# fails processing with 90534 "Unsupported SDK or Xcode version" — verified. The beta
# is only for installing onto devices running a beta OS.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

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
# Two credential paths, tried in order. The API key can archive but NOT mint the
# Apple Distribution certificate unless its App Store Connect role has certificate
# access ("Cloud signing permission error" + "No signing certificate iOS
# Distribution" — hit for real on 2026-08-21). Xcode's logged-in account session
# holds account-holder power, so it succeeds where the key is refused. Fix the key's
# role in ASC > Users and Access > Integrations to make the first path self-contained.
if ! xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/build/ExportOptions-$BUILD.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"; then
  echo "==> API-key export refused (cloud signing) — retrying with Xcode's account session"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT" \
    -exportOptionsPlist "$ROOT/build/ExportOptions-$BUILD.plist" \
    -allowProvisioningUpdates
fi

echo
echo "Uploaded build $BUILD."
echo "It appears in App Store Connect > TestFlight after processing (usually 5-15 min)."
echo "Internal testers (your team) can install immediately; external testers need a"
echo "one-time Beta App Review."

#!/bin/sh
# check-brand.sh — the product reads "LeSearch AI" everywhere a person sees it, and the identifiers
# Apple, the Keychain, the App Group and printed pairing QR codes are keyed by stay byte-identical.
#
# 2026-09-21 rename (MeshWatch 08-28 → LeSearch Mesh 09-04 → LeSearch AI 09-21). Frozen: bundle ids
# com.lecoder.*, the meshwatch:// scheme, target/product names, group.com.lecoder.meshwatch, the
# MeshGlance widget kind, SessionActivityAttributes, ai.lesearch service labels. Also pins the app
# MARKETING_VERSION to the daemon VERSION (publish-plan T02).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() {
  echo "check-brand: FAIL — $*" >&2
  exit 1
}

# 1. Frozen-id guard
grep -qF 'com.lecoder.meshwatch' project.yml || die "Missing com.lecoder.meshwatch in project.yml"
grep -qF 'com.lecoder.meshwatch' Generated/iOS-Info.plist || die "Missing com.lecoder.meshwatch in Generated/iOS-Info.plist"
grep -qF 'com.lecoder.meshdesktop' project.yml || die "Missing com.lecoder.meshdesktop in project.yml"
grep -qF 'com.lecoder.meshwatch.watchkitapp' project.yml || die "Missing com.lecoder.meshwatch.watchkitapp in project.yml"
grep -qF 'com.lecoder.meshwatch.watchkitapp.glance' project.yml || die "Missing com.lecoder.meshwatch.watchkitapp.glance in project.yml"
grep -qF 'com.lecoder.meshwatch.widgets' project.yml || die "Missing com.lecoder.meshwatch.widgets in project.yml"
grep -qF 'meshwatch://' Shared/Models.swift || die "Missing meshwatch:// in Shared/Models.swift"
grep -qF 'group.com.lecoder.meshwatch' Watch/MeshWatchWatch.entitlements || die "Missing group.com.lecoder.meshwatch in Watch/MeshWatchWatch.entitlements"
grep -qE 'CFBundleURLName.*com.lecoder.meshwatch' project.yml || die "Missing CFBundleURLName com.lecoder.meshwatch in project.yml"
grep -qF 'PRODUCT_NAME: MeshWatch' project.yml || die "Missing PRODUCT_NAME: MeshWatch in project.yml"
grep -qF 'ai.lesearch' install/install.sh || die "Missing ai.lesearch.meshd in install/install.sh"
grep -qF '"MeshGlance"' WatchWidgets/WatchGlanceWidget.swift || die "Missing \"MeshGlance\" in WatchWidgets/WatchGlanceWidget.swift"
grep -qF 'SessionActivityAttributes' Shared/SessionActivity.swift || die "Missing SessionActivityAttributes in Shared/SessionActivity.swift"

# 2. Display-name guard
for plist in project.yml Generated/iOS-Info.plist Generated/Watch-Info.plist Generated/Desktop-Info.plist MeshWatchWidgets/Info.plist WatchWidgets/Info.plist; do
  if [ "$plist" = project.yml ]; then
    bad_lines=$(grep 'CFBundleDisplayName:' "$plist" | grep -vE 'LeSearch AI( Sessions)?' || true)
    if [ -n "$bad_lines" ]; then
      die "Invalid CFBundleDisplayName in $plist: $bad_lines"
    fi
  else
    if grep -q '<key>CFBundleDisplayName</key>' "$plist"; then
      val_line=$(grep -A1 '<key>CFBundleDisplayName</key>' "$plist" | tail -n1)
      if ! echo "$val_line" | grep -qE 'LeSearch AI( Sessions)?'; then
        die "Invalid CFBundleDisplayName in $plist: $val_line"
      fi
    fi
  fi
done

# 3. No user-visible legacy name
legacy=$(grep -rnE '"[^"]*(MeshWatch|LeSearch Mesh)[^"]*"' iOS Watch Shared MeshDesktop MeshWatchWidgets WatchWidgets || true)
if [ -n "$legacy" ]; then
  die "Found user-visible legacy names in Swift files: $legacy"
fi

grep -q "LeSearch AI" web/index.html || die "Missing LeSearch AI in web/index.html"
head -n 1 README.md | grep -q "LeSearch AI" || die "Missing LeSearch AI in README.md first line"
if grep -q "LeSearch Mesh" install/payload/bin/mesh; then
  die "HELP banner in bin/mesh still says LeSearch Mesh"
fi

# 4. Version guard
PROJ_VER=$(grep -E 'MARKETING_VERSION:' project.yml | head -n 1 | awk -F '"' '{print $2}')
DAEMON_VER=$(grep -E 'const VERSION = ' install/payload/meshd/server.ts | head -n 1 | awk -F '"' '{print $2}')
if [ "$PROJ_VER" != "$DAEMON_VER" ]; then
  die "Version mismatch: project.yml has $PROJ_VER but server.ts has $DAEMON_VER"
fi

echo "check-brand: OK"

#!/bin/sh
# App icon audit: catches the specific things that make App Store Connect reject
# a build — a missing 1024x1024 marketing icon, a Contents.json entry pointing at
# a file that doesn't exist, and an alpha channel on the iOS marketing icon (ASC
# rejects iOS icons with alpha). Deliberately lazy: no size-completeness nagging,
# no idiom bean-counting — just the things that actually bounce a submission.
#
# macOS-only (needs sips). SKIPs cleanly everywhere else so CI on Linux passes.
set -eu

if ! command -v sips >/dev/null 2>&1; then
  echo "SKIP: sips not available (not macOS)"
  exit 0
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
checked=0

# Which AppIcon set names does project.yml actually wire up? Only audit those —
# an appiconset nobody references can't break a build.
names="$(grep -o 'ASSETCATALOG_COMPILER_APPICON_NAME:[[:space:]]*[A-Za-z0-9_]*' project.yml \
  | sed -E 's/.*:[[:space:]]*//' | sort -u)"

if [ -z "$names" ]; then
  echo "SKIP: no ASSETCATALOG_COMPILER_APPICON_NAME entries in project.yml"
  exit 0
fi

for name in $names; do
  for set_dir in $(find . \( -path "*/build/*" -o -path "*/.asc/*" -o -path "*/DerivedData/*" -o -path "*/node_modules/*" \) -prune \
      -o -type d -name "${name}.appiconset" -print); do
    checked=$((checked + 1))
    contents="$set_dir/Contents.json"

    if [ ! -f "$contents" ]; then
      echo "FAIL: $set_dir has no Contents.json"
      fail=1
      continue
    fi

    # Every file the catalog references must actually be on disk.
    for fname in $(grep -o '"filename"[[:space:]]*:[[:space:]]*"[^"]*"' "$contents" \
        | sed -E 's/.*"([^"]+)"$/\1/'); do
      if [ ! -f "$set_dir/$fname" ]; then
        echo "FAIL: $contents references missing file '$fname'"
        fail=1
      fi
    done

    # The 1024x1024 marketing icon is non-negotiable for an App Store submission.
    if ! grep -q '"size"[[:space:]]*:[[:space:]]*"1024x1024"' "$contents"; then
      echo "FAIL: $set_dir is missing a 1024x1024 marketing icon entry"
      fail=1
      continue
    fi

    # Find the filename attached to the iOS 1024 entry specifically (single-size
    # format uses platform:ios; legacy multi-size format uses idiom ios-marketing)
    # and make sure that PNG has no alpha channel.
    ios1024_file="$(awk '
      BEGIN { RS = "{" }
      /"size"[ \t]*:[ \t]*"1024x1024"/ && (/"platform"[ \t]*:[ \t]*"ios"/ || /"ios-marketing"/) {
        n = split($0, lines, "\n")
        for (i = 1; i <= n; i++) {
          if (lines[i] ~ /"filename"/) {
            line = lines[i]
            sub(/.*"filename"[ \t]*:[ \t]*"/, "", line)
            sub(/".*/, "", line)
            print line
            exit
          }
        }
      }
    ' "$contents")"

    if [ -n "$ios1024_file" ] && [ -f "$set_dir/$ios1024_file" ]; then
      alpha="$(sips -g hasAlpha "$set_dir/$ios1024_file" 2>/dev/null | awk '/hasAlpha/ {print $2}')"
      if [ "$alpha" = "yes" ]; then
        echo "FAIL: $set_dir/$ios1024_file has an alpha channel (App Store rejects iOS icons with alpha)"
        fail=1
      fi
    fi
  done
done

if [ "$checked" -eq 0 ]; then
  echo "SKIP: no .appiconset directories found for: $names"
  exit 0
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "check-app-icons: OK ($checked appicon set(s) checked)"

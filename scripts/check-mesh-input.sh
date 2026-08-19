#!/bin/sh
# Self-check for Mac remote control.
#  1. bin/mesh-input.swift still compiles and answers --check.
#  2. every key, media key and system action the watch sends is one the Mac knows.
# (2) is the silent failure mode: an unknown name is a no-op, so the button just does
# nothing on the Mac with no error anywhere.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/install/payload/bin/mesh-input.swift"
MESHD="$ROOT/install/payload/meshd/input.ts"
VIEW="$ROOT/Watch/RemoteView.swift"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for f in "$SRC" "$MESHD" "$VIEW"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; exit 1; }
done

/usr/bin/swiftc -O -o "$TMP/mesh-input" "$SRC" || { echo "FAIL: mesh-input.swift does not compile"; exit 1; }
"$TMP/mesh-input" --check | grep -q '"trusted"' || { echo "FAIL: --check did not report trust state"; exit 1; }

names() { sed -n 's/.*"\([a-z0-9]*\)"[[:space:]]*:.*/\1/p' | sort -u; }

# --- keyboard keys ---
awk '/^let KEYCODES/,/^\]/' "$SRC" | tr ',' '\n' | names > "$TMP/known-keys"
{
  sed -n 's/.*\.key("\([a-z0-9]*\)".*/\1/p;s/.*keyButton("\([a-z0-9]*\)".*/\1/p;s/.*("[^"]*", *"\([a-z0-9]*\)", *\[.*/\1/p' "$VIEW"
  # every literal in the on-screen keyboard grids
  awk '/^let (KEYBOARD|FUNCTION)_ROWS/,/^\]/' "$VIEW" | tr ',' '\n' | sed -n 's/.*"\([a-z0-9]*\)".*/\1/p'
} | sort -u > "$TMP/used-keys"

# --- media keys ---
awk '/^let MEDIA_KEYS/,/^\]/' "$SRC" | tr ',' '\n' | names > "$TMP/known-media"
sed -n 's/.*mediaButton("\([a-z0-9]*\)".*/\1/p;s/.*\.media("\([a-z0-9]*\)".*/\1/p' "$VIEW" | sort -u > "$TMP/used-media"

# --- window placements (the helper's switch is the source of truth) ---
awk '/^func placeWindow/,/^}/' "$SRC" | sed -n 's/.*case "\([a-z]*\)".*/\1/p' | sort -u > "$TMP/known-window"
sed -n 's/.*windowButton("\([a-z]*\)".*/\1/p;s/.*\.window("\([a-z]*\)").*/\1/p' "$VIEW" | sort -u > "$TMP/used-window"

# --- system actions (allowlisted in meshd, not the helper) ---
awk '/^const SYSTEM_ACTIONS/,/^};/' "$MESHD" | sed -n 's/^  \([a-z]*\):.*/\1/p' | sort -u > "$TMP/known-system"
sed -n 's/.*\.system("\([a-z]*\)").*/\1/p' "$VIEW" | sort -u > "$TMP/used-system"

fail=0
for kind in keys media window system; do
  missing="$(comm -23 "$TMP/used-$kind" "$TMP/known-$kind")"
  if [ -n "$missing" ]; then
    echo "FAIL: watch sends $kind the Mac cannot map:"
    echo "$missing"
    fail=1
  fi
done
[ "$fail" -eq 0 ] || exit 1

printf 'OK: mesh-input compiles; %s keys, %s media, %s window, %s system all mapped\n' \
  "$(wc -l < "$TMP/used-keys" | tr -d ' ')" \
  "$(wc -l < "$TMP/used-media" | tr -d ' ')" \
  "$(wc -l < "$TMP/used-window" | tr -d ' ')" \
  "$(wc -l < "$TMP/used-system" | tr -d ' ')"

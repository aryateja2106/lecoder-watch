#!/bin/sh
# Self-check for Mac remote control.
#  1. bin/mesh-input.swift still compiles and answers --check.
#  2. every key name the watch sends exists in the helper's KEYCODES table.
# (2) is the silent failure mode: a key the helper doesn't know is a no-op, so the
# button just does nothing on the Mac with no error anywhere.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/install/payload/bin/mesh-input.swift"
VIEW="$ROOT/Watch/RemoteView.swift"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -f "$SRC" ] || { echo "FAIL: missing $SRC"; exit 1; }
[ -f "$VIEW" ] || { echo "FAIL: missing $VIEW"; exit 1; }

/usr/bin/swiftc -O -o "$TMP/mesh-input" "$SRC" || { echo "FAIL: mesh-input.swift does not compile"; exit 1; }
"$TMP/mesh-input" --check | grep -q '"trusted"' || { echo "FAIL: --check did not report trust state"; exit 1; }

# Key names known to the helper.
awk '/^let KEYCODES/,/^\]/' "$SRC" | tr ',' '\n' | sed -n 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/p' | sort -u > "$TMP/known"

# Key names the watch sends: .key("x"), .key("x", [...]), keyButton("x", ...), ("Name", "x", [mods]).
sed -n 's/.*\.key("\([a-z0-9]*\)".*/\1/p;s/.*keyButton("\([a-z0-9]*\)".*/\1/p;s/.*("[^"]*", *"\([a-z0-9]*\)", *\[.*/\1/p' "$VIEW" \
  | sort -u > "$TMP/used"

missing="$(comm -23 "$TMP/used" "$TMP/known")"
[ -z "$missing" ] || { echo "FAIL: watch sends keys the helper cannot map:"; echo "$missing"; exit 1; }

echo "OK: mesh-input compiles; $(wc -l < "$TMP/used" | tr -d ' ') watch key names all mapped"

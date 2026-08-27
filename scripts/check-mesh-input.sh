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
# --- event pacing ---
# The helper used to usleep(1200) after EVERY posted event, cursor moves included. At
# MAX_EVENTS=200 that is 240ms of pure sleep in one batch, which was most of "the mouse
# is slow and laggy" — while still being far too short to stop the WindowServer dropping
# a mouseUp posted right behind its mouseDown, which is why clicks landed only sometimes.
# Both halves of that regression are cheap to reintroduce and impossible to see in a
# build, so both are asserted here.
if grep -qE '^\s*usleep\([0-9_]+\)\s*$' "$SRC"; then
  echo "FAIL: mesh-input posts with an unconditional usleep again — that paces cursor moves too"
  fail=1
fi
grep -q 'func post(_ event: CGEvent?, settle: UInt32 = 0)' "$SRC" \
  || { echo "FAIL: post() no longer takes a per-event settle defaulting to none"; fail=1; }

# A click needs a real fence between its down and its up, not a token one.
fence="$(sed -n 's/^let clickFence: UInt32 = \([0-9_]*\).*/\1/p' "$SRC" | tr -d '_')"
[ -n "$fence" ] || { echo "FAIL: clickFence is gone — a click has nothing separating down from up"; fail=1; }
if [ -n "$fence" ] && [ "$fence" -lt 20000 ]; then
  echo "FAIL: clickFence is ${fence}us; under ~20ms the WindowServer drops the mouseUp"
  fail=1
fi
awk '/func click\(/,/^}/' "$SRC" | grep -q 'settle: clickFence' \
  || { echo "FAIL: click() does not use clickFence"; fail=1; }

# Position updates must NOT pace — that is the whole latency win.
awk '/func moveCursor\(/,/^}/' "$SRC" | grep -q 'settle:' \
  && { echo "FAIL: moveCursor pauses after each move; that is the 240ms batch back"; fail=1; }
awk '/func scroll\(/,/^}/' "$SRC" | grep -q 'settle:' \
  && { echo "FAIL: scroll pauses after each event; scrolls supersede and need no fence"; fail=1; }

# Keys must still pace: half a dropped down/up pair is a stuck modifier.
awk '/func pressKey\(|func typeText\(/,/^}/' "$SRC" | grep -q 'settle: keyFence' \
  || { echo "FAIL: key/text events no longer settle — a dropped pair sticks a modifier"; fail=1; }

[ "$fail" -eq 0 ] || exit 1

printf 'OK: mesh-input compiles; %s keys, %s media, %s window, %s system all mapped\n' \
  "$(wc -l < "$TMP/used-keys" | tr -d ' ')" \
  "$(wc -l < "$TMP/used-media" | tr -d ' ')" \
  "$(wc -l < "$TMP/used-window" | tr -d ' ')" \
  "$(wc -l < "$TMP/used-system" | tr -d ' ')"

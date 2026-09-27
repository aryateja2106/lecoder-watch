#!/bin/sh
# The remote screen's trackpad turned every pointer move into a drag on a real phone, and
# no simulator run could see it: a synthetic swipe is over in well under the long press's
# 0.35 s, while a human aiming a pointer rests a finger for longer than that. With
# `allowableMovement` at .greatestFiniteMagnitude the long press could never fail, so the
# mouse button went down under a finger that was already moving and the Mac spent the
# session selecting text (reported 2026-09-22 from the iPhone).
#
# Two invariants keep "move" and "drag" apart. Both are one line, both are easy to delete
# by accident, and neither shows up in a build:
#   1. the long press must fail once the finger has travelled  (allowableMovement is finite)
#   2. a hold that arrives after the pan has already moved must not press the button
# The third assertion is the one that made the drag work in the first place, so that the
# fix for one defect cannot quietly reintroduce the other.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/iOS/RemoteScreenView.swift"
fail=0
note() { echo "check-trackpad-drag: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
[ -f "$SRC" ] || { echo "FAIL: missing $SRC"; exit 1; }

if grep -q 'hold.allowableMovement = .greatestFiniteMagnitude' "$SRC"; then
  bad "the long press can never fail — every pointer move becomes a drag again"
elif grep -qE 'hold\.allowableMovement = [0-9]+' "$SRC"; then
  note "the long press fails once the finger travels ($(grep -oE 'hold\.allowableMovement = [0-9]+' "$SRC" | head -1 | awk '{print $3}') pt)"
else
  bad "hold.allowableMovement is not set at all — UIKit's 10 pt default is close, but say it"
fi

grep -q 'guard panTravel <' "$SRC" \
  || bad "a hold that arrives mid-move can still press the button (no panTravel guard)"
grep -q 'panTravel += ' "$SRC" \
  || bad "nothing accumulates pan travel, so the guard above can never be true"
grep -q 'if g.state == .began { lastPan = .zero; panTravel = 0 }' "$SRC" \
  || bad "pan travel is not reset when a new gesture begins — the guard would latch after one drag"

# The drag itself must survive: press, hold still, then move.
grep -q 'dragging = true' "$SRC" || bad "the hold no longer starts a drag — press-and-hold-then-move is dead"
grep -q 'parent.onDragEnded()' "$SRC" || bad "nothing releases the button, so a drag would stick"

[ "$fail" = 0 ] && echo "check-trackpad-drag: OK" || exit 1

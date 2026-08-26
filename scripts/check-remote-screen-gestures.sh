#!/bin/sh
# The phone's remote-screen surface, checked against the two things it talks to: the
# host input backends, and its own preference.
#
# Every failure below has already shipped here at least once, and none of them is
# visible to a build: the wrong literal compiles, renders, and sends — the host just
# drops it. "center" is a real example. bin/mesh-input's mouseButton() accepts it as a
# synonym for middle, so a middle click worked on the Mac and vanished on Linux, whose
# BUTTONS map has left/middle/right and silently returns nothing for anything else.
#
# So this does not assert that a string appears somewhere. It extracts the literals the
# phone actually sends and requires BOTH backends to know each one, and it recomputes
# the shipped scroll direction from the preference's default rather than trusting a
# comment about it.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCREEN="$ROOT/iOS/RemoteScreenView.swift"
MAC="$ROOT/install/payload/bin/mesh-input.swift"
LNX="$ROOT/install/payload/meshd/input-linux.ts"
fail=0

note() { echo "check-remote-screen-gestures: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

for f in "$SCREEN" "$MAC" "$LNX"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; exit 1; }
done

# ---- what each backend understands ----
mac_buttons="left $(sed -n '/func mouseButton/,/^}/p' "$MAC" | grep -oE '"[a-z]+"' | tr -d '"' | tr '\n' ' ')"
lnx_buttons=$(sed -n 's/^const BUTTONS.*= {\(.*\)};.*/\1/p' "$LNX" | grep -oE '[a-z]+:' | tr -d ':' | tr '\n' ' ')
mac_keys=$(sed -n '/^let KEYCODES/,/^]/p' "$MAC" | grep -oE '"[^"]+": *-?[0-9]+' | sed -E 's/": *-?[0-9]+//; s/^"//' | tr '\n' ' ')
lnx_keys=$(sed -n '/^const KEYSYMS/,/^};/p' "$LNX" | grep -oE '[a-zA-Z0-9]+:' | tr -d ':' | tr '\n' ' ')
mac_mods=$(sed -n '/^let MODIFIERS/,/^]/p' "$MAC" | grep -oE '"[a-z]+": *\(' | sed -E 's/": *\(//; s/^"//' | tr '\n' ' ')
lnx_mods=$(sed -n '/^const MODS/,/^};/p' "$LNX" | grep -oE '[a-z]+:' | tr -d ':' | tr '\n' ' ')

# An empty extraction would make every assertion below pass vacuously — the exact way a
# check goes green while the feature is dead. Refuse instead.
for pair in "mac_buttons=$mac_buttons" "lnx_buttons=$lnx_buttons" "mac_keys=$mac_keys" \
            "lnx_keys=$lnx_keys" "mac_mods=$mac_mods" "lnx_mods=$lnx_mods"; do
  case "$pair" in *=|*=" ") echo "FAIL: extracted no ${pair%%=*} — the host maps moved, fix this check"; exit 1 ;; esac
done

has() { # has <needle> <haystack…>
  needle="$1"; shift
  for w in $*; do [ "$w" = "$needle" ] && return 0; done
  return 1
}

# ---- 1. every mouse button the screen sends is understood by both hosts ----
buttons=$(grep -oE 'click\("[a-z]+"' "$SCREEN" | sed -E 's/click\("//; s/"//' | sort -u | tr '\n' ' ')
[ -n "$buttons" ] || bad "the remote screen sends no named mouse button at all"
for b in $buttons; do
  has "$b" "$mac_buttons" || bad "the screen sends click(\"$b\") but bin/mesh-input's mouseButton() falls through to left"
  has "$b" "$lnx_buttons" || bad "the screen sends click(\"$b\") but input-linux.ts BUTTONS has no \"$b\" — it drops the click in silence (this is what \"center\" did)"
done
note "mouse buttons [$buttons] are understood by both the Mac helper and xdotool"

# ---- 2. gesture -> wire, the mapping that has shipped dead here before ----
# Number of fingers is decided in makeUIView; which button that becomes is decided ~200
# lines away at the call site. Nothing but this connects the two.
grep -q 'threeTap.numberOfTouchesRequired = 3' "$SCREEN" || bad "no three-touch recognizer — the middle click is unreachable"
grep -q 'twoTap.numberOfTouchesRequired = 2' "$SCREEN" || bad "no two-touch recognizer — the right click is unreachable"
grep -q 'twoTap.require(toFail: threeTap)' "$SCREEN" \
  || bad "twoTap does not require threeTap to fail — a three-finger tap middle-clicks AND right-clicks"
grep -q 'onSecondaryTap: { remote.click("right") }' "$SCREEN" \
  || bad "the two-finger tap no longer maps to click(\"right\") — check it is not gated behind a drag mode again"
grep -q 'onTertiaryTap: { remote.click("middle") }' "$SCREEN" \
  || bad "the three-finger tap no longer maps to click(\"middle\")"
note "two fingers -> right, three fingers -> middle, three beats two"

# ---- 3. press-and-hold-then-drag needs BOTH recognizers on the delegate ----
# The long press and the one-finger pan must run together: without the delegate the
# press wins and cancels the pan, so the button goes down and nothing ever moves — no
# dragging a window, no drag-selecting text, no moving a slider.
grep -q '^ *pan.delegate = c' "$SCREEN" || bad "pan has no delegate — the long press cancels it and drags never move"
grep -q '^ *hold.delegate = c' "$SCREEN" || bad "hold has no delegate — the long press cancels the pan and drags never move"
grep -q 'shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }' "$SCREEN" \
  || bad "the delegate no longer allows simultaneous recognition — assigning it achieves nothing"
note "pan and hold both run through a delegate that allows simultaneous recognition"

# ---- 4. every key and modifier the key bar sends exists on both hosts ----
specials=$(sed -n '/private static let specials/,/^ *$/p' "$SCREEN")
chords=$(sed -n '/private static let chords/,/^ *$/p' "$SCREEN")
plain_keys=$(printf '%s' "$specials" | grep -oE '\("[^"]*", "[^"]+"' | sed -E 's/.*, "//; s/"//' | sort -u | tr '\n' ' ')
keys="$plain_keys$(printf '%s' "$chords" | grep -oE '\("[^"]*", "[^"]+"' | sed -E 's/.*, "//; s/"//' | sort -u | tr '\n' ' ')"
mods=$(printf '%s\n%s' "$specials" "$chords" | grep -oE '\["[a-z", ]+\]' | grep -oE '"[a-z]+"' | tr -d '"'
       grep -oE 'private static let modifiers = .*' "$SCREEN" | grep -oE ', "[a-z]+"\)' | sed -E 's/, "//; s/"\)//')
mods=$(printf '%s' "$mods" | sort -u | tr '\n' ' ')
# The *plain* key, not the chord: sticky modifiers are the general answer (tap ⌥, tap
# space), and a bar that only offers pre-baked chords cannot compose the next one.
has space "$plain_keys" || bad "the key bar has no plain space key — ⌥Space (Raycast) and ⌘Space are unsendable from the phone, and this bar is the only surface reaching the OS input path instead of a pane's stdin"
printf '%s' "$chords" | grep -q '"space", \["option"\]' \
  || bad "no one-tap ⌥Space chord — reachable via sticky ⌥, but nothing labels it"
for k in $keys; do
  has "$k" "$mac_keys" || bad "the key bar sends \"$k\" but bin/mesh-input's KEYCODES has no such key — it returns early and nothing is typed"
  has "$k" "$lnx_keys" || bad "the key bar sends \"$k\" but input-linux.ts KEYSYMS has no such key — keysym() returns null and the event is skipped"
done
for m in $mods; do
  has "$m" "$mac_mods" || bad "modifier \"$m\" is not in bin/mesh-input's MODIFIERS — compactMap drops it and the chord fires bare"
  has "$m" "$lnx_mods" || bad "modifier \"$m\" is not in input-linux.ts MODS — it is filtered out and the chord fires bare"
done
note "key bar keys [$keys] and modifiers [$mods] exist on both hosts"

# ---- 5. the scroll preference's default reproduces the shipped direction ----
# Recomputed, not asserted: read which branch the stored default selects, and require
# that branch to be the -1 the app shipped with before the preference existed. Nobody's
# muscle memory may change because a setting appeared.
dflt=$(grep -oE 'forKey: naturalScrollKey\) as\? Bool \?\? (true|false)' "$SCREEN" | grep -oE '(true|false)$')
tern=$(grep -oE 'naturalScrolling \? -?[0-9]+ : -?[0-9]+' "$SCREEN")
[ -n "$dflt" ] || bad "no UserDefaults-backed default for naturalScrolling — the preference does not survive the app"
[ -n "$tern" ] || bad "scroll() no longer picks its sign from naturalScrolling"
if [ -n "$dflt" ] && [ -n "$tern" ]; then
  on_true=$(printf '%s' "$tern" | sed -E 's/.*\? *(-?[0-9]+) *:.*/\1/')
  on_false=$(printf '%s' "$tern" | sed -E 's/.*: *(-?[0-9]+).*/\1/')
  if [ "$dflt" = "true" ]; then sign="$on_true"; else sign="$on_false"; fi
  [ "$sign" = "-1" ] \
    || bad "a fresh install now scrolls with sign $sign; it shipped as -1, so every existing user's scroll direction just flipped"
  grep -q 'sign \* Double(delta.width)' "$SCREEN" && grep -q 'sign \* Double(delta.height)' "$SCREEN" \
    || bad "the computed sign is not applied to both scroll axes"
  [ "$fail" = "0" ] && note "default $dflt selects sign $sign — identical to the direction shipped before the preference existed"
fi

# ---- 6. the preference is reachable ----
# A preference nothing can set is the same as no preference. This repo has shipped that
# exact shape before, which is why it is asserted rather than assumed.
grep -q 'isOn: \$remote.naturalScrolling' "$SCREEN" \
  || bad "nothing in the UI is bound to naturalScrolling — the preference exists but no user can change it"
note "natural scrolling has a control bound to it"

# ---- 7. the idle timer is held and released in matching pairs ----
# The one screen whose entire job is being looked at must not dim; a phone that never
# sleeps again after you leave it is the worse bug.
on=$(grep -c 'isIdleTimerDisabled = true' "$SCREEN" || true)
off=$(grep -c 'isIdleTimerDisabled = false' "$SCREEN" || true)
if [ "$on" = "0" ]; then
  bad "the remote screen never holds the idle timer — it dims while you watch the Mac"
elif [ "$on" != "$off" ]; then
  bad "RemoteScreenView holds the idle timer $on time(s) and releases it $off — the phone would stop sleeping"
else
  note "the idle timer is held and released in $on matching pair(s)"
fi

if [ "$fail" = "0" ]; then
  echo "check-remote-screen-gestures: OK"
else
  echo "check-remote-screen-gestures: FAILED"
  exit 1
fi

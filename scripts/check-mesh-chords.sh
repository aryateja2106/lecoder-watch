#!/bin/sh
# Self-check for simultaneous modifier chords — issue #109.
#
# A chord is not "a key with some flags on it". It is a sequence: every modifier down,
# the key down and up while they are held, the modifiers up again in reverse. Nothing in
# a build can see whether that order is right, and nothing in a build can see a modifier
# quietly falling out of it — which is the failure this file exists for. A ⌘⇧4 that has
# lost its ⌘ is not a failed screenshot; it is a "$" typed into whatever had focus.
#
# So this runs the real pipeline end to end and reads the result:
#
#   the NDJSON the phone sends  ->  meshd's normalizeChords  ->  what mesh-input posts
#
# and nothing is injected into this Mac. mesh-input has a --dry-run mode that prints the
# events it would post and posts none of them, which is the only way to assert a chord
# on a machine somebody is sitting at.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/install/payload/bin/mesh-input.swift"
MESHD="$ROOT/install/payload/meshd/input.ts"
VIEW="$ROOT/iOS/RemoteScreenView.swift"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

for f in "$SRC" "$MESHD" "$VIEW"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; exit 1; }
done
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun is required — meshd is a bun program"; exit 1; }

/usr/bin/swiftc -O -o "$TMP/mesh-input" "$SRC" || { echo "FAIL: mesh-input.swift does not compile"; exit 1; }

# --- --dry-run must be a dry run -------------------------------------------------
# It has to return BEFORE the post, not after it. A dry run that still injected would
# be worse than having no test at all, and it would be invisible in this file's output.
awk '/^func post\(/,/^}/' "$SRC" > "$TMP/post"
dry_line="$(grep -n 'if dryRun' "$TMP/post" | cut -d: -f1 | head -1)"
post_line="$(grep -n 'event.post(tap:' "$TMP/post" | cut -d: -f1 | head -1)"
if [ -z "$dry_line" ] || [ -z "$post_line" ]; then
  echo "FAIL: post() no longer has both a --dry-run branch and a real post"
  fail=1
elif [ "$dry_line" -gt "$post_line" ]; then
  echo "FAIL: post() checks --dry-run after posting the event — the dry run injects"
  fail=1
fi
grep -q 'return }' "$TMP/post" \
  || { echo "FAIL: the --dry-run branch does not return, so it prints AND posts"; fail=1; }

# --- the phone -> meshd half of the pipeline -------------------------------------
cat > "$TMP/normalize.ts" <<TS
import { normalizeChords } from "$MESHD";
const lines = (await Bun.stdin.text()).split("\n").filter((l) => l.trim().length > 0);
const result = normalizeChords(lines.map((l) => JSON.parse(l)));
if ("error" in result) { console.log("REFUSED " + result.error); process.exit(0); }
for (const e of result.events) console.log(JSON.stringify(e));
TS

# What the phone puts on the wire, through meshd, into the helper.
synthesize() { printf '%s\n' "$1" | bun run "$TMP/normalize.ts" | "$TMP/mesh-input" --dry-run; }
normalize() { printf '%s\n' "$1" | bun run "$TMP/normalize.ts"; }

assert_sequence() {
  label="$1"; wire="$2"; want="$3"
  synthesize "$wire" > "$TMP/got"
  printf '%s\n' "$want" > "$TMP/want"
  if diff -u "$TMP/want" "$TMP/got" > "$TMP/diff" 2>&1; then :; else
    echo "FAIL: $label does not synthesize the chord sequence"
    sed -n '3,40p' "$TMP/diff"
    fail=1
  fi
}

# Keycodes are Apple's virtual key numbers and are hardcoded on purpose: 55 ⌘, 56 ⇧,
# 58 ⌥, 49 space, 19 "2", 21 "4". A modifier reports as `flags` rather than `keydown`
# because that is the event the real ⌘ key emits; whether it went down or came up is
# the flag list on the line.
assert_sequence "⌘space (Spotlight)" '{"t":"key","key":"space","mods":["cmd"]}' \
'flags 55 cmd
keydown 49 cmd
keyup 49 cmd
flags 55 -'

assert_sequence "⌥space (Raycast)" '{"t":"key","key":"space","mods":["option"]}' \
'flags 58 opt
keydown 49 opt
keyup 49 opt
flags 58 -'

assert_sequence "⌘⇧2" '{"t":"key","key":"2","mods":["cmd","shift"]}' \
'flags 55 cmd
flags 56 shift+cmd
keydown 19 shift+cmd
keyup 19 shift+cmd
flags 56 cmd
flags 55 -'

assert_sequence "⌘⇧4 (screenshot selection)" '{"t":"key","key":"4","mods":["cmd","shift"]}' \
'flags 55 cmd
flags 56 shift+cmd
keydown 21 shift+cmd
keyup 21 shift+cmd
flags 56 cmd
flags 55 -'

# The phone holds its sticky modifiers in a Set, so the same two taps can arrive in
# either order. They must press the SAME sequence — ⌘ outermost — not two.
assert_sequence "⌘⇧4 sent as ⇧ then ⌘" '{"t":"key","key":"4","mods":["shift","cmd"]}' \
'flags 55 cmd
flags 56 shift+cmd
keydown 21 shift+cmd
keyup 21 shift+cmd
flags 56 cmd
flags 55 -'

# cmd and command are one physical key. Pressing it twice would release it on the first
# lift while the rest of the chord still needed it.
assert_sequence "⌘⇧4 with a duplicated ⌘ alias" '{"t":"key","key":"4","mods":["command","cmd","shift"]}' \
'flags 55 cmd
flags 56 shift+cmd
keydown 21 shift+cmd
keyup 21 shift+cmd
flags 56 cmd
flags 55 -'

# --- all-or-nothing ---------------------------------------------------------------
# The whole point. A modifier neither backend can map must stop the chord, not shrink
# it: ⇧4 is "$", and typing "$" into the frontmost window is not a lesser screenshot.
for bad in nope super constructor; do
  out="$(normalize "{\"t\":\"key\",\"key\":\"4\",\"mods\":[\"cmd\",\"$bad\"]}")"
  case "$out" in
    "REFUSED unknown modifier: $bad") : ;;
    *) echo "FAIL: meshd accepted the unmappable modifier \"$bad\" (said: $out)"; fail=1 ;;
  esac
done

# And the helper refuses on its own too — meshd is not the only thing that ever feeds it.
printf '%s\n' '{"t":"key","key":"4","mods":["cmd","nope"]}' | "$TMP/mesh-input" --dry-run > "$TMP/bad"
if [ -s "$TMP/bad" ]; then
  echo "FAIL: mesh-input pressed something for a chord it could not fully map:"
  cat "$TMP/bad"
  fail=1
fi

# Non-chord events must pass through untouched — this guard sits in front of every
# pointer batch, not just the key bar.
out="$(normalize '{"t":"move","dx":3,"dy":-2}')"
case "$out" in
  *'"t":"move"'*'"dx":3'*) : ;;
  *) echo "FAIL: normalizeChords mangled a pointer event: $out"; fail=1 ;;
esac

# --- the key row on the phone -----------------------------------------------------
# Preset chips are the only way to reach these chords with one tap, and a chip whose key
# or modifier the Mac cannot map is a button that silently does nothing.
# Split on the quoted keys, never on commas: "," and "\\" are themselves entries in
# that table, and a comma-split loses exactly the punctuation this check is here for.
awk '/^let KEYCODES/,/^\]/' "$SRC" \
  | grep -oE '"[^"]*"[[:space:]]*:' \
  | sed 's/[[:space:]]*:$//; s/^"//; s/"$//' \
  | sed 's/\\\\/\\/g' \
  | sort -u > "$TMP/known-keys"
awk '/^let MODIFIERS/,/^\]/' "$SRC" | grep -oE '"[a-z]+"' | tr -d '"' | sort -u > "$TMP/known-mods"

awk '/private static let chords:/,/^    \]/' "$VIEW" \
  | sed -n 's/.*("[^"]*", *"\([^"]*\)", *\[\([^]]*\)\]).*/\1|\2/p' \
  | tr -d '" ' > "$TMP/chips"

[ -s "$TMP/chips" ] || { echo "FAIL: the remote-control key row declares no chord chips"; fail=1; }

for want in 'space|cmd' 'space|option' '2|cmd,shift' '4|cmd,shift'; do
  grep -qx "$want" "$TMP/chips" \
    || { echo "FAIL: the key row has no preset chip for $want"; fail=1; }
done

while IFS='|' read -r key mods; do
  [ -n "$key" ] || continue
  grep -Fqx -- "$key" "$TMP/known-keys" \
    || { echo "FAIL: chip key \"$key\" is not in mesh-input's KEYCODES"; fail=1; }
  for m in $(printf '%s' "$mods" | tr ',' ' '); do
    grep -Fqx -- "$m" "$TMP/known-mods" \
      || { echo "FAIL: chip modifier \"$m\" is not in mesh-input's MODIFIERS"; fail=1; }
  done
done < "$TMP/chips"

# A typed character combines with the held modifiers into one chord — but only for
# characters the Mac can actually press. Anything the phone thinks is chordable and the
# Mac does not know is a chord that vanishes.
chordable="$(sed -n 's/.*static let chordableCharacters = Set(#"\(.*\)"#).*/\1/p' "$VIEW")"
[ -n "$chordable" ] || { echo "FAIL: the phone no longer declares which characters it can press as keys"; fail=1; }
i=1
len=${#chordable}
while [ "$i" -le "$len" ]; do
  c="$(printf '%s' "$chordable" | cut -c "$i")"
  # -F, because half these characters ([ \ . ) are regex metacharacters and the other
  # half are the ones a chord is most likely to lose.
  grep -Fqx -- "$c" "$TMP/known-keys" \
    || { echo "FAIL: the phone would press \"$c\" as a key, which mesh-input cannot map"; fail=1; }
  i=$((i + 1))
done

# The sticky modifiers must reach the wire in a fixed order, or one gesture sends two
# different sequences on different days.
grep -q 'private static let modifierOrder' "$VIEW" \
  || { echo "FAIL: the phone no longer orders its sticky modifiers before sending them"; fail=1; }
awk '/func pressKey\(_ key: String\)/,/^    }/' "$VIEW" | grep -q 'orderedMods' \
  || { echo "FAIL: pressKey sends the raw Set again — the modifier order is back to chance"; fail=1; }
awk '/func type\(_ text: String\)/,/^    }/' "$VIEW" | grep -q 'pressKey' \
  || { echo "FAIL: a typed character no longer combines with the held modifiers into a chord"; fail=1; }

[ "$fail" -eq 0 ] || exit 1

printf 'OK: %s chord chips, all mappable; ⌘space ⌥space ⌘⇧2 ⌘⇧4 synthesize atomically; unmappable modifiers refused\n' \
  "$(wc -l < "$TMP/chips" | tr -d ' ')"

#!/bin/sh
# Two defects that a green build cannot see, because in both cases the wrong code
# compiles, renders and behaves normally right up to the moment it matters.
#
#  1. Smart punctuation. Every field that reaches a shell already calls
#     .autocorrectionDisabled(), which is why this looked handled — but that trait says
#     nothing about smart quotes or smart dashes, so iOS was still turning `--flag` into
#     `–flag` and "x" into curly quotes on the way to bash. The command fails, nothing on
#     screen says why, and the daemon takes the blame.
#
#     The first fix for this was a UITextField.appearance() proxy set at launch, and it
#     CRASHED THE APP: UIKit replays a stored appearance invocation onto every field
#     entering a window, and replaying any UITextInputTraits setter onto a UITextField
#     throws — so every screen with a TextField died. Measured on iOS 26.5 and 27.0, for
#     smartQuotesType / smartDashesType / smartInsertDeleteType / autocorrectionType
#     alike. This check used to REQUIRE those lines. Now it forbids them, and asserts the
#     per-field replacement instead. UITests/SmokeTests.swift covers what no grep can:
#     that a text field can actually appear.
#
#  2. The idle timer. Holding it is one line; releasing it is the line that gets lost in
#     a refactor, and a phone that never sleeps again is a worse bug than the dim. So we
#     assert the pairing, not the presence.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/iOS/MeshRelayApp.swift"
TERM="$ROOT/iOS/TerminalView.swift"
XTERM="$ROOT/install/payload/rmux-bridge/public/vendor/xterm.js"
fail=0

note() { echo "check-phone-input-and-wake: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# grep -I skips a file it decides is binary, in SILENCE — every assertion below would
# then pass vacuously. Refuse to run instead. (server.ts really did carry raw NULs once.)
for f in "$APP" "$TERM" "$XTERM"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ] \
    && bad "$f greps as binary — assertions would pass vacuously"
done
[ "$fail" = "0" ] || { echo "check-phone-input-and-wake: FAILED"; exit 1; }

# ---- 1. smart punctuation is handled per field, and NOT via the appearance proxy ----
sites=$(grep -rc 'autocorrectionDisabled' "$ROOT/iOS" | awk -F: '{n+=$2} END {print n+0}')
[ "$sites" -gt 0 ] || bad "no .autocorrectionDisabled() left in iOS/ — has input hygiene been removed wholesale?"

# The proxy is a crash, not a style preference. Any UITextInputTraits setter on either
# appearance proxy brings back the bug that shipped in 0.5.0.
proxy=$(grep -rn '(UITextField|UITextView)\.appearance\(\)\.(smart[A-Za-z]*Type|autocorrectionType)' \
          -E "$ROOT/iOS" 2>/dev/null || true)
if [ -n "$proxy" ]; then
  bad "a UITextInputTraits setter is back on an appearance proxy — this crashed every screen with a TextField in 0.5.0:"
  echo "$proxy" | sed 's/^/    /'
fi

# Every TextField carrying a host, path, URL, session name or command must normalise its
# own text. Numeric fields (format:) have no punctuation to rewrite.
# A TextField's binding may span several lines (the get:/set: form), so judge the
# declaration plus the next 4 lines, not the one line the match landed on.
raw=$(awk '
  FILENAME != prev { prev = FILENAME; n = 0 }
  { for (i = 1; i <= n; i++) buf[i] = buf[i+1] }
  /TextField\(/ && $0 !~ /format: \.number/ {
    block = $0; ln = FNR; f = FILENAME
    for (i = 1; i <= 4; i++) { if ((getline nxt) > 0) { block = block nxt; push[i] = nxt } else break }
    if (block !~ /shellSafe/) printf "%s:%d:%s\n", f, ln, $0
  }
' $(find "$ROOT/iOS" -name '*.swift') 2>/dev/null || true)
if [ -n "$raw" ]; then
  bad "these TextFields reach a shell but do not normalise smart punctuation (add .shellSafe):"
  echo "$raw" | sed 's/^/    /'
else
  covered=$(grep -rc 'shellSafe' "$ROOT/iOS" | awk -F: '{n+=$2} END {print n+0}')
  note "smart punctuation is normalised per field ($covered bindings), with no appearance proxy to crash on"
fi

# ---- 1b. the WKWebView terminal is NOT relying on that proxy ----
# xterm types into its own hidden textarea inside WKWebView, which the UIKit appearance
# proxy never touches. It must keep saying so itself, or swapping the vendored bundle
# would quietly re-enable autocorrect on the one field that is a live shell.
ok=1
for attr in 'autocorrect","off' 'autocapitalize","off' 'spellcheck","false'; do
  grep -q "setAttribute(\"$attr\")" "$XTERM" \
    || { bad "vendored xterm.js no longer sets $attr on its input helper — the WKWebView terminal is not covered by the UIKit proxy"; ok=0; }
done
[ "$ok" = "1" ] && note "the WKWebView terminal disables its own input correction, independent of UIKit"

# ---- 2. the idle timer is held and released in matching pairs ----
on=$(grep -c 'isIdleTimerDisabled = true' "$TERM" || true)
off=$(grep -c 'isIdleTimerDisabled = false' "$TERM" || true)
if [ "$on" = "0" ]; then
  bad "the terminal screen never holds the idle timer — the screen dims mid-session"
elif [ "$on" != "$off" ]; then
  bad "TerminalView.swift holds the idle timer $on time(s) and releases it $off — the phone would stop sleeping"
else
  note "the idle timer is held and released in $on matching pair(s)"
fi
# Held on a view, not on the app: an app-scope hold outlives the screen that needed it.
grep -q '.onDisappear { UIApplication.shared.isIdleTimerDisabled = false }' "$TERM" \
  || bad "the release is not on .onDisappear — leaving the terminal must give the screen back"

if [ "$fail" = "0" ]; then
  echo "check-phone-input-and-wake: OK"
else
  echo "check-phone-input-and-wake: FAILED"
  exit 1
fi

#!/bin/sh
# VoiceSegments self-check: pure accumulation logic for streaming speech recognition
# (pause mid-sentence, resume, a silent/empty task ending), proven without a microphone.
#
# check-all.sh's own check-*.swift loop compiles every scripts/check-*.swift against a
# fixed DEPS list that does not include Shared/VoiceSegments.swift, and check-all.sh is
# not to be edited to add it — so this script is a .sh, not a .swift, and compiles its
# own fixture directly against that one Shared file with its own swiftc line. Must build
# with -Onone: assert() is a no-op under -O, so an optimized build would pass even if the
# accumulation logic were wrong.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/check.swift" <<'EOF'
import Foundation

@main
struct CheckVoiceAccumulate {
    static func main() {
        // A pause mid-sentence: one task finalizes, a second one starts and grows a
        // partial on top of it, then it finalizes too.
        var s = VoiceSegments()
        assert(s.compose(partial: "") == "")
        assert(s.compose(partial: "hel") == "hel")
        s.append(final: "hello there")
        assert(s.compose(partial: "") == "hello there")
        assert(s.compose(partial: "how are") == "hello there how are")
        s.append(final: "how are you")
        assert(s.compose(partial: "") == "hello there how are you")

        // A task that ends with nothing recognized (silence gap, an error with no
        // result) must not inject a stray or doubled space.
        s.append(final: "")
        s.append(final: "   ")
        assert(s.compose(partial: "") == "hello there how are you")

        // Fresh, never-appended state composes straight from the partial, trimmed.
        var fresh = VoiceSegments()
        assert(fresh.compose(partial: "  wor  ") == "wor")

        // Resume rebases onto hand-edited text via the initializer, then keeps
        // appending after it rather than after whatever was committed before the edit.
        var resumed = VoiceSegments(committed: "hello there, corrected")
        resumed.append(final: "next segment")
        assert(resumed.compose(partial: "") == "hello there, corrected next segment")

        print("check-voice-accumulate: OK")
    }
}
EOF

BIN="$TMP/check-voice-accumulate"
if /usr/bin/swiftc -Onone -o "$BIN" "$ROOT/Shared/VoiceSegments.swift" "$TMP/check.swift" 2>"$TMP/err"; then
  "$BIN"
else
  echo "FAIL: check-voice-accumulate does not compile"
  tail -20 "$TMP/err"
  exit 1
fi

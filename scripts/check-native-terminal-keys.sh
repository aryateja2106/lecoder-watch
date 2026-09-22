#!/bin/sh
# The phone's native terminal (iOS/NativeTerminalScreen.swift) drives a pane through
# meshd's /send while the streaming pty route does not exist yet, so every keystroke
# SwiftTerm emits as bytes has to become a key name meshd accepts. This compiles the
# router with its test and pins the daemon side of the contract: the ctrl-/alt-letter
# pattern meshd resolves outside KEY_SEND_KEYS, and the `ansi=1` capture the screen
# needs to paint colour and place the cursor.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/install/payload/meshd/server.ts"
fail=0
bad() { echo "FAIL: $1"; fail=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if /usr/bin/swiftc -Onone -o "$TMP/keys" "$ROOT/scripts/native-terminal-keys-test.swift" "$ROOT/Shared/TerminalKeyRouter.swift" 2>"$TMP/err"; then
  "$TMP/keys" || bad "router test failed"
else
  bad "router does not compile: $(head -3 "$TMP/err")"
fi
grep -q 'function modifierKey' "$SERVER" || bad "meshd lost modifierKey (ctrl-/alt-letter keys)"
grep -q 'KEY_SEND_KEYS\[key\] ?? modifierKey(key)' "$SERVER" || bad "agentSend does not fall back to modifierKey"
grep -q 'capture-pane -p${ansi ? " -e" : ""}' "$SERVER" || bad "/output lost the ansi=1 -e capture"
grep -q '"captureAnsi"' "$SERVER" || bad "captureAnsi capability not advertised"
grep -q 'ansi: true' "$ROOT/iOS/NativeTerminalScreen.swift" || bad "native terminal no longer asks for ansi output"
grep -q 'supports("captureAnsi")' "$ROOT/Shared/MeshClient.swift" || bad "client sends ansi=1 without gating on the capability"
grep -q 'inputAccessoryView = nil' "$ROOT/iOS/NativeTerminalScreen.swift" || bad "SwiftTerm's own accessory bar would stack on the key bar"
[ "$fail" = 0 ] && echo "check-native-terminal-keys: ok" || exit 1

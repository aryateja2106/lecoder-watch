#!/bin/sh
# Build the two device-sync JSON bodies in process. A fixture token and a
# TEST-NET-3 address are sealed inside the ciphertext and must not appear in
# either body. This check does not call Supabase, read a mesh directory, or
# dial a daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/experiments/device-sync/client.ts"
CHECK="$ROOT/experiments/device-sync/check.ts"
SEAL="$ROOT/experiments/sealed-mailbox"

command -v node >/dev/null 2>&1 || {
  echo "FAIL: check-device-sync: node is not installed"
  exit 1
}

for f in "$CLIENT" "$CHECK" "$SEAL/seal.ts" "$SEAL/open.ts"; do
  [ -f "$f" ] || { echo "FAIL: check-device-sync: missing $f"; exit 1; }
done

# The client is what a later menu-bar change calls. A network client, a file
# write, or the live daemon port in this file would put a machine secret
# somewhere this slice is not allowed to put it.
if grep -E -n 'fetch\(|@supabase|createClient|supabase|8899|\.mesh|hosts\.json|node:fs|node:http|node:net|writeFile|readFile|homedir|process\.env|child_process|https?://' "$CLIENT"; then
  echo "FAIL: check-device-sync: client reaches the network, a file, or a live daemon"
  exit 1
fi

NODE_NO_WARNINGS=1 node --experimental-strip-types "$CHECK"

# The Swift round-trip already lives on this branch. Compile it with -Onone
# only when swiftc is present. A missing compiler does not skip the node
# check above: that check has already failed closed or passed.
if command -v swiftc >/dev/null 2>&1 && [ -f "$ROOT/scripts/check-sealed-mailbox-swift.sh" ]; then
  sh "$ROOT/scripts/check-sealed-mailbox-swift.sh"
fi

echo "check-device-sync: OK"

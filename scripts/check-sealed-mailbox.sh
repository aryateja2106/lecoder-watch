#!/bin/sh
# Seal and open a fleet handoff locally. The server-shaped blob is ciphertext;
# this check never sends it anywhere and never reads a real mesh token.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/experiments/sealed-mailbox"

command -v node >/dev/null 2>&1 || {
  echo "FAIL: check-sealed-mailbox: node is not installed"
  exit 1
}

for f in "$DIR/seal.ts" "$DIR/open.ts" "$DIR/check.ts"; do
  [ -f "$f" ] || { echo "FAIL: check-sealed-mailbox: missing $f"; exit 1; }
done

# These three files are the whole experiment. A client, a URL, or a file write
# would put a machine token somewhere this helper is not allowed to put it.
if grep -E -n 'fetch\(|@supabase|createClient|node:fs|node:http|writeFile' "$DIR"/*.ts; then
  echo "FAIL: check-sealed-mailbox: network, supabase, or a file write is in the helper"
  exit 1
fi

NODE_NO_WARNINGS=1 node --experimental-strip-types "$DIR/check.ts"

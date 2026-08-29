#!/bin/sh
# qr.ts self-check: every payload is encoded and then read back by a decoder written
# against the standard rather than against the encoder — format info BCH, Reed-Solomon
# syndromes, and the data bytes byte-for-byte. A QR that "looks right" but does not
# decode is the failure this pins down; nobody can eyeball a mask or a syndrome.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-pair-qr: SKIP (bun not installed)"; exit 0; }
bun "$ROOT/install/payload/meshd/qr.ts" --check

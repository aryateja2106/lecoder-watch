#!/bin/sh
# meshd's side of pairing: code shape, normalisation, loopback detection.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-pair: SKIP (no bun)"; exit 0; }
bun "$ROOT/install/payload/meshd/pair.ts" --check

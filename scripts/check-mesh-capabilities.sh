#!/bin/sh
# Honest /health capability list: Linux/container subsets of the macOS superset.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-capabilities: SKIP (no bun)"; exit 0; }
bun "$ROOT/install/payload/meshd/capabilities.ts" --check

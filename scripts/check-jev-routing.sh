#!/bin/sh
# Local routing fixture. Runs entirely on this machine.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
node --experimental-strip-types "$ROOT/experiments/jev-routing/check.ts"

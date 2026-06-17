#!/bin/sh
set -eu

tmp=$(mktemp "${TMPDIR:-/tmp}/mesh-self-check.XXXXXX")
trap 'rm -f "$tmp"' EXIT

printf '{"ok":true,"peers":[]}' > "$tmp"
grep '"ok":true' "$tmp" >/dev/null

printf '{"ok":false,"peers":[],"error":"tailscale unavailable"}' > "$tmp"
if grep '"ok":true' "$tmp" >/dev/null; then
  exit 1
fi

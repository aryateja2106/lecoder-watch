#!/bin/sh

set -eu

team="${1:-}"
if [ -z "$team" ]; then
  printf '%s\n' "Usage: scripts/set-development-team.sh TEAM_ID" >&2
  exit 2
fi

case "$team" in
  *[!A-Za-z0-9]*)
    printf '%s\n' "TEAM_ID must be alphanumeric, got: $team" >&2
    exit 2
    ;;
esac

if [ ! -f project.yml ]; then
  printf '%s\n' "project.yml not found; run from repo root" >&2
  exit 1
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/mesh-project.XXXXXX")
sed "s/DEVELOPMENT_TEAM: \"[^\"]*\"/DEVELOPMENT_TEAM: \"$team\"/" project.yml > "$tmp"
mv "$tmp" project.yml

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
else
  printf '%s\n' "Updated project.yml. Run xcodegen generate if MeshWatch.xcodeproj needs regeneration."
fi

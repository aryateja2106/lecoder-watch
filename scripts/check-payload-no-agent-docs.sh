#!/bin/sh
# check-payload-no-agent-docs.sh — the installer tarball carries no agent navigation files
# (AGENTS.md, INDEX.md) and no harness state (.omc, node_modules, lockfiles).
#
# install/payload/ is what `mesh-install` ships to every machine, and bin/ lands on the
# user's PATH with mode 755. The per-folder briefs and generated indexes written for coding
# agents live in the same folders, so the packager must drop them. This packages into a
# temp file and lists the archive; a match is a shipped note. Runs in about a second.
set -eu
cd "$(dirname "$0")/.."
command -v python3 >/dev/null 2>&1 || { echo "check-payload-no-agent-docs: SKIP (no python3)"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
sh scripts/package-mesh-install.sh "$TMP/mesh-install.tgz" >/dev/null
bad="$(tar -tzf "$TMP/mesh-install.tgz" | grep -E '(^|/)(AGENTS\.md|INDEX\.md|node_modules|\.omc|bun\.lockb?)(/|$)' || true)"
if [ -n "$bad" ]; then
  printf 'check-payload-no-agent-docs: shipped in the tarball:\n%s\n' "$bad"
  exit 1
fi
echo "check-payload-no-agent-docs: ok ($(tar -tzf "$TMP/mesh-install.tgz" | grep -c .) entries, no agent notes)"

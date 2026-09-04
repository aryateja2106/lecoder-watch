#!/bin/sh
# The four app-building skills (app-brief, apple-native-apis, native-app-builder,
# pwa-local-app-builder) started life as a draft with a hardcoded Team ID, a hardcoded
# bundle prefix, and a daemon on a port meshd has never listened on. This check makes
# sure none of that regressed back in, and that `mesh skills install` actually does what
# it says: copy into ~/.agents/skills and symlink every CLI's own skills directory to it,
# from a completely fresh $HOME.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_SRC="$ROOT/install/payload/share/skills"
MESH="$ROOT/install/payload/bin/mesh"
fail=0
bad() { echo "FAIL: $1"; fail=1; }

# ---- 1. no personal identifiers, no fake ports, in the shipped skills ----
for name in app-brief apple-native-apis native-app-builder pwa-local-app-builder; do
  f="$SKILLS_SRC/$name/SKILL.md"
  [ -f "$f" ] || { bad "missing $f"; continue; }
  for needle in B5B87F7AXF com.aryateja 7777 imake maxawad; do
    grep -q -- "$needle" "$f" && bad "$f still contains '$needle'"
  done
done
# The reference docs are part of the same rewrite — hold them to the same bar.
if [ -d "$SKILLS_SRC/apple-native-apis/references" ]; then
  for f in "$SKILLS_SRC"/apple-native-apis/references/*.md; do
    for needle in B5B87F7AXF com.aryateja 7777 imake maxawad; do
      grep -q -- "$needle" "$f" 2>/dev/null && bad "$f still contains '$needle'"
    done
  done
fi

# ---- 2. the repo's own symlinks resolve to real content ----
# .claude/skills and .cursor/skills pointers are committed. .agents/skills/* is per-machine
# by .gitignore policy (only factory-* rides into PRs), so on a fresh checkout — CI — those
# links are absent, which is fine; a real directory there would be a stale copy, which is not.
for name in app-brief apple-native-apis native-app-builder pwa-local-app-builder; do
  for dir in .cursor/skills .claude/skills; do
    link="$ROOT/$dir/$name"
    [ -L "$link" ] || { bad "$dir/$name is not a symlink"; continue; }
    [ -f "$link/SKILL.md" ] || bad "$dir/$name does not resolve to a SKILL.md"
  done
  local_copy="$ROOT/.agents/skills/$name"
  if [ -e "$local_copy" ] && [ ! -L "$local_copy" ]; then
    bad ".agents/skills/$name is a real directory — a stale copy; the canonical skill is install/payload/share/skills/$name"
  fi
done

command -v bun >/dev/null 2>&1 || { echo "check-mesh-skills: SKIP (no bun) — string/symlink checks above still ran"; [ "$fail" -eq 0 ] && exit 0 || exit 1; }

# ---- 3. `mesh skills install` into a temp HOME creates the expected links ----
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
run() { HOME="$TMP" MESH_HOME="$TMP/.mesh" bun "$MESH" "$@"; }

run skills install >"$TMP/out1" 2>&1 || { bad "mesh skills install failed:"; cat "$TMP/out1"; }
for name in app-brief apple-native-apis native-app-builder pwa-local-app-builder; do
  [ -f "$TMP/.agents/skills/$name/SKILL.md" ] || bad "no ~/.agents/skills/$name/SKILL.md after install"
  for dir in .claude .codex .cursor; do
    link="$TMP/$dir/skills/$name"
    [ -L "$link" ] || { bad "$dir/skills/$name is not a symlink after install"; continue; }
    [ -f "$link/SKILL.md" ] || bad "$dir/skills/$name symlink is broken"
  done
done

# Idempotent: a second install must not error or duplicate anything odd.
run skills install >/dev/null 2>&1 || bad "mesh skills install is not idempotent (second run failed)"

# `mesh skills status` must report all three installed, in JSON a caller can parse.
STATUS_JSON="$(run skills status --json)"
installed_count=$(printf '%s' "$STATUS_JSON" | grep -c '"installed": true') || installed_count=0
[ "$installed_count" -eq 4 ] || bad "mesh skills status --json reports $installed_count/4 installed"

# A directory the user owns (not created by mesh) must survive untouched.
mkdir -p "$TMP/.agents/skills/user-owned-example"
echo mine > "$TMP/.agents/skills/user-owned-example/mine.txt"
run skills install >/dev/null 2>&1
[ "$(cat "$TMP/.agents/skills/user-owned-example/mine.txt")" = "mine" ] || bad "install disturbed a directory it did not create"

# --uninstall removes the symlinks and the managed copy.
run skills install --uninstall >/dev/null 2>&1 || bad "mesh skills install --uninstall failed"
for name in app-brief apple-native-apis native-app-builder pwa-local-app-builder; do
  [ -e "$TMP/.agents/skills/$name" ] && bad "$name still present under ~/.agents/skills after --uninstall"
  for dir in .claude .codex .cursor; do
    [ -L "$TMP/$dir/skills/$name" ] && bad "$dir/skills/$name symlink survived --uninstall"
  done
done
[ -f "$TMP/.agents/skills/user-owned-example/mine.txt" ] || bad "--uninstall removed a directory it did not create"

if [ "$fail" -eq 0 ]; then
  echo "check-mesh-skills: OK (no personal identifiers, symlinks resolve, install/uninstall verified against a temp HOME)"
else
  exit 1
fi

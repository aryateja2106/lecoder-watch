#!/bin/sh
# `mesh uninstall` is a trust feature, not a convenience: someone non-technical pastes a
# curl command onto a machine they care about, and the only honest way to ask that is to
# be able to undo it completely. Two ways it could betray them, both tested here:
# leaving something of ours behind, or taking something of theirs with it.
#
# Runs entirely inside a throwaway HOME. os.homedir() follows $HOME on POSIX, so every
# path the command computes lands in the sandbox and the real install is never touched --
# which this check also asserts at the end, because a bug here would be expensive.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MESH="$ROOT/install/payload/bin/mesh"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-uninstall: SKIP (no bun)"; exit 0; }

TMP="$(mktemp -d)"
SB="$TMP/fakehome"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$SB/.mesh/bin" "$SB/.mesh/backups" "$SB/Library/LaunchAgents" \
         "$SB/.config/systemd/user" "$SB/.claude"

# A plausible install.
echo 'not-a-real-token' > "$SB/.mesh/token"
printf '{"default":"mac","hosts":{"mac":{"ip":"127.0.0.1","port":8899,"token":"x"}}}\n' > "$SB/.mesh/hosts.json"
: > "$SB/.mesh/kb.sqlite"
printf '<plist/>\n' > "$SB/Library/LaunchAgents/ai.lesearch.meshd.plist"
printf '<unit/>\n' > "$SB/.config/systemd/user/ai.lesearch-meshd.service"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/.mesh/bin/mesh-hook"}]}]}}\n' \
  > "$SB/.claude/settings.json"

# Our lines interleaved with lines that MUST survive byte for byte.
cat > "$SB/.zshrc" <<'RC'
export EDITOR=vim
alias gs="git status"

# MeshWatch PATH
eval "$($HOME/.mesh/bin/mesh shellenv)"

# MeshWatch cmux bridge (auto-start in interactive shells)
[ -f "$HOME/.mesh/hooks/cmux-bridge.zsh" ] && source "$HOME/.mesh/hooks/cmux-bridge.zsh"

export MY_IMPORTANT_VAR=keepme
RC
RC_LINES_BEFORE="$(wc -l < "$SB/.zshrc")"

run_mesh() { HOME="$SB" MESH_HOME="$SB/.mesh" bun "$MESH" "$@" >"$TMP/out" 2>&1 || true; }

fail=0
chk() {
  if [ "$2" = "$3" ]; then :; else echo "FAIL: $1 (got '$2', want '$3')"; fail=1; fi
}
# grep -c prints 0 AND exits 1 when it matches nothing, so a bare `|| echo 0` yields
# "0\n0" and every comparison fails. Count in one place instead.
count() { [ -f "$1" ] || { echo 0; return; }; grep -c "$2" "$1" 2>/dev/null || true; }

# ---- 1. no --yes means nothing is deleted ----
run_mesh uninstall
chk "dry run kept ~/.mesh"   "$([ -d "$SB/.mesh" ] && echo y || echo n)" "y"
chk "dry run kept the plist" "$([ -f "$SB/Library/LaunchAgents/ai.lesearch.meshd.plist" ] && echo y || echo n)" "y"
chk "dry run kept the rc"    "$(wc -l < "$SB/.zshrc" | tr -d ' ')" "$(echo "$RC_LINES_BEFORE" | tr -d ' ')"
grep -q -- "--yes" "$TMP/out" || { echo "FAIL: dry run does not say how to proceed"; fail=1; }
# It must name what it will delete, or "are you sure" is not informed consent.
grep -q "\.mesh" "$TMP/out" || { echo "FAIL: dry run does not name ~/.mesh"; fail=1; }

# ---- 2. --yes removes everything of ours ----
run_mesh uninstall --yes
chk "removed ~/.mesh"        "$([ -e "$SB/.mesh" ] && echo y || echo n)" "n"
chk "removed launchd plist"  "$([ -e "$SB/Library/LaunchAgents/ai.lesearch.meshd.plist" ] && echo y || echo n)" "n"
chk "unwired mesh-hook"      "$(count "$SB/.claude/settings.json" 'mesh-hook')" "0"
chk "dropped PATH line"      "$(count "$SB/.zshrc" 'mesh shellenv')" "0"
chk "dropped cmux line"      "$(count "$SB/.zshrc" 'cmux-bridge.zsh')" "0"
chk "dropped our comments"   "$(count "$SB/.zshrc" 'MeshWatch')" "0"

# ---- 3. and nothing of theirs ----
chk "kept EDITOR"            "$(count "$SB/.zshrc" 'EDITOR=vim')" "1"
chk "kept alias"             "$(count "$SB/.zshrc" 'alias gs')" "1"
chk "kept their var"         "$(count "$SB/.zshrc" 'MY_IMPORTANT_VAR')" "1"
chk "kept an rc backup"      "$([ -f "$SB/.zshrc.bak" ] && echo y || echo n)" "y"
# No hole left where our block used to be.
chk "no triple blank line"   "$(awk 'BEGIN{r=0;m=0} /^[[:space:]]*$/{r++; if(r>m)m=r; next} {r=0} END{print (m>2)?"bad":"ok"}' "$SB/.zshrc")" "ok"

# ---- 4. the sandbox really was a sandbox ----
chk "real ~/.mesh untouched" "$([ -d "$HOME/.mesh" ] && echo y || echo n)" "y"

if [ "$fail" = "0" ]; then
  echo "check-mesh-uninstall: OK (removes every installer artefact, keeps every user line)"
else
  echo "check-mesh-uninstall: FAILED"
  exit 1
fi

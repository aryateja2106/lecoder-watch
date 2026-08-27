#!/bin/sh
# check-bridge-kill-scope.sh — nothing shipped in the payload may enumerate processes by
# port without restricting to the LISTENING one.
#
# This exists because the bare form shipped, and it killed meshd.
#
# `lsof -i :PORT` matches a socket with that port on EITHER end, so
# `lsof -ti ":$port" | xargs kill -9` selected the bridge *and every client connected to
# the bridge*. meshd is such a client — GET /agents asks the bridge for cmux sessions
# over a kept-alive connection. And the starter runs from `~/.mesh/hooks/cmux-bridge.zsh`
# on EVERY interactive zsh. So on a machine where the bridge looked unhealthy, opening a
# terminal sent SIGKILL to the user's running daemon. Observed directly: `lsof -ti :8901`
# listed the bridge (LISTEN, pid 81037) and meshd (ESTABLISHED, pid 81044, the daemon
# serving :8899).
#
# The invariant is asserted on the SELECTION, not on the kill verb. Two earlier versions
# of this file keyed on the verb and both were escapable:
#   - the first matched the literal `kill -9`; the second added -KILL/-SIGKILL/-s KILL.
#     Both still passed `xargs kill -TERM`, `xargs kill -15`, and a bare `xargs kill` —
#     the *more* idiomatic spelling. SIGTERM ends meshd exactly as dead, and meshd runs
#     with KeepAlive=true, so the symptom is a daemon that bounces on every terminal
#     rather than one that stays down. Measured: 3 of those 4 spellings passed.
#   - worse, the positive assertions were GATED behind that same verb regex, so deleting
#     the two characters `-9` escaped the negative check AND switched off the positive
#     ones, while the script still printed "kills only the port's listener, never meshd".
#     A check that asserts a conclusion it did not verify is the failure this repo keeps
#     paying for.
# Selecting by port is also the step that must be safe when the kill sits on a different
# line (`pids=$(lsof -ti ":$p"); kill $pids`), which no verb rule can see.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ok=1
bad() { echo "FAIL: check-bridge-kill-scope.sh: $1"; ok=0; }

# Strip comments before judging, or the paragraph above reports itself. Trailing comments
# too: `kill -9 $pid  # only the listener, honest` laundered an unscoped kill straight
# past a whole-line-only filter.
# Both comment styles: the payload holds shell scripts AND bun/TypeScript ones
# (bin/mesh is `#!/usr/bin/env bun`), and bin/mesh's JSDoc block quotes the unsafe
# `lsof -ti ":$port"` form verbatim while documenting this very bug — so a stripper that
# only knew `#` reported the explanation as the defect.
strip_comments() {
  sed -e 's/[[:space:]]#.*$//' \
      -e 's/^[[:space:]]*#.*$//' \
      -e 's|^[[:space:]]*\*.*$||' \
      -e 's|^[[:space:]]*//.*$||' \
      -e 's|[[:space:]]//.*$||' "$1"
}

# Returns non-zero if the file violates the invariant, and says what it found.
# Run against the real payload AND against a deliberately broken copy, so this script
# proves it can still fail instead of only proving it can pass.
scan_file() {
  sf_file="$1"; sf_label="$2"; sf_bad=0
  sf_body="$(strip_comments "$sf_file")"

  # Only files that actually select processes by port are in scope. Without this, the
  # kill assertion below fired on bin/mesh purely because its help text contains the
  # string "mesh kill <session>" — a subcommand name in a usage line, not a defect.
  sf_sel="$(printf '%s\n' "$sf_body" | grep -E 'lsof[^|;&]*-ti' || true)"
  [ -n "$sf_sel" ] || return 0

  # Any lsof selection by port must be restricted to the listener.
  sf_unscoped="$(printf '%s\n' "$sf_sel" | grep -v 'sTCP:LISTEN' || true)"
  if [ -n "$sf_unscoped" ]; then
    echo "    $sf_label selects processes by port without -sTCP:LISTEN — that list includes"
    echo "    every client of the port, and meshd is one:"
    printf '      %s\n' "$sf_unscoped"
    sf_bad=1
  fi

  # And where any kill exists, the scoped selector must still be present, so deleting the
  # restriction outright cannot read as success. Any verb, any signal — the invariant is
  # "never kill the user's meshd", not "never SIGKILL it".
  if printf '%s\n' "$sf_body" | grep -qE '(^|[^A-Za-z0-9_.-])p?kill([[:space:]]|$)'; then
    printf '%s\n' "$sf_body" | grep -q -- '-sTCP:LISTEN' || {
      echo "    $sf_label kills processes but no longer restricts the selection to the listener"
      sf_bad=1
    }
  fi
  return "$sf_bad"
}

# Discover, rather than list. An earlier version named two files by hand; one was later
# deleted and the other was all that stayed covered, so a new script with the same defect
# would have been invisible.
files="$(find "$ROOT/install/payload" -type f \( -name '*.sh' -o -name '*.zsh' -o -perm -u+x \) 2>/dev/null | sort -u)"
[ -n "$files" ] || bad "found no payload scripts to scan — the search itself is broken"

scanned=0
for f in $files; do
  case "$f" in *.ts|*.swift|*.json|*.md) continue ;; esac
  grep -q 'lsof' "$f" 2>/dev/null || continue
  # Documentation of the historical bug is not the bug: count a file as covered only if
  # a real port selection survives comment stripping.
  strip_comments "$f" | grep -qE 'lsof[^|;&]*-ti' || continue
  scanned=$((scanned + 1))
  scan_file "$f" "${f#"$ROOT"/}" || bad "${f#"$ROOT"/} violates the meshd kill-scope invariant"
done
[ "$scanned" -gt 0 ] || bad "scanned 0 payload scripts that touch lsof — this check has stopped checking anything"

# ---- the check must be able to fail ----
# Mutate a copy into the form recorded as having killed meshd and require a "broken"
# verdict. If a bare `xargs kill` on an unscoped selection passes, every OK above is
# worthless — which is exactly the state the previous two versions shipped in.
HOOK="$ROOT/install/payload/hooks/cmux-bridge.zsh"
if [ -f "$HOOK" ]; then
  tmp="$(mktemp)"
  # Mutate by REMOVING the scope flag, not by rewriting one exact line. Anchoring the
  # mutation to a literal kill line meant any legitimate rewording of it (say `xargs
  # pkill -9`) made the self-test unable to mutate, and the check then failed honest
  # code. Stripping -sTCP:LISTEN reproduces the historical defect whatever the verb is.
  sed -e 's/ -sTCP:LISTEN//g' "$HOOK" > "$tmp"
  if cmp -s "$HOOK" "$tmp"; then
    bad "self-test could not mutate the hook — it carries no -sTCP:LISTEN to remove, so"
    echo "      this check cannot prove it detects anything. That is itself the defect."
  elif scan_file "$tmp" "<self-test mutant>" >/dev/null 2>&1; then
    bad "self-test: an unscoped port selection was judged acceptable."
    echo "      Every OK this script prints is meaningless until that is fixed."
  fi
  rm -f "$tmp"
fi

[ "$ok" -eq 1 ] || { echo "check-bridge-kill-scope: FAILED"; exit 1; }
echo "check-bridge-kill-scope: OK (nothing selects by port unscoped; self-test still catches the historical form)"

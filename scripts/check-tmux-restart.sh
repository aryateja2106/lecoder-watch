#!/bin/sh
# check-tmux-restart.sh — the daemon can be restarted more than once.
#
# On a machine with neither launchd nor systemd — every Linux box without a user systemd,
# and any Mac where the LaunchAgent did not take — meshd runs in a detached tmux session
# and `mesh upgrade` restarts it by killing that session and starting a new one.
#
# The session was named `ai.lesearch-meshd`. tmux does two separate things with that dot:
# it rewrites '.' in a session NAME to '_', so the session that actually exists is called
# `ai_lesearch-meshd`; and it reads '.' in a TARGET as the session:window.pane separator,
# so `kill-session -t ai.lesearch-meshd` answers "can't find pane: lesearch-meshd" and
# kills nothing at all.
#
# So the first start worked and every restart afterwards failed on a duplicate session.
# `mesh upgrade` then installed the new files, failed to restart, and left the old daemon
# serving — while `mesh version`, which reads the files, reported the new version. An
# upgrade that reports success and changes nothing running is the worst kind.
#
# Asserted by round-tripping a dotted name through tmux, because this is tmux behaviour
# and no amount of reading our own source would have shown it.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ok=1
bad() { echo "FAIL: check-tmux-restart.sh: $1"; ok=0; }

command -v tmux >/dev/null 2>&1 || { echo "check-tmux-restart: SKIP (no tmux)"; exit 0; }

# 1. Neither the CLI nor the installer may hand tmux a session name containing a dot.
grep -qE '^const SERVICE_TMUX = .*replace\(/\\\.\/g, "_"\)' "$ROOT/install/payload/bin/mesh" \
  || bad "install/payload/bin/mesh builds SERVICE_TMUX without stripping dots — a dotted session cannot be killed by its own name"
grep -qE "^mux_session\(\).*tr '\.' '_'" "$ROOT/install/install.sh" \
  || bad "install/install.sh's mux_session() does not strip dots"

# 2. And the reason, demonstrated against the real tmux on this machine: a dotted name is
#    created under a different name and is not reachable by the name that created it.
SOCK="checktmuxrestart$$"
tmux -L "$SOCK" kill-server 2>/dev/null || true
DOTTED="checkdot.restart-$$"
tmux -L "$SOCK" new-session -d -s "$DOTTED" -c /tmp 'sleep 30' 2>/dev/null || true
REAL="$(tmux -L "$SOCK" ls -F '#{session_name}' 2>/dev/null | head -1)"
if [ -n "$REAL" ] && [ "$REAL" = "$DOTTED" ]; then
  echo "check-tmux-restart: NOTE — this tmux keeps dots in session names; the guard is still correct, just not load-bearing here"
elif [ -n "$REAL" ]; then
  # This is the real world: the name came back different, so a dotted target cannot match.
  tmux -L "$SOCK" kill-session -t "$DOTTED" 2>/dev/null || true
  STILL="$(tmux -L "$SOCK" ls -F '#{session_name}' 2>/dev/null | head -1)"
  [ "$STILL" = "$REAL" ] \
    || bad "expected a dotted kill-session target to miss, and it did not — re-read this check's reasoning before trusting it"
  # And a second start under the same requested name must collide, which is the failure.
  tmux -L "$SOCK" new-session -d -s "$DOTTED" -c /tmp 'sleep 30' 2>/dev/null \
    && bad "a second new-session under the same dotted name succeeded — the collision this check describes did not happen"
fi
tmux -L "$SOCK" kill-server 2>/dev/null || true

[ "$ok" -eq 1 ] || exit 1
echo "check-tmux-restart: OK (session names carry no dots, so the restart can find and replace its own session)"

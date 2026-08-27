#!/bin/sh
# check-bridge-kill-scope.sh — the cmux-bridge starter may only kill the process that
# actually HOLDS its port, never the processes talking to it.
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
# It is a one-word regression to make again, it cannot be caught in review without
# knowing that lsof detail, and its symptom — "meshd keeps dying" — points nowhere near
# the shell profile that caused it.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ok=1
bad() { echo "FAIL: check-bridge-kill-scope.sh: $1"; ok=0; }

# Every script that force-kills by port. Add files here; never add exceptions.
for rel in install/payload/bin/start-cmux-bridge-inner.zsh install/payload/hooks/cmux-bridge.zsh; do
  f="$ROOT/$rel"
  [ -f "$f" ] || { bad "$rel is missing"; continue; }

  # No `kill -9` line may select processes by port without restricting to the listener.
  # Comments are stripped first — the explanation of this very bug says "kill -9" and
  # would otherwise report itself as the bug.
  unscoped="$(grep -v '^[[:space:]]*#' "$f" | grep 'kill -9' | grep -v 'sTCP:LISTEN' || true)"
  if [ -n "$unscoped" ]; then
    bad "$rel force-kills by port without -sTCP:LISTEN, which also kills every client of that port — meshd is one:"
    printf '    %s\n' "$unscoped"
  fi

  # The scoped form must actually be there, so deleting the kill outright (or renaming
  # the flag) cannot read as success.
  grep -q 'lsof -ti "tcp:' "$f" \
    || bad "$rel no longer selects the port owner with lsof -ti tcp:<port>"
  grep -q -- '-sTCP:LISTEN' "$f" \
    || bad "$rel no longer restricts its kill to the listening process"
done

[ "$ok" -eq 1 ] || exit 1
echo "check-bridge-kill-scope: OK (the bridge starter kills only the port's listener, never meshd)"

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

# Discover, rather than list. The previous version named two files by hand; one of them
# was later deleted and the other was the only thing still covered, so a new script with
# the same defect would have been invisible. Anything shipped in the payload that kills
# by port is in scope.
files="$(find "$ROOT/install/payload" -type f \( -name '*.sh' -o -name '*.zsh' -o -perm -u+x \) 2>/dev/null | sort -u)"
[ -n "$files" ] || bad "found no payload scripts to scan — the search itself is broken"

scanned=0
for f in $files; do
  case "$f" in *.ts|*.swift|*.json|*.md) continue ;; esac
  grep -q 'lsof' "$f" 2>/dev/null || continue
  rel="${f#$ROOT/}"
  scanned=$((scanned + 1))

  # Strip comments before judging, or the paragraph explaining this very bug reports
  # itself. Trailing comments too: `kill -9 $pid  # only the listener, honest` used to
  # launder an unscoped kill straight past a whole-line-only filter.
  body="$(sed -e 's/[[:space:]]#.*$//' -e 's/^[[:space:]]*#.*$//' "$f")"

  # Every spelling of SIGKILL, not just `kill -9`. `kill -KILL`, `kill -s KILL` and
  # `kill -SIGKILL` are the same instruction and were all invisible before.
  unscoped="$(printf '%s\n' "$body" \
    | grep -E 'kill[[:space:]]+(-9|-KILL|-SIGKILL|-s[[:space:]]+(KILL|SIGKILL|9))' \
    | grep -v 'sTCP:LISTEN' || true)"
  if [ -n "$unscoped" ]; then
    bad "$rel force-kills by port without -sTCP:LISTEN, which also kills every client of that port — meshd is one:"
    printf '    %s\n' "$unscoped"
  fi

  # Where a kill exists at all, the scoped selector must be present, so deleting the
  # restriction (or renaming the flag) cannot read as success.
  if printf '%s\n' "$body" | grep -qE 'kill[[:space:]]+(-9|-KILL|-SIGKILL|-s[[:space:]]+(KILL|SIGKILL|9))'; then
    printf '%s\n' "$body" | grep -q 'lsof -ti "tcp:' \
      || bad "$rel no longer selects the port owner with lsof -ti tcp:<port>"
    printf '%s\n' "$body" | grep -q -- '-sTCP:LISTEN' \
      || bad "$rel no longer restricts its kill to the listening process"
  fi
done
[ "$scanned" -gt 0 ] || bad "scanned 0 payload scripts that touch lsof — this check has stopped checking anything"

[ "$ok" -eq 1 ] || exit 1
echo "check-bridge-kill-scope: OK (the bridge starter kills only the port's listener, never meshd)"

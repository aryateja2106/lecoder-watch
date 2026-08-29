#!/bin/sh
# The shell hook must never make opening a terminal slow.
#
# cmux-bridge.zsh is sourced from ~/.zshrc, so it runs on EVERY interactive shell. It
# once cost 14.4 seconds each, measured: its health check asked whether the cmux *app*
# had at least one window open — a property of a separate desktop program, not of the
# bridge — so with cmux closed a perfectly working bridge was declared broken, kill -9'd,
# and waited on through a 20 x 0.25s retry loop that could not possibly succeed, because
# restarting the bridge cannot start cmux.
#
# This asserts behaviour, not shape: it runs the hook and times it. A grep for "no retry
# loop" would pass the moment somebody wrote a slow check in a different style.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/install/payload/hooks/cmux-bridge.zsh"
fail=0

note() { echo "check-shell-startup: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

[ -f "$HOOK" ] || { bad "missing $HOOK"; echo "check-shell-startup: FAILED"; exit 1; }
command -v zsh >/dev/null 2>&1 || { note "SKIP — no zsh on this machine"; exit 0; }

# A port nothing is listening on, so the hook takes its "bridge is down" path — the one
# that used to burn 14.4s. Probed rather than assumed: a hard-coded port that happened to
# be busy would make this check silently measure the fast path instead.
PORT=""
for candidate in 8931 8932 8933 8934 8935; do
  if ! lsof -ti "tcp:$candidate" -sTCP:LISTEN >/dev/null 2>&1; then PORT="$candidate"; break; fi
done
[ -n "$PORT" ] || { note "SKIP — could not find a free port to probe with"; exit 0; }

# Budget. Generous on purpose: this is not a benchmark, it is a tripwire for a hook that
# blocks. Anything under a second is imperceptible; the regression it guards was 14400ms.
BUDGET_MS=1000

ELAPSED_MS="$(zsh -f -c '
  # Neutralise the spawn: the hook launches a real bun process via `nohup launchctl`,
  # and a check must not leave a daemon behind on a bogus port.
  nohup()     { : }
  launchctl() { : }
  export CMUX_BRIDGE_PORT="'"$PORT"'"
  source "'"$HOOK"'" 2>/dev/null

  typeset -F SECONDS=0
  start_cmux_bridge >/dev/null 2>&1 || true
  printf "%.0f" $(( SECONDS * 1000 ))
' 2>/dev/null || echo "99999")"

case "$ELAPSED_MS" in
  ''|*[!0-9]*) bad "could not time the hook (got: '$ELAPSED_MS')" ;;
  *)
    if [ "$ELAPSED_MS" -gt "$BUDGET_MS" ]; then
      bad "opening a shell would block for ${ELAPSED_MS}ms in start_cmux_bridge (budget ${BUDGET_MS}ms)."
      echo "      This hook runs on every interactive shell. It must not wait on a daemon:"
      echo "      report the problem through 'mesh doctor', never through the user's prompt."
    else
      note "the bridge hook returns in ${ELAPSED_MS}ms with no bridge running (budget ${BUDGET_MS}ms)"
    fi
    ;;
esac

# ---- the wedged-listener path, which the case above structurally cannot see ----
# `curl -m 1` only costs its full timeout when something ACCEPTS the connection and then
# never answers. The probe above deliberately uses a FREE port, where connect fails
# instantly (62ms measured) — so on its own it would pass a hook that blocks a full
# second on every shell. This case stands up a listener that accepts and says nothing,
# which is what a wedged bridge looks like.
if command -v python3 >/dev/null 2>&1; then
  WPORT=""
  for candidate in 8941 8942 8943 8944 8945; do
    if ! lsof -ti "tcp:$candidate" -sTCP:LISTEN >/dev/null 2>&1; then WPORT="$candidate"; break; fi
  done
  if [ -z "$WPORT" ]; then
    note "SKIP (wedged case) — no free port to stand a listener on"
  else
    python3 -c "
import socket, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', $WPORT)); s.listen(8); s.settimeout(0.2)
# HOLD every accepted connection. Dropping it lets CPython garbage-collect and CLOSE the
# socket, so curl gets an instant EOF instead of hanging — this measured 66ms instead of
# the ~1000ms it is supposed to reproduce, i.e. the check silently tested nothing.
held = []
end = time.time() + 30
while time.time() < end:
    try:
        conn, _ = s.accept()
        held.append(conn)     # accepted, and deliberately never answered
    except Exception:
        pass
" >/dev/null 2>&1 &
    LPID=$!
    sleep 1

    # A private TMPDIR so the hook's restart stamp cannot be pre-warmed by a real shell
    # on this machine — a fresh stamp would send it down the early-return and measure
    # nothing.
    WTMP="$(mktemp -d)"
    WEDGED_MS="$(zsh -f -c '
      nohup()     { : }
      launchctl() { : }
      export TMPDIR="'"$WTMP"'"
      export CMUX_BRIDGE_PORT="'"$WPORT"'"
      source "'"$HOOK"'" 2>/dev/null
      typeset -F SECONDS=0
      start_cmux_bridge >/dev/null 2>&1 || true
      printf "%.0f" $(( SECONDS * 1000 ))
    ' 2>/dev/null || echo "99999")"
    kill "$LPID" 2>/dev/null || true
    wait "$LPID" 2>/dev/null || true
    rm -rf "$WTMP"

    WEDGED_BUDGET_MS=2500
    case "$WEDGED_MS" in
      ''|*[!0-9]*) bad "could not time the wedged-listener path (got: '$WEDGED_MS')" ;;
      *)
        if [ "$WEDGED_MS" -gt "$WEDGED_BUDGET_MS" ]; then
          bad "a wedged bridge costs ${WEDGED_MS}ms per shell (budget ${WEDGED_BUDGET_MS}ms)"
        else
          note "a wedged bridge (accepts, never answers) costs ${WEDGED_MS}ms (budget ${WEDGED_BUDGET_MS}ms)"
        fi
        ;;
    esac
  fi
else
  note "SKIP (wedged case) — no python3 to stand a listener on"
fi

# The specific wrong question, kept out by name. Whether cmux has windows open — or is
# running at all — says nothing about whether the bridge is healthy, and conflating them
# is what made the timeout unreachable.
if grep -q 'windows' "$HOOK" 2>/dev/null; then
  bad "the hook's health check inspects cmux's window list again — a bridge with zero"
  echo "      cmux windows is healthy, and restarting it can never create one."
fi

[ "$fail" = "0" ] || { echo "check-shell-startup: FAILED"; exit 1; }
echo "check-shell-startup: OK"

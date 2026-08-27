#!/bin/sh
# check-install-idempotent.sh — re-running the one-liner does not reinstall on top of
# itself, an older install still upgrades, and an unset SHELL does not kill the run.
#
# The one-liner is the command people keep in their shell history and the one printed on
# the website, so re-running it is the most natural thing anybody does. It used to
# reinstall unconditionally, and that is not free: bin/ is replaced wholesale, and macOS
# grants Accessibility per BINARY — so overwriting an unchanged mesh-input costs the user
# that grant, and every click and keystroke from their watch silently stops working until
# they work out why. Paying that to install bytes already on disk is a bad trade.
#
# The opposite mistake is worse, so it is asserted too: someone whose `mesh` is too old to
# run `mesh upgrade` has only this one-liner, and refusing them would strand them on a
# stale daemon forever.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$ROOT/install/install.sh"
SERVER="$ROOT/install/payload/meshd/server.ts"
ok=1
bad() { echo "FAIL: check-install-idempotent.sh: $1"; ok=0; }

[ -f "$INSTALL" ] || { bad "install/install.sh is missing"; exit 1; }

WANT="$(tr -d '\000' < "$SERVER" | sed -n 's/^[[:space:]]*const VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$WANT" ] || { bad "could not read VERSION out of the payload's meshd/server.ts"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# `--only tools` keeps this off the network: no bun bootstrap, no daemon, no services.
run_install() {
  sb="$1"; shift
  mkdir -p "$sb"
  # `|| true` matters: under `set -e` a failing install aborts this whole check before it
  # can say what went wrong, so a caught bug looks like a broken test rather than a report.
  ( cd "$ROOT/install" && HOME="$sb" MESH_HOME="$sb/.mesh" \
      sh "$INSTALL" --prefix "$sb/.mesh" --only tools --no-start "$@" ) >"$sb/out.log" 2>&1 \
    && printf 0 > "$sb/exit" || printf '%s' "$?" > "$sb/exit"
}

fake_install() {   # $1 = sandbox, $2 = version to pretend is installed
  mkdir -p "$1/.mesh/meshd"
  printf 'const VERSION = "%s";\n' "$2" > "$1/.mesh/meshd/server.ts"
}

# 1. Same version already there: say so, change nothing, exit clean.
A="$TMP/same"
fake_install "$A" "$WANT"
run_install "$A"
[ "$(cat "$A/exit")" = "0" ] || bad "re-running on an identical install exited $(cat "$A/exit"), not 0"
grep -qi 'already installed' "$A/out.log" \
  || { bad "re-running on an identical install did not say it was already installed:"; sed 's/^/    /' "$A/out.log" | tail -5; }
[ ! -d "$A/.mesh/bin" ] \
  || bad "it skipped but still wrote bin/ — on macOS that costs the user their Accessibility grant"

# 2. --force is the way through.
B="$TMP/force"
fake_install "$B" "$WANT"
run_install "$B" --force
grep -qi 'already installed' "$B/out.log" \
  && bad "--force was ignored — there is no way to deliberately reinstall"
[ -d "$B/.mesh/bin" ] || bad "--force did not actually install anything"

# 3. An older install must still upgrade. This one-liner IS the upgrade path for anyone
#    whose `mesh` predates `mesh upgrade`.
C="$TMP/older"
fake_install "$C" "0.0.1-ancient"
run_install "$C"
grep -qi 'already installed' "$C/out.log" \
  && bad "an OLDER install was refused — that strands anyone whose mesh is too old to self-upgrade"
[ -d "$C/.mesh/bin" ] || bad "an older install was not upgraded"

# 4. SHELL unset. Docker, cron, a non-login ssh — most of the headless Linux this is meant
#    for. `${SHELL##*/}` under `set -u` is fatal there, and it fires at the very end, after
#    everything is installed, so a working install reads as a failed one.
#    It has to run under a shell that can actually show it. macOS /bin/sh is bash, and
#    bash SETS $SHELL for itself when the environment does not — so `env -u SHELL sh` on a
#    Mac silently tests nothing and passes whether the bug is there or not. dash (which is
#    /bin/sh on the Linux this ships to, and on the CI runner) is the shell that reproduces
#    it. Skip loudly rather than pass quietly when there is no dash to use.
NOSHELL_SH=""
for c in dash /bin/dash /usr/bin/dash; do command -v "$c" >/dev/null 2>&1 && { NOSHELL_SH="$c"; break; }; done
if [ -z "$NOSHELL_SH" ]; then
  echo "check-install-idempotent: NOTE — unset-SHELL case skipped, no dash here (bash re-sets \$SHELL, so /bin/sh cannot show it)"
else
  D="$TMP/noshell"
  mkdir -p "$D"
  ( cd "$ROOT/install" && env -u SHELL HOME="$D" MESH_HOME="$D/.mesh" \
      "$NOSHELL_SH" "$INSTALL" --prefix "$D/.mesh" --only tools --no-start ) >"$D/out.log" 2>&1 \
    && echo 0 > "$D/exit" || echo "$?" > "$D/exit"
  [ "$(cat "$D/exit")" = "0" ] \
    || { bad "installing with SHELL unset exited $(cat "$D/exit")"; tail -4 "$D/out.log" | sed 's/^/    /'; }
  if grep -q 'SHELL: parameter not set\|SHELL: unbound variable' "$D/out.log"; then
    bad "install still dies on an unset SHELL:"
    grep -n 'SHELL' "$D/out.log" | head -2 | sed 's/^/    /'
  fi
fi

[ "$ok" -eq 1 ] || exit 1
echo "check-install-idempotent: OK (same version skips, --force overrides, older upgrades, unset SHELL survives)"

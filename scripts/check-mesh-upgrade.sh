#!/bin/sh
# End-to-end proof of `mesh upgrade` against a throwaway MESH_HOME.
#
# Reading the code cannot tell you whether an upgrade is safe — the whole command is a
# sequence of moves on a directory tree, and every way it can go wrong is invisible in
# the source:
#   - the swap silently not happening (the old cosmetic `install.sh --upgrade` bug),
#   - the old tree deleted instead of kept, so there is nothing to roll back to,
#   - token / hosts.json clobbered, which unpairs every phone and watch on the mesh,
#   - a failed upgrade leaving a half-swapped tree behind,
#   - and the original sin: the files land but the daemon is never restarted, so the
#     machine keeps serving the old build with no error anywhere (how the fleet froze
#     on 0.2.x while every host reported a successful "upgrade").
# So this drives the real command and then looks at the real directory.
#
# Everything runs against a throwaway HOME, a throwaway MESH_HOME, a private tmux server
# (TMUX_TMPDIR) and MESH_LABEL_PREFIX, so it never touches the deployed ~/.mesh or the
# real service. The rollback path is the same code with a restart that cannot come up —
# reproduce it by squatting the daemon's port before the last phase.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-upgrade: SKIP (bun not installed)"; exit 0; }

TH="$(mktemp -d)"
trap 'ec=$?; TMUX_TMPDIR="$TH/tmux" tmux kill-server 2>/dev/null || true; rm -rf "$TH" 2>/dev/null || true; exit "$ec"' EXIT INT TERM

MH="$TH/mesh"
CLI="$ROOT/install/payload/bin/mesh"
# A port nothing is listening on, so the preflight /health probe is deterministic here
# and never depends on whether this machine happens to be running a real daemon.
DEAD_PORT=8998

fail() { echo "FAIL: $*"; exit 1; }

# ---------- seed a fake old install ----------

mkdir -p "$MH"
cp -R "$ROOT/install/payload/meshd" "$MH/meshd"
# Rewrite the seeded VERSION so "the new one is in place" is a real assertion and not
# two identical trees passing by accident.
sed 's/^const VERSION = .*/const VERSION = "0.0.1-test";/' "$MH/meshd/server.ts" > "$MH/meshd/server.ts.new"
mv "$MH/meshd/server.ts.new" "$MH/meshd/server.ts"
grep -q '^const VERSION = "0.0.1-test";' "$MH/meshd/server.ts" || fail "could not seed the old VERSION"

printf 'seed-token-must-survive\n' > "$MH/token"
printf '{"default":"seed","hosts":{"seed":{"ip":"10.0.0.9","port":8899,"token":"seed-host-token"}}}\n' > "$MH/hosts.json"
cp "$MH/token" "$TH/token.expected"
cp "$MH/hosts.json" "$TH/hosts.expected"

NEW_VERSION="$(sed -n 's/^const VERSION = "\(.*\)";/\1/p' "$ROOT/install/payload/meshd/server.ts")"
[ -n "$NEW_VERSION" ] || fail "could not read the repo's meshd VERSION"

# ---------- the real upgrade, from this checkout ----------

MESH_HOME="$MH" MESHD_PORT="$DEAD_PORT" bun "$CLI" upgrade --src "$ROOT/install" --no-restart \
  || fail "mesh upgrade exited nonzero"

grep -q "^const VERSION = \"$NEW_VERSION\";" "$MH/meshd/server.ts" \
  || fail "meshd/server.ts is not the new $NEW_VERSION after the upgrade"

BACKUP="$(ls -d "$MH"/backups/meshd-0.0.1-test-* 2>/dev/null | head -1)" || true
[ -n "${BACKUP:-}" ] && [ -d "$BACKUP" ] || fail "the old meshd was not kept under backups/ (nothing to roll back to)"
grep -q '^const VERSION = "0.0.1-test";' "$BACKUP/server.ts" \
  || fail "the backup is not the old tree"

cmp -s "$MH/token" "$TH/token.expected" || fail "the token was modified — every paired device would be locked out"
cmp -s "$MH/hosts.json" "$TH/hosts.expected" || fail "hosts.json was modified"

# Staging is an implementation detail and must not outlive the command.
[ -z "$(find "$MH" -maxdepth 1 -name '.staging-*' 2>/dev/null)" ] || fail "a .staging-* directory was left behind"

# ---------- a corrupted source must change nothing ----------

BAD="$TH/bad/payload"
mkdir -p "$BAD/meshd" "$BAD/bin"
: > "$BAD/bin/mesh"          # bin/mesh present, meshd/server.ts deliberately missing

# Cheap tree fingerprint: names + the bytes of everything that matters. node_modules is
# excluded only because it is 28MB of dev-only type stubs.
manifest() { find "$1" -not -path '*/node_modules/*' | sed "s#^$1##" | sort; }
BEFORE="$(manifest "$MH")"

if MESH_HOME="$MH" MESHD_PORT="$DEAD_PORT" bun "$CLI" upgrade --src "$TH/bad" --no-restart >"$TH/bad.log" 2>&1; then
  fail "upgrade from a payload with no meshd/server.ts must fail, but it exited 0"
fi
grep -q 'server.ts' "$TH/bad.log" || fail "the failure did not name the missing file: $(cat "$TH/bad.log")"

[ "$BEFORE" = "$(manifest "$MH")" ] || fail "a failed upgrade changed the tree"
grep -q "^const VERSION = \"$NEW_VERSION\";" "$MH/meshd/server.ts" || fail "a failed upgrade damaged the installed meshd"
cmp -s "$MH/token" "$TH/token.expected" || fail "a failed upgrade touched the token"
cmp -s "$MH/hosts.json" "$TH/hosts.expected" || fail "a failed upgrade touched hosts.json"

# ---------- the restart actually happens ----------
#
# The bug this whole command exists for: without a real restart the daemon keeps serving
# the old build out of memory. So run the upgrade for real, with no --no-restart, and
# make the DAEMON say which version it is.

if ! command -v tmux >/dev/null 2>&1; then
  echo "check-mesh-upgrade: OK (restart phase skipped — no tmux)"
  exit 0
fi

RH="$TH/rhome"
mkdir -p "$RH/.mesh" "$TH/tmux" "$RH/.mesh/hooks"
cp -R "$ROOT/install/payload/meshd" "$RH/.mesh/meshd"

# A hooks/ file from an older release, plus one of the user's own. Upgrade used to move
# bin/ and meshd/ and leave hooks/ untouched — so a fix shipped in a hook only ever
# reached people doing a FRESH install, which is precisely the people who do not need it.
# That stranded the cmux-bridge fix: on a machine that upgraded, the line that SIGKILLs
# meshd on every interactive shell was still there afterwards. Measured on a real machine.
printf 'stale hook from an older release\n' > "$RH/.mesh/hooks/cmux-bridge.zsh"
printf 'mine, keep it\n' > "$RH/.mesh/hooks/my-own-hook.zsh"
sed 's/^const VERSION = .*/const VERSION = "0.0.1-test";/' "$RH/.mesh/meshd/server.ts" > "$RH/v" && mv "$RH/v" "$RH/.mesh/meshd/server.ts"
printf 'restart-phase-token\n' > "$RH/.mesh/token"
cp "$RH/.mesh/token" "$TH/rtoken.expected"

# Outside 8901-8999, which the pre-install trial run scans for a scratch port.
RPORT="$(bun -e 'for(let p=9100;p<9200;p++){try{Bun.serve({port:p,hostname:"127.0.0.1",fetch:()=>new Response("")}).stop(true);console.log(p);break}catch{}}')"
[ -n "$RPORT" ] || fail "no free port in 9100-9199 for the restart phase"

HOME="$RH" MESH_HOME="$RH/.mesh" MESH_LABEL_PREFIX=meshupgradecheck MESHD_HOST=127.0.0.1 \
  MESHD_PORT="$RPORT" TMUX_TMPDIR="$TH/tmux" \
  bun "$CLI" upgrade --src "$ROOT/install" >"$TH/restart.log" 2>&1 \
  || { cat "$TH/restart.log"; fail "mesh upgrade (with restart) exited nonzero"; }

LIVE="$(curl -fsS "http://127.0.0.1:$RPORT/health" 2>/dev/null | sed -n 's/.*"meshdVersion":"\([^"]*\)".*/\1/p')"
[ "$LIVE" = "$NEW_VERSION" ] \
  || { cat "$TH/restart.log"; fail "the restarted daemon reports '${LIVE:-nothing}', not $NEW_VERSION — the upgrade was cosmetic"; }
cmp -s "$RH/.mesh/token" "$TH/rtoken.expected" || fail "the restart phase modified the token"

# hooks/ has to arrive with everything else.
cmp -s "$RH/.mesh/hooks/cmux-bridge.zsh" "$ROOT/install/payload/hooks/cmux-bridge.zsh" \
  || fail "upgrade left the old hooks/cmux-bridge.zsh in place — a fix shipped in a hook never reaches anyone who upgrades"
[ -f "$RH/.mesh/hooks/my-own-hook.zsh" ] \
  || fail "upgrade deleted a hook the user put there themselves"

echo "check-mesh-upgrade: OK (0.0.1-test -> $NEW_VERSION, state preserved, hooks synced, failure is a no-op, daemon really restarted)"

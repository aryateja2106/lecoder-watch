#!/bin/sh
# End-to-end proof of `mesh token rotate` against a throwaway MESH_HOME.
#
# This command is the remediation path for a leaked bearer token — the fleet's tokens
# have escaped into local AI-session transcripts twice — so "it printed a new token" is
# not the thing that matters. Every way it can be a lie is invisible in the source:
#   - the file rotates but the DAEMON keeps the old secret in memory (the leaked one is
#     still live and `mesh doctor` still says "token set"),
#   - the old token is overwritten with no backup, which is a permanent lockout,
#   - hosts.json or another piece of unrecoverable state gets clobbered,
#   - the restart puts the token back on a command line, where `ps` hands it to every
#     other user on the box.
#
# WHAT THIS PROVES (by running the real command against a real daemon):
#   * $MESH_HOME/token is 64 hex, mode 0600, and different from the old value;
#   * the old value survives as token.bak-<UTC>, mode 0600;
#   * hosts.json is byte-for-byte untouched, and no temp file is left behind;
#   * the daemon is really restarted and answers /health afterwards;
#   * THE RUNNING DAEMON SERVES THE NEW TOKEN. Proven end-to-end via /pair/claim, which
#     hands a phone the token the daemon is running with: before the rotation it returns
#     the seeded token, after it returns the new one. A plain authenticated request
#     cannot prove this from here — the daemon exempts loopback by socket address, and
#     spoofing a non-loopback peer locally is not possible (an Origin header is rejected
#     for both tokens, so it discriminates nothing);
#   * no process argv anywhere on this machine contains either token, and neither does
#     the tmux pane's start command — the `ps` leak the env-file change closes.
#
# WHAT THIS DOES NOT PROVE:
#   * install.sh's own tmux fallback is only checked by shape (the last section), not by
#     running it: a real run needs `bun install` and a network round-trip.
#   * the launchd/systemd branches of the rotation (rewriting the plist / unit env) are
#     not exercised — no service is registered under the test label prefix, so the tmux
#     fallback is what runs here.
#   * the remote (-H) flow is not exercised; it needs a second machine.
#
# Everything runs against a throwaway HOME, MESH_HOME, tmux server (TMUX_TMPDIR) and
# MESH_LABEL_PREFIX, so it never touches the deployed ~/.mesh or the real service.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-token-rotate: SKIP (bun not installed)"; exit 0; }
command -v tmux >/dev/null 2>&1 || { echo "check-token-rotate: SKIP (no tmux — the restart is the point)"; exit 0; }

TH="$(mktemp -d)"
trap 'ec=$?; TMUX_TMPDIR="$TH/tmux" tmux kill-server 2>/dev/null || true; rm -rf "$TH" 2>/dev/null || true; exit "$ec"' EXIT INT TERM

HM="$TH/home"
MH="$HM/.mesh"
CLI="$ROOT/install/payload/bin/mesh"
PREFIX=meshrotatecheck
SESSION="$PREFIX-meshd"

fail() { echo "FAIL: $*"; exit 1; }
# GNU first: on Linux `stat -f` SUCCEEDS as a filesystem stat and prints a page of
# garbage, so BSD-first never falls through. macOS rejects `-c` cleanly, so this
# ordering works on both (caught by the ubuntu CI job, 2026-08-21).
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

# Same env on every invocation of the CLI under test. MESHD_TOKEN is deliberately NOT
# exported: localToken() prefers it, and a rotation that reads the environment instead of
# the file would silently re-install the old secret.
run_mesh() {
  HOME="$HM" MESH_HOME="$MH" MESH_LABEL_PREFIX="$PREFIX" \
    MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" TMUX_TMPDIR="$TH/tmux" \
    bun "$CLI" "$@"
}

# Does the daemon hand out the token in FILE? /pair/claim is the one route that reveals
# what the running process actually holds. Prints match | differs | claim-failed | down.
served_token() {
  bun -e '
    const [port, file] = process.argv.slice(1);
    const want = (await Bun.file(file).text()).trim();
    let p;
    try { p = await (await fetch(`http://127.0.0.1:${port}/pair/new`)).json(); }
    catch { console.log("down"); process.exit(0); }
    const r = await fetch(`http://127.0.0.1:${port}/pair/claim`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: p.code }),
    });
    if (!r.ok) { console.log("claim-failed"); process.exit(0); }
    console.log((await r.json()).token === want ? "match" : "differs");
  ' "$PORT" "$1"
}

wait_health() {
  i=0
  while [ "$i" -lt 60 ]; do
    curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && return 0
    i=$((i + 1)); sleep 0.25 2>/dev/null || sleep 1
  done
  return 1
}

# ---------- seed a throwaway install ----------

mkdir -p "$MH" "$TH/tmux"
cp -R "$ROOT/install/payload/meshd" "$MH/meshd"

# A realistic 64-hex seed. Generated into a FILE — never through an argv, or this check
# would itself put a token where `ps` can read it, which is the bug under test.
bun -e 'const b=new Uint8Array(32);crypto.getRandomValues(b);await Bun.write(process.argv[1],Array.from(b,x=>x.toString(16).padStart(2,"0")).join("")+"\n")' "$MH/token"
chmod 600 "$MH/token"
cp "$MH/token" "$TH/old-token"
printf '{"default":"seed","hosts":{"seed":{"ip":"10.0.0.9","port":8899,"token":"seed-host-token"}}}\n' > "$MH/hosts.json"
cp "$MH/hosts.json" "$TH/hosts.expected"

# Supervisor definitions in install.sh's exact shape. launchd and systemd replay their
# own copy of MESHD_TOKEN on every start — that is how they keep it out of `ps` — so a
# rotation that only rewrites the token file brings the daemon back on the OLD secret.
# Neither fixture is registered with a real supervisor (the files just exist), so the
# restart still falls through to tmux and nothing outside this directory is touched.
PLIST="$HM/Library/LaunchAgents/$PREFIX.meshd.plist"
UNIT="$HM/.config/systemd/user/$PREFIX-meshd.service"
mkdir -p "$(dirname "$PLIST")" "$(dirname "$UNIT")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>Label</key><string>$PREFIX.meshd</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>MESHD_TOKEN</key>
        <string>$(cat "$TH/old-token")</string>
        <key>MESHD_PORT</key>
        <string>8899</string>
    </dict>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
cat > "$UNIT" <<EOF
[Service]
Environment="PATH=/usr/bin:/bin"
Environment="MESHD_TOKEN=$(cat "$TH/old-token")"
Environment="MESHD_PORT=8899"
ExecStart=/usr/bin/bun run server.ts
EOF
chmod 600 "$PLIST" "$UNIT"
cp "$PLIST" "$TH/plist.before"; cp "$UNIT" "$TH/unit.before"

# Outside 8901-8999 (the upgrade trial-run scan) and 9100-9199 (check-mesh-upgrade).
PORT="$(bun -e 'for(let p=9200;p<9300;p++){try{Bun.serve({port:p,hostname:"127.0.0.1",fetch:()=>new Response("")}).stop(true);console.log(p);break}catch{}}')"
[ -n "$PORT" ] || fail "no free port in 9200-9299"

# Start the "before" daemon exactly the way the fixed code does: env in a 0600 file,
# sourced, so nothing in this check contradicts what it is asserting.
OLD_TOKEN="$(cat "$TH/old-token")"
( umask 077; cat > "$MH/meshd.env" <<EOF
MESHD_TOKEN=$OLD_TOKEN
MESHD_PORT=$PORT
MESHD_HOST=127.0.0.1
EOF
)
HOME="$HM" TMUX_TMPDIR="$TH/tmux" tmux new-session -d -s "$SESSION" -c "$MH/meshd" \
  "sh -c 'set -a; . \"\$0\"; set +a; exec bun run server.ts' $MH/meshd.env" \
  || fail "could not start the seed daemon in tmux"
wait_health || fail "the seed daemon never answered /health on 127.0.0.1:$PORT"

[ "$(served_token "$TH/old-token")" = "match" ] \
  || fail "baseline is wrong: the seed daemon is not serving the seeded token"

# ---------- a rotation nobody confirmed must not happen ----------

if run_mesh token rotate >"$TH/noconfirm.log" 2>&1 </dev/null; then
  fail "'mesh token rotate' with no --yes and no TTY exited 0 — it must refuse"
fi
grep -q -- '--yes' "$TH/noconfirm.log" || fail "the refusal does not mention --yes: $(cat "$TH/noconfirm.log")"
cmp -s "$MH/token" "$TH/old-token" || fail "the refused rotation still changed the token"

# ---------- the real rotation ----------

run_mesh token rotate --yes >"$TH/rotate.log" 2>&1 \
  || { cat "$TH/rotate.log"; fail "mesh token rotate exited nonzero"; }

grep -Eq '^[0-9a-f]{64}$' "$MH/token" || fail "the new token is not 64 hex characters"
[ "$(mode_of "$MH/token")" = "600" ] || fail "the new token file is mode $(mode_of "$MH/token"), not 600"
if cmp -s "$MH/token" "$TH/old-token"; then fail "the token did not actually change"; fi

BACKUP="$(ls -d "$MH"/token.bak-* 2>/dev/null | head -1)" || true
[ -n "${BACKUP:-}" ] && [ -f "$BACKUP" ] || fail "the old token was not kept as token.bak-* — that is a permanent lockout"
cmp -s "$BACKUP" "$TH/old-token" || fail "the backup does not hold the previous token"
[ "$(mode_of "$BACKUP")" = "600" ] || fail "the backup is mode $(mode_of "$BACKUP"), not 600"

cmp -s "$MH/hosts.json" "$TH/hosts.expected" || fail "hosts.json was modified by a token rotation"

# The supervisors' own copies must move too, or the next boot resurrects the leaked token.
for pair in "$PLIST:launchd plist" "$UNIT:systemd unit"; do
  f="${pair%%:*}"; what="${pair#*:}"
  grep -qFf "$TH/old-token" "$f" && fail "the $what still contains the OLD token — the next start would resurrect it"
  grep -qFf "$MH/token" "$f" || fail "the $what was not given the new token"
  [ "$(mode_of "$f")" = "600" ] || fail "the $what is mode $(mode_of "$f") after the rewrite, not 600"
done
# Nothing but that one value may change: these files also carry the port, KeepAlive and
# ExecStart, and a rotation that rewrites them wholesale would silently drop settings.
[ "$(grep -vFf "$TH/old-token" "$TH/plist.before" | wc -l)" = "$(grep -vFf "$MH/token" "$PLIST" | wc -l)" ] \
  || fail "the launchd plist changed by more than the token value"
grep -q 'KeepAlive' "$PLIST" || fail "the launchd plist lost KeepAlive"
grep -q 'ExecStart=/usr/bin/bun run server.ts' "$UNIT" || fail "the systemd unit lost its ExecStart"
grep -q 'Environment="MESHD_PORT=8899"' "$UNIT" || fail "the systemd unit lost MESHD_PORT"
[ -z "$(find "$MH" -maxdepth 1 -name '.token.new-*' 2>/dev/null)" ] || fail "a .token.new-* temp file was left behind"

wait_health || fail "nothing answers /health after the rotation — the machine is dark"

# The assertion the whole command exists for.
[ "$(served_token "$TH/old-token")" != "match" ] \
  || fail "the restarted daemon is STILL serving the OLD token — the rotation was cosmetic and the leaked token is live"
[ "$(served_token "$MH/token")" = "match" ] \
  || fail "the restarted daemon is not serving the new token (got: $(served_token "$MH/token"))"

# ---------- the token must not be visible in any command line ----------

[ -f "$MH/meshd.env" ] || fail "no $MH/meshd.env — the restart must keep the env off the command line"
[ "$(mode_of "$MH/meshd.env")" = "600" ] || fail "meshd.env is mode $(mode_of "$MH/meshd.env"), not 600"
grep -q '^MESHD_TOKEN=' "$MH/meshd.env" || fail "meshd.env does not carry MESHD_TOKEN, so the daemon lost its token"

# Match on the token VALUES, not on the string "MESHD_TOKEN": an unrelated process on
# this machine must never be able to turn this check red.
cat "$TH/old-token" "$MH/token" > "$TH/secrets"
{ ps ax -o args= 2>/dev/null || ps -eo args= 2>/dev/null; } > "$TH/ps.txt" || true
[ -s "$TH/ps.txt" ] || fail "could not read the process table"
if grep -qFf "$TH/secrets" "$TH/ps.txt"; then
  fail "a bearer token is visible in a process command line — every local user can read it with ps"
fi
TMUX_TMPDIR="$TH/tmux" tmux list-panes -a -F '#{pane_start_command}' > "$TH/panes.txt" 2>/dev/null || : > "$TH/panes.txt"
if grep -qFf "$TH/secrets" "$TH/panes.txt"; then
  fail "the tmux pane's start command embeds the token (tmux list-panes / ps exposes it)"
fi

# ---------- install.sh's tmux fallback: shape only ----------
#
# Not run (it needs `bun install` and the network), so this pins the shape instead:
# reintroducing `env $ss_flat ... bun run` there must turn this red.
INSTALL="$ROOT/install/install.sh"
grep -Fq 'ss_envfile="$MESH_HOME/$ss_name.env"' "$INSTALL" \
  || fail "install.sh's tmux fallback no longer writes a per-service env file"
grep -Fq 'set -a; . ' "$INSTALL" \
  || fail "install.sh's tmux fallback no longer sources that env file"
grep -Fq 'chmod 600 "$ss_envfile"' "$INSTALL" \
  || fail "install.sh does not lock its service env file to 0600"
if grep -Fq 'ss_flat' "$INSTALL"; then
  fail "install.sh still flattens the environment onto the tmux command line (ss_flat) — ps exposes MESHD_TOKEN"
fi

echo "check-token-rotate: OK (file+backup+modes, state preserved, daemon restarted and now serves the NEW token, no token in any argv)"

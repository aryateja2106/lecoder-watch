#!/bin/sh
# Proves mesh KB CLI wiring locally and, when opted in, federation across the live fleet.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/install/payload/bin/mesh"
SKILL="$ROOT/install/payload/share/skills/mesh-knowledge/SKILL.md"
command -v bun >/dev/null 2>&1 || { echo "check-kb-federation: SKIP (no bun)"; exit 0; }
command -v curl >/dev/null 2>&1 || { echo "check-kb-federation: SKIP (no curl)"; exit 0; }

TMP="$(mktemp -d)"
A_PID=""
B_PID=""
cleanup() {
  [ -z "$A_PID" ] || kill "$A_PID" 2>/dev/null || true
  [ -z "$B_PID" ] || kill "$B_PID" 2>/dev/null || true
  [ -z "$A_PID" ] || wait "$A_PID" 2>/dev/null || true
  [ -z "$B_PID" ] || wait "$B_PID" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM
fail() { echo "check-kb-federation: FAIL — $*"; exit 1; }

free_port() {
  bun -e 'for(let p=Number(process.argv[1]);p<Number(process.argv[1])+100;p++){try{Bun.serve({port:p,hostname:"127.0.0.1",fetch:()=>new Response("")}).stop(true);console.log(p);break}catch{}}' "$1"
}
PORT_A="$(free_port 9300)"
PORT_B="$(free_port 9400)"
[ -n "$PORT_A" ] && [ -n "$PORT_B" ] || fail "no free test ports"

mkdir -p "$TMP/a/.mesh" "$TMP/b/.mesh" "$TMP/cli"
TOKEN_A="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
TOKEN_B="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf '{"default":"a","hosts":{"a":{"ip":"127.0.0.1","port":%s,"token":"%s"},"b":{"ip":"127.0.0.1","port":%s,"token":"%s"}}}\n' \
  "$PORT_A" "$TOKEN_A" "$PORT_B" "$TOKEN_B" > "$TMP/cli/hosts.json"

HOME="$TMP/a" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT_A" MESHD_TOKEN="$TOKEN_A" \
  MESHD_KB_PATH="$TMP/a/kb.sqlite" MESHD_EVENTS_PATH="$TMP/a/events.jsonl" MESHD_TELEMETRY=off \
  bun "$ROOT/install/payload/meshd/server.ts" >"$TMP/a.log" 2>&1 &
A_PID=$!
HOME="$TMP/b" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT_B" MESHD_TOKEN="$TOKEN_B" \
  MESHD_KB_PATH="$TMP/b/kb.sqlite" MESHD_EVENTS_PATH="$TMP/b/events.jsonl" MESHD_TELEMETRY=off \
  bun "$ROOT/install/payload/meshd/server.ts" >"$TMP/b.log" 2>&1 &
B_PID=$!

for endpoint in "127.0.0.1:$PORT_A" "127.0.0.1:$PORT_B"; do
  i=0
  until curl -sf -o /dev/null "http://$endpoint/health" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt 50 ] || { cat "$TMP/a.log" "$TMP/b.log"; fail "throwaway daemon never came up at $endpoint"; }
    sleep 0.2
  done
done

run_mesh() { HOME="$TMP/a" MESH_HOME="$TMP/cli" bun "$CLI" "$@"; }
probe="kb-structural-$$"
# FTS5 indexes title/body/tags, not the key — the probe token goes in the title so search can find it.
run_mesh kb put checks "$probe" "KB structural probe $probe" "stored only on daemon B" --kind note --source check -H b > "$TMP/put"
run_mesh kb get checks "$probe" -H b > "$TMP/get"
grep -q 'KB structural probe' "$TMP/get" || fail "kb get did not return the note"
run_mesh kb search "$probe" --local -H b > "$TMP/search-b"
grep -q "checks/$probe" "$TMP/search-b" || fail "local kb search did not return the note"
run_mesh kb search "$probe" --local -H a > "$TMP/search-a"
[ ! -s "$TMP/search-a" ] || fail "--local leaked daemon B's note into daemon A"
curl -sf "http://127.0.0.1:$PORT_A/kb/search?q=$probe&federate=0" > "$TMP/direct-local.json"
grep -q '"results":\[\]' "$TMP/direct-local.json" || fail "federate=0 did not stay local"

# Loopback daemons cannot prove federation: kbFederateSearch requires a peer present in
# both hosts.json and `tailscale status --json`, and excludes this machine's own IPs.
# The opt-in live half below is the end-to-end federation proof.
[ -f "$SKILL" ] || fail "mesh-knowledge skill is missing"
head -1 "$SKILL" | grep -q '^---$' || fail "mesh-knowledge skill has no frontmatter"
grep -q '^name: mesh-knowledge$' "$SKILL" || fail "mesh-knowledge skill name is wrong"
grep -q '/search' "$SKILL" || fail "mesh-knowledge skill does not document /search"
grep -q '/remember' "$SKILL" || fail "mesh-knowledge skill does not document /remember"
run_mesh kb --help | grep -q 'mesh kb put' || fail "mesh kb --help has no usage"
run_mesh help kb | grep -q 'mesh kb search' || fail "mesh help kb has no usage"

if [ "${MESH_FLEET_LIVE:-0}" = "1" ]; then
  REMOTE="${MESH_REMOTE_HOST:-jetson}"
  live_probe="probe-$$"
  LIVE_MESH_HOME="${MESH_HOME:-$HOME/.mesh}"
  HOME="$HOME" MESH_HOME="$LIVE_MESH_HOME" bun "$CLI" kb put -H "$REMOTE" overnight "$live_probe" "kb probe $$" "written on $REMOTE" --json > "$TMP/live-put.json"
  HOME="$HOME" MESH_HOME="$LIVE_MESH_HOME" bun "$CLI" kb search "$live_probe" -H local --json > "$TMP/live-search.json"
  bun -e '
    const put = await Bun.file(process.argv[1]).json();
    const search = await Bun.file(process.argv[2]).json();
    if (!(search.results ?? []).some((r) => r.host === put.host && r.scope === "overnight" && r.key === process.argv[3])) process.exit(1);
  ' "$TMP/live-put.json" "$TMP/live-search.json" "$live_probe" || fail "local daemon did not federate the note from $REMOTE"
fi

echo "check-kb-federation: OK"

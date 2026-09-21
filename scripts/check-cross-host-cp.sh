#!/bin/sh
# Proves raw daemon file writes and `mesh cp` round trips without touching the live fleet.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=8934
command -v bun >/dev/null 2>&1 || { echo "check-cross-host-cp: SKIP (no bun)"; exit 0; }
if curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/health" 2>/dev/null; then
  echo "check-cross-host-cp: FAIL — something already listens on :$PORT"
  exit 1
fi

TMP="$(mktemp -d)"
HM="$TMP/home"
MH="$HM/.mesh"
DAEMON_PID=""
mkdir -p "$MH"
head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$MH/token"
TOKEN="$(cat "$MH/token")"

stop_daemon() {
  if [ -n "$DAEMON_PID" ]; then
    kill "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true
    DAEMON_PID=""
  fi
}
cleanup() {
  stop_daemon
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM
fail() { echo "check-cross-host-cp: FAIL — $*"; exit 1; }

start_daemon() {
  limit="$1"
  MESHD_TOKEN="$TOKEN" HOME="$HM" MESH_HOME="$MH" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" \
    MESHD_FS_WRITE_MAX="$limit" MESHD_EVENTS_PATH="$TMP/events.jsonl" \
    MESHD_EXPOSURES_PATH="$TMP/exposures.json" MESHD_TELEMETRY=off \
    bun "$ROOT/install/payload/meshd/server.ts" >"$TMP/meshd.log" 2>&1 &
  DAEMON_PID=$!
  i=0
  until curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt 50 ] || { cat "$TMP/meshd.log"; fail "throwaway daemon never came up"; }
    sleep 0.2
  done
}

status_post() {
  path="$1"; file="$2"
  curl -sS -o "$TMP/response.json" -w '%{http_code}' -H "Authorization: Bearer $TOKEN" \
    -H 'content-type: application/octet-stream' --data-binary "@$file" \
    "http://127.0.0.1:$PORT/fs/write?$path"
}
json_field() {
  bun -e 'const j=await Bun.file(process.argv[1]).json();console.log(j[process.argv[2]] ?? "")' "$1" "$2"
}

start_daemon ""
dd if=/dev/urandom of="$TMP/five.bin" bs=1048576 count=5 2>/dev/null
want_sha="$(shasum -a 256 "$TMP/five.bin" | awk '{print $1}')"
code="$(status_post "path=$TMP/written.bin" "$TMP/five.bin")"
[ "$code" = 201 ] || fail "5 MiB write returned HTTP $code: $(cat "$TMP/response.json")"
[ "$(json_field "$TMP/response.json" sha256)" = "$want_sha" ] || fail "write sha256 did not match shasum"
[ "$(json_field "$TMP/response.json" bytes)" = 5242880 ] || fail "write byte count was not 5242880"

code="$(status_post "path=$TMP/written.bin" "$TMP/five.bin")"
[ "$code" = 409 ] || fail "second write without overwrite returned HTTP $code"
code="$(status_post "path=$TMP/written.bin&overwrite=1" "$TMP/five.bin")"
[ "$code" = 201 ] || fail "overwrite=1 returned HTTP $code"
code="$(status_post "path=$HM/.mesh/x" "$TMP/five.bin")"
[ "$code" = 403 ] || fail "write inside ~/.mesh returned HTTP $code"
code="$(status_post "path=$TMP/missing/child.bin" "$TMP/five.bin")"
[ "$code" = 404 ] || fail "missing parent returned HTTP $code"
code="$(status_post "path=$TMP/made/child.bin&mkdirs=1" "$TMP/five.bin")"
[ "$code" = 201 ] || fail "mkdirs=1 returned HTTP $code"

curl -sS -D "$TMP/read.headers" -o "$TMP/read.bin" -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:$PORT/fs/read?path=$TMP/written.bin&raw=1"
cmp -s "$TMP/five.bin" "$TMP/read.bin" || fail "raw read bytes differ"
header_sha="$(awk 'tolower($1)=="x-mesh-sha256:" { gsub("\r", "", $2); print $2 }' "$TMP/read.headers")"
[ "$header_sha" = "$want_sha" ] || fail "x-mesh-sha256 header did not match"

printf '{"default":"t","hosts":{"t":{"ip":"127.0.0.1","port":%s,"token":"%s"}}}\n' "$PORT" "$TOKEN" > "$MH/hosts.json"
HOME="$HM" MESH_HOME="$MH" bun "$ROOT/install/payload/bin/mesh" cp "$TMP/five.bin" "t:$TMP/copy.bin" >/dev/null \
  || fail "CLI local-to-remote copy failed"
HOME="$HM" MESH_HOME="$MH" bun "$ROOT/install/payload/bin/mesh" cp "t:$TMP/copy.bin" "$TMP/back.bin" >/dev/null \
  || fail "CLI remote-to-local copy failed"
[ "$(shasum -a 256 "$TMP/back.bin" | awk '{print $1}')" = "$want_sha" ] || fail "CLI round-trip sha256 differs"

stop_daemon
start_daemon 1024
dd if=/dev/urandom of="$TMP/too-big.bin" bs=2048 count=1 2>/dev/null
code="$(status_post "path=$TMP/rejected.bin" "$TMP/too-big.bin")"
[ "$code" = 413 ] || fail "oversize write returned HTTP $code"
[ ! -e "$TMP/rejected.bin" ] || fail "oversize write created its destination"
find "$TMP" -name 'rejected.bin.part-*' -print | grep -q . && fail "oversize write left a .part file"

if [ "${MESH_FLEET_LIVE:-0}" = 1 ]; then
  REMOTE="${MESH_REMOTE_HOST:-jetson}"
  # THIS tree's CLI against the real fleet (the installed ~/.mesh/bin/mesh may predate `cp`);
  # the daemons on the remote hosts must already run a build with /fs/write.
  LIVE_MESH="$ROOT/install/payload/bin/mesh"
  LOCAL="$HOME/Downloads/mesh-cp-check-$$.txt"
  REMOTE_FILE="/tmp/mesh-cp-check-$$.txt"
  SESSION="mesh-cp-clean-$$"
  trap 'rm -f "$LOCAL"; "$LIVE_MESH" new "$SESSION" -H "$REMOTE" --cmd "sh -c '\''rm -f $REMOTE_FILE'\''" >/dev/null 2>&1 || true; sleep 1; "$LIVE_MESH" kill "$SESSION" -H "$REMOTE" >/dev/null 2>&1 || true; cleanup' EXIT INT TERM
  "$LIVE_MESH" cp "$REMOTE:/etc/hostname" "$LOCAL" --force || fail "live remote-to-local copy failed"
  grep -q '[[:alnum:]]' "$LOCAL" || fail "live /etc/hostname copy is empty"
  "$LIVE_MESH" cp "$LOCAL" "$REMOTE:$REMOTE_FILE" --force || fail "live local-to-remote copy failed"
fi

echo "check-cross-host-cp: OK"

#!/bin/sh
# check-agent-new-latency.sh — the 900ms toll on session creation must stay dead.
#
# POST /agents/new with initialText used to sleep a flat 900ms before sending — 943ms
# of a measured 989ms round trip (issue #117; a bun→rust rewrite was proposed over what
# was one hardcoded setTimeout). The fix polls the fresh pane for a drawn prompt every
# 50ms with the old sleep surviving only as a 1200ms ceiling. Measured on the live
# daemon 2026-08-29: 1019ms before, then the polled version after (see the commit).
#
# Structural half (always runs): no flat setTimeout toll may reappear on the
# initialText path, and the readiness poll must still be there.
#
# Live half (opt-in, MESH_LATENCY_LIVE=1): creates a scratch session against the local
# daemon, times the round trip, and deletes it. Opt-in because check-all runs must not
# mutate the developer's real mesh on every invocation.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/install/payload/meshd/server.ts"

if grep -qE 'setTimeout\(resolve, *900\)' "$SERVER"; then
  echo "check-agent-new-latency: FAIL — the flat 900ms sleep is back on the initialText path"
  exit 1
fi
if ! grep -q 'capture-pane' "$SERVER"; then
  echo "check-agent-new-latency: FAIL — the readiness poll (capture-pane) is gone; initialText would type into a pane with no reader"
  exit 1
fi

if [ "${MESH_LATENCY_LIVE:-}" != "1" ]; then
  echo "check-agent-new-latency: OK (structural; set MESH_LATENCY_LIVE=1 to time the live daemon)"
  exit 0
fi

TOKEN_FILE="$HOME/.mesh/token"
[ -r "$TOKEN_FILE" ] || { echo "check-agent-new-latency: SKIP live (no ~/.mesh/token)"; exit 0; }
TOKEN="$(cat "$TOKEN_FILE")"
NAME="latency-check-$$"
MS=$(python3 - "$TOKEN" "$NAME" <<'PY'
import json, sys, time, urllib.request
token, name = sys.argv[1], sys.argv[2]
body = json.dumps({"name": name, "initialText": "true\n"}).encode()
req = urllib.request.Request("http://127.0.0.1:8899/agents/new", data=body, method="POST",
    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
t0 = time.time()
urllib.request.urlopen(req, timeout=10).read()
print(int((time.time() - t0) * 1000))
PY
) || { echo "check-agent-new-latency: SKIP live (daemon not answering)"; exit 0; }
curl -s -m 5 -X DELETE -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8899/agents/$NAME" >/dev/null || true

if [ "$MS" -ge 800 ]; then
  echo "check-agent-new-latency: FAIL — live /agents/new with initialText took ${MS}ms (>= 800ms; the toll is back or the pane never paints)"
  exit 1
fi
echo "check-agent-new-latency: OK (live round trip ${MS}ms)"

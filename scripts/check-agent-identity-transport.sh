#!/bin/sh
# check-agent-identity-transport.sh — two ways a session identity gets silently lost in
# transit, both verified against a live daemon before this file existed.
#
# 1. THE URL. meshd routes on `^/agents/([^/]+)/send$`. Swift built that segment with the
#    raw name, and the two call sites that did encode used `.urlPathAllowed`, which
#    deliberately PERMITS `/` because it is meant for a whole path. So any identity that
#    is not a bare mux name — a cwd, a worktree path, a Claude session_id — produced
#    `/agents//Users/x/y/send` and 404'd before session resolution was attempted.
#    Measured live: raw segment -> 404, percent-encoded -> 200.
#
# 2. THE HOOK'S EXIT STATUS. mesh-hook is registered on Stop, and Claude Code treats a
#    Stop hook exiting 2 as a BLOCKING error — it refuses to end the turn and loops. The
#    deployed hook returns 2 when it cannot read a token. Telemetry must never be able to
#    hold a session open, so no input may make it exit non-zero.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/Shared/MeshClient.swift"
HOOK="$ROOT/install/payload/bin/mesh-hook"
ok=1
bad() { echo "FAIL: check-agent-identity-transport.sh: $1"; ok=0; }

# --- 1. every /agents/<segment> is encoded, and the encoder drops '/' ---
raw="$(grep -n 'agents/\\(' "$CLIENT" | grep -v 'Self.pathSegment' || true)"
if [ -n "$raw" ]; then
  bad "an /agents path segment is interpolated raw, so a path-shaped session 404s:"
  printf '    %s\n' "$raw"
fi
# grep -E with an anchor, not a bare substring: a commented-out `// set.remove("/")`
# still contains the substring, and the first version of this check passed against
# exactly that mutation.
awk '/static let pathSegmentAllowed/,/}\(\)/' "$CLIENT" | grep -qE '^[[:space:]]*set\.remove\("/"\)' \
  || bad "the path-segment encoder no longer removes '/', which is the only character that matters here"
grep -q 'static func pathSegment' "$CLIENT" \
  || bad "MeshClient.pathSegment is gone — segments are being built by hand again"

# --- 2. the hook cannot exit non-zero, whatever happens ---
command -v python3 >/dev/null 2>&1 || { echo "check-agent-identity-transport: SKIP (no python3)"; exit 0; }
for probe in token badflag; do
  case "$probe" in
    token)   out=$(printf '{"hook_event_name":"Stop"}' | env -u MESHD_TOKEN MESH_HOME=/nonexistent-mesh-home \
               python3 "$HOOK" --source claude 2>/dev/null || echo "EXIT:$?") ;;
    badflag) out=$(printf '{}' | python3 "$HOOK" --definitely-not-a-flag 2>/dev/null || echo "EXIT:$?") ;;
  esac
  case "$out" in
    *EXIT:*) bad "mesh-hook exits non-zero on the '$probe' path; registered on Stop, that WEDGES the session" ;;
  esac
done
grep -q 'raise SystemExit(0)' "$HOOK" \
  || bad "mesh-hook no longer forces a zero exit at its entry point"

[ "$ok" -eq 1 ] || exit 1
echo "check-agent-identity-transport: OK (identities survive the URL; the hook can never block a turn)"

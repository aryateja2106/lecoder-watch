#!/usr/bin/env bash
# stop-published.sh — Stop hook for the 2026-09-22 publish mission: the session may not
# stop until `MESH_PUBLISHED=1 sh scripts/check-published.sh` exits 0.
#
# Wired from .claude/settings.local.json (machine-local, never committed) so it binds only
# the session that is driving the publish, not every future session in this repo.
#
# Reads the Stop event as JSON on stdin. On a red check it answers
#   {"decision":"block","reason":"<the failing lines>"}
# so the agent keeps working. The escape hatch the mission asked for: when the SAME first
# failing assertion has been red 25 times in a row with NO new commit between attempts,
# the hook lets the session stop and prints the blocker instead of looping forever.
# State lives in .omc/state/check-published-stop.json (gitignored).
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 0
INPUT="$(cat)"
STATE_DIR="$ROOT/.omc/state"
STATE="$STATE_DIR/check-published-stop.json"
LIMIT=25
mkdir -p "$STATE_DIR"

# Never start a check-all while one is already running: both drive the same simulator and
# kill each other's test runner, so the collision gets blamed on the code. Block the stop
# with the honest reason instead — a run in flight is not a pass.
RACING="$(pgrep -fl 'scripts/check-all\.sh|scripts/gates\.sh|scripts/release-mesh-install\.sh|xcodebuild test' 2>/dev/null | grep -v stop-published || true)"
if [ -n "$RACING" ]; then
  REASON="A gate run is already in flight, so check-published was not started (it would race it on the simulator). Wait for that run, then stop again:
$(printf '%s' "$RACING" | head -3)"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$REASON" '{decision:"block", reason:$r}'
  else
    printf '%s\n' "$REASON" >&2
    exit 2
  fi
  exit 0
fi

# Run the finish line. Its stdout is the evidence either way.
OUT="$(MESH_PUBLISHED=1 sh "$ROOT/scripts/check-published.sh" 2>&1)"
RC=$?
printf '%s\n' "$OUT" >"$STATE_DIR/check-published-last.log"

if [ "$RC" -eq 0 ]; then
  rm -f "$STATE"
  exit 0
fi

FIRST="$(printf '%s\n' "$OUT" | grep -E '^FAIL: check-published:' | head -1 | sed 's/^FAIL: check-published: //' | cut -d' ' -f1-3)"
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo none)"

count=0; prev_check=""; prev_head=""
if [ -f "$STATE" ] && command -v jq >/dev/null 2>&1; then
  prev_check="$(jq -r '.check // ""' "$STATE" 2>/dev/null)"
  prev_head="$(jq -r '.head // ""' "$STATE" 2>/dev/null)"
  count="$(jq -r '.count // 0' "$STATE" 2>/dev/null)"
fi
if [ "$prev_check" = "$FIRST" ] && [ "$prev_head" = "$HEAD_SHA" ]; then
  count=$((count + 1))
else
  count=1
fi
if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$FIRST" --arg h "$HEAD_SHA" --argjson n "$count" '{check:$c, head:$h, count:$n}' >"$STATE"
fi

FAILS="$(printf '%s\n' "$OUT" | grep -E '^FAIL: check-published:' | head -12)"

if [ "$count" -ge "$LIMIT" ]; then
  # stop_hook_active escape: same assertion, same HEAD, LIMIT attempts — hand back.
  cat <<EOF
check-published has failed $count times in a row on the same assertion with no new commit:
  $FIRST
Stopping so a human can unblock it. Record it in BLOCKED.md. Full output:
$FAILS
EOF
  exit 0
fi

REASON="$(printf 'check-published.sh is red (attempt %s/%s on this assertion at %s). Not published yet. Fix these, commit, push, then stop:\n%s' "$count" "$LIMIT" "${HEAD_SHA:0:7}" "$FAILS")"
if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "$REASON" '{decision:"block", reason:$r}'
else
  printf '%s\n' "$REASON" >&2
  exit 2
fi
exit 0

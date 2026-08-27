#!/bin/sh
# check-codex-state.sh — the rollout reader, against fixtures that encode the exact traps
# measured on a real stalled session (2026-08-27, "Polish LeSearch.ai landing page").
#
# The trap that matters: the reset epoch is NOT on the newest token_count line. On the real
# incident the newest carried limit_id "premium" with primary:null — the credits pool —
# while the usable snapshot sat one line earlier. A reader that takes the last token_count
# reads null and silently never arms, which for a feature whose entire job is to fire
# hours later is the worst possible failure: it looks fine and does nothing.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-codex-state: SKIP (no bun)"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mk() { # $1=file  $2=stop-line
  {
    printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":99.0,"window_minutes":300,"resets_at":1787804714}}}}'
    printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":100.0,"window_minutes":300,"resets_at":1787804714}}}}'
    # Two decoys, both newer than the usable line.
    #  (a) exactly what the real incident carried: wrong pool, primary null.
    #  (b) the dangerous one: wrong pool with a POPULATED primary and a different
    #      resets_at. Without the limit_id=="codex" guard a reader takes this and arms
    #      for 03:00 instead of 09:55 — wrong by hours, and it still looks like it works.
    printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"premium","primary":{"used_percent":42.0,"window_minutes":10080,"resets_at":1787700000}}}}'
    printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"premium","primary":null,"secondary":null}}}'
    printf '%s\n' "$2"
  } > "$1"
}
LIMIT='{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":null,"error":{"message":"You'"'"'ve hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro)","codex_error_info":"usage_limit_exceeded"}}}'
DONE='{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"all set"}}'
ABORT='{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}'
mk "$TMP/limit.jsonl"  "$LIMIT"
mk "$TMP/done.jsonl"   "$DONE"
mk "$TMP/abort.jsonl"  "$ABORT"

cat > "$TMP/t.ts" <<'TS'
import { readStopReason, isResumable } from "./codex-state.ts";
const dir = process.argv[2];
let bad = 0;
const say = (m: string) => { console.log(`FAIL: ${m}`); bad = 1; };

const limit = await readStopReason(`${dir}/limit.jsonl`);
if (limit.stopped !== "limit") say(`usage_limit_exceeded must read as "limit", got "${limit.stopped}"`);
if (limit.resetsAtMs !== 1787804714000)
  say(`the reset epoch must come from the newest limit_id=="codex" snapshot, not the newest token_count; got ${limit.resetsAtMs}`);
if (limit.usedPercent !== 100) say(`used_percent should be 100, got ${limit.usedPercent}`);
if (!isResumable(limit)) say("a real limit stop with a reset time must be resumable");

const done = await readStopReason(`${dir}/done.jsonl`);
if (done.stopped !== "done") say(`a clean finish must read as "done", got "${done.stopped}"`);
if (isResumable(done)) say("a finished session must NOT be resumable — typing at it starts work nobody asked for");

const abort = await readStopReason(`${dir}/abort.jsonl`);
if (abort.stopped !== "interrupted") say(`turn_aborted must read as "interrupted", got "${abort.stopped}"`);
if (isResumable(abort)) say("a human-interrupted session must NOT be resumable — stopping it was a deliberate choice");

const missing = await readStopReason(`${dir}/nope.jsonl`);
if (missing.stopped !== "unknown") say(`an unreadable rollout must read as "unknown", got "${missing.stopped}"`);
if (isResumable(missing)) say("an unreadable rollout must never be treated as resumable");

if (bad) process.exit(1);
console.log("check-codex-state: OK (limit/done/interrupted/unknown separate; epoch survives the premium decoy)");
TS
cp "$ROOT/install/payload/meshd/codex-state.ts" "$TMP/codex-state.ts"
cd "$TMP" && bun run "$TMP/t.ts" "$TMP"

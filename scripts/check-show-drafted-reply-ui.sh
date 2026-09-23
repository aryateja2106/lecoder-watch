#!/bin/sh
# Wiring only. After a draft returns, show that reply on the answer already
# on screen. A held or failed draft leaves the answer alone.
# This script does not start a daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_STORE="$ROOT/iOS/MeshStore.swift"
WATCH_STORE="$ROOT/Watch/WatchMeshStore.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$IOS_STORE" "$WATCH_STORE"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-show-drafted-reply-ui: FAILED"; exit 1; }

python3 - "$IOS_STORE" "$WATCH_STORE" << 'PY'
import sys

ios_path, watch_path = sys.argv[1:3]
fail = []

def bad(msg):
    fail.append(msg)

def matching_brace(src, open_idx):
    depth = 0
    for i in range(open_idx, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return -1

def extract_func(src, name):
    marker = "func " + name
    start = src.find(marker)
    if start < 0:
        bad("missing func %s" % name)
        return ""
    brace = src.find("{", start)
    if brace < 0:
        bad("func %s has no body" % name)
        return ""
    end = matching_brace(src, brace)
    if end < 0:
        bad("func %s is unclosed" % name)
        return ""
    return src[start:end + 1]

def check_store(label, path):
    src = open(path, encoding="utf-8").read()
    action = extract_func(src, "draftShownAnswer")
    if not action:
        return
    guard = "guard !drafted.held, let reply = drafted.reply, !reply.isEmpty else { return }"
    assign = "knowledgeAnswer = reply"
    call = "draftAgentNote(id:"
    guard_at = action.find(guard)
    assign_at = action.find(assign)
    call_at = action.find(call)
    if call_at < 0 or "confirm: true" not in action[call_at:call_at + 80]:
        bad("%s draftShownAnswer does not confirm the draft" % label)
    if guard_at < 0:
        bad("%s draftShownAnswer does not return when the reply is held or empty" % label)
    elif call_at >= 0 and guard_at < call_at:
        bad("%s held return comes before the draft call" % label)
    if assign_at < 0:
        bad("%s draftShownAnswer does not assign knowledgeAnswer = reply" % label)
    elif guard_at >= 0 and assign_at < guard_at:
        bad("%s assigns knowledgeAnswer before the held return" % label)
    if action.count(assign) != 1:
        bad("%s knowledgeAnswer = reply appears %s times" % (label, action.count(assign)))
    caught = action.rfind("} catch {")
    if caught < 0:
        bad("%s draftShownAnswer has no catch" % label)
    else:
        brace = action.find("{", caught)
        end = matching_brace(action, brace) if brace >= 0 else -1
        body = action[brace + 1:end] if end > brace else ""
        if body.strip() != "return":
            bad("%s error return changes state: %r" % (label, body.strip()))
    zero = action.find("matches.count == 1 else { return }")
    if zero < 0:
        bad("%s zero or several matches do not return" % label)
    title = action.find("guard read.title == titled else { return }")
    if title < 0:
        bad("%s a mismatched read title does not return" % label)

check_store("phone", ios_path)
check_store("watch", watch_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-show-drafted-reply-ui: OK")
PY

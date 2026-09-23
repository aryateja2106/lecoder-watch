#!/bin/sh
# Wiring only. A new ask or draft clears the spoken title.
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
[ "$fail" = "0" ] || { echo "check-clear-spoken-title-ui: FAILED"; exit 1; }

python3 - "$IOS_STORE" "$WATCH_STORE" << 'PY'
import sys

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
        return ""
    end = matching_brace(src, brace)
    if end < 0:
        return ""
    return src[start:end + 1]

CLEAR = "knowledgeDraftFile = nil\n                knowledgeSpokenTitle = nil"
DRAFT = "knowledgeAnswer = reply\n                knowledgeSpokenTitle = nil\n                knowledgeDraftFile = Self.heldDraftFile(drafted.draft)"

def check_store(label, path):
    src = open(path, encoding="utf-8").read()
    ask = extract_func(src, "askCurrentKnowledgeNote")
    if ask.count(CLEAR) != 2:
        bad("%s ask clears the spoken title %s times" % (label, ask.count(CLEAR)))
    for name in ("draftShownAnswer", "draftLoadedNote"):
        action = extract_func(src, name)
        if action.count(DRAFT) != 1:
            bad("%s %s does not clear the spoken title when the reply is shown" % (label, name))
    shown = extract_func(src, "speakShownAnswer")
    if "knowledgeSpokenTitle" in shown:
        bad("%s speakShownAnswer assigns knowledgeSpokenTitle" % label)
    speak = extract_func(src, "speakKnowledgeNote")
    if speak.count("knowledgeSpokenTitle = spoken.title") != 1:
        bad("%s speakKnowledgeNote no longer records a spoken title" % label)

for label, path in (("phone", sys.argv[1]), ("watch", sys.argv[2])):
    check_store(label, path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-clear-spoken-title-ui: OK")
PY

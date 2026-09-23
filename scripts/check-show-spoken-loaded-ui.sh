#!/bin/sh
# Wiring only. A loaded note shows Spoken when that title was spoken and no answer is on screen.
# This script does not start a daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_VIEWS="$ROOT/iOS/ContentView.swift"
WATCH_VIEWS="$ROOT/Watch/WatchViews.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$IOS_VIEWS" "$WATCH_VIEWS"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-show-spoken-loaded-ui: FAILED"; exit 1; }

python3 - "$IOS_VIEWS" "$WATCH_VIEWS" << 'PY'
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

def extract_struct(src, name):
    marker = "struct " + name
    start = src.find(marker)
    if start < 0:
        bad("missing struct %s" % name)
        return ""
    brace = src.find("{", start)
    if brace < 0:
        return ""
    end = matching_brace(src, brace)
    if end < 0:
        return ""
    return src[start:end + 1]

BLOCK = """                Button(\"Speak\") { confirmingSpeak = true }
                    .disabled(namedNote.isEmpty || store.loadedKnowledgeNote?.title != namedNote)
                if store.knowledgeAnswer?.isEmpty != false,
                    store.knowledgeSpokenTitle == namedNote, !namedNote.isEmpty {
                    Text(\"Spoken \\(namedNote)\").font(.caption2)
                }"""

KEPT = """if store.knowledgeSpokenTitle == keptTitle, !keptTitle.isEmpty {
                        Text(\"Spoken \\(keptTitle)\").font(.caption2)
                    }"""

def check(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    if view.count(BLOCK) != 1:
        bad("%s loaded spoken block appears %s times" % (label, view.count(BLOCK)))
    if view.count(KEPT) != 1:
        bad("%s kept caption appears %s times" % (label, view.count(KEPT)))
    ask = view.find("Section(\"Ask\")")
    block_at = view.find(BLOCK)
    if ask < 0 or block_at < 0 or block_at > ask:
        bad("%s loaded spoken caption is not before Ask" % label)
    ask_line = view.find("else if let line = store.knowledgeAskLine")
    if ask_line >= 0 and "Spoken" in view[ask_line:ask_line + 400]:
        bad("%s ask-line branch shows Spoken" % label)

check("phone", sys.argv[1])
check("watch", sys.argv[2])

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-show-spoken-loaded-ui: OK")
PY

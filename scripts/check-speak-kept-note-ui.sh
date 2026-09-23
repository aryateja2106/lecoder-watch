#!/bin/sh
# Wiring only. Speak kept speaks the note Keep just loaded.
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
[ "$fail" = "0" ] || { echo "check-speak-kept-note-ui: FAILED"; exit 1; }

python3 - "$IOS_VIEWS" "$WATCH_VIEWS" << 'PY'
import sys

ios_views_path, watch_views_path = sys.argv[1:3]
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
        bad("struct %s has no body" % name)
        return ""
    end = matching_brace(src, brace)
    if end < 0:
        bad("struct %s is unclosed" % name)
        return ""
    return src[start:end + 1]

def block_from(src, marker_at):
    brace = src.find("{", marker_at)
    if brace < 0:
        return -1, ""
    end = matching_brace(src, brace)
    if end < 0:
        return -1, ""
    return end, src[brace + 1:end]

def check_view(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    if view.count("@State private var confirmingSpeakKept = false") != 1:
        bad("%s confirmingSpeakKept appears %s times" % (label, view.count("@State private var confirmingSpeakKept = false")))
    button = """Button(\"Speak kept\") { confirmingSpeakKept = true }
                        .disabled(keptTitle.isEmpty || store.loadedKnowledgeNote?.title != keptTitle)"""
    if view.count(button) != 1:
        bad("%s Speak kept button appears %s times" % (label, view.count(button)))
    ask_line = view.find("else if let line = store.knowledgeAskLine")
    if ask_line >= 0 and "Speak kept" in view[ask_line:ask_line + 400]:
        bad("%s Speak kept is in the ask-line branch" % label)
    dialog = "confirmationDialog(\"Speak this kept note?\""
    if view.count(dialog) != 1:
        bad("%s Speak kept dialog appears %s times" % (label, view.count(dialog)))
    at = view.find(dialog)
    if at < 0:
        return
    end, body = block_from(view, at)
    if end < 0:
        bad("%s Speak kept dialog is unclosed" % label)
        return
    call = "speakKnowledgeNote(host: host, title: keptTitle, confirmed: true)"
    if body.count(call) != 1:
        bad("%s Speak kept dialog does not call speakKnowledgeNote with the kept title" % label)
    if "speakShownAnswer(" in body:
        bad("%s Speak kept dialog calls speakShownAnswer" % label)
    old = view.find("confirmationDialog(\"Speak this note?\"")
    if old < 0 or old > at:
        bad("%s Speak kept dialog is not after Speak this note" % label)
    if view.count("speakShownAnswer(") != 1:
        bad("%s speakShownAnswer appears %s times" % (label, view.count("speakShownAnswer(")))

check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-speak-kept-note-ui: OK")
PY

#!/bin/sh
# Wiring only. When the saved reply's title is the question, the ask screen
# shows that title and body. This script does not start a daemon.
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
[ "$fail" = "0" ] || { echo "check-show-saved-reply-note-ui: FAILED"; exit 1; }

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

def block_from(src, header_at):
    brace = src.find("{", header_at)
    if brace < 0:
        return -1, -1, ""
    end = matching_brace(src, brace)
    if end < 0:
        return brace, -1, ""
    return brace, end, src[brace + 1:end]

def check_view(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    marker = ".onChange(of: store.loadedKnowledgeNote)"
    at = view.find(marker)
    if at < 0:
        bad("%s ask screen has no loadedKnowledgeNote onChange" % label)
        return
    _, end, body = block_from(view, at)
    if end < 0:
        bad("%s loadedKnowledgeNote onChange is unclosed" % label)
        return
    named = "if loaded.title == namedNote"
    question = "else if loaded.title == question"
    named_at = body.find(named)
    question_at = body.find(question)
    if named_at < 0:
        bad("%s ask screen has no namedNote branch" % label)
        return
    if question_at < 0:
        bad("%s ask screen has no else if loaded.title == question branch" % label)
        return
    _, named_end, named_body = block_from(body, named_at)
    if named_end < 0:
        bad("%s namedNote branch is unclosed" % label)
        return
    if question_at < named_end:
        bad("%s question branch is inside the namedNote branch" % label)
        return
    if "noteBody = loaded.body" not in named_body:
        bad("%s namedNote branch does not assign noteBody = loaded.body" % label)
    _, question_end, question_body = block_from(body, question_at)
    if question_end < 0:
        bad("%s question branch is unclosed" % label)
        return
    if "note = loaded.title" not in question_body:
        bad("%s question branch does not assign note" % label)
    if "noteBody = loaded.body" not in question_body:
        bad("%s question branch does not assign noteBody" % label)

check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-show-saved-reply-note-ui: OK")
PY

#!/bin/sh
# Wiring only. After Keep, the Note and Body fields show the new note.
# This script does not start a daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_STORE="$ROOT/iOS/MeshStore.swift"
WATCH_STORE="$ROOT/Watch/WatchMeshStore.swift"
IOS_VIEWS="$ROOT/iOS/ContentView.swift"
WATCH_VIEWS="$ROOT/Watch/WatchViews.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$IOS_STORE" "$WATCH_STORE" "$IOS_VIEWS" "$WATCH_VIEWS"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-show-kept-note-ui: FAILED"; exit 1; }

python3 - "$IOS_STORE" "$WATCH_STORE" "$IOS_VIEWS" "$WATCH_VIEWS" << 'PY'
import sys

ios_store_path, watch_store_path, ios_views_path, watch_views_path = sys.argv[1:5]
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

ASSIGN = "loadedKnowledgeNote = KnowledgeNote(id: saved.id, title: saved.title, body: text)"

def check_store(label, path):
    src = open(path, encoding="utf-8").read()
    action = extract_func(src, "keepShownDraft")
    if not action:
        return
    call = "let saved = try await c.createKnowledgeNote(title: titled, body: text)"
    if action.count(call) != 1:
        bad("%s create assignment appears %s times" % (label, action.count(call)))
    gate = "if saved.title == titled {"
    if action.count(gate) != 1:
        bad("%s title gate appears %s times" % (label, action.count(gate)))
    if action.count(ASSIGN) != 1:
        bad("%s kept-note assignment appears %s times" % (label, action.count(ASSIGN)))
    gate_at = action.find(gate)
    assign_at = action.find(ASSIGN)
    if gate_at < 0 or assign_at < gate_at:
        bad("%s assignment is not inside the title gate" % label)
    load_at = action.find("loadKnowledgeNotes(host: host)")
    if load_at < assign_at:
        bad("%s list refresh is not after the kept note is shown" % label)
    catch_at = action.rfind("catch")
    if catch_at >= 0 and "loadedKnowledgeNote" in action[catch_at:]:
        bad("%s catch assigns loadedKnowledgeNote" % label)
    for forbidden in ("knowledgeAnswer =", "knowledgeDraftFile =", "currentKnowledgeNote =", "knowledgeAskLine =", "replaceKnowledgeNote", "readKnowledgeNote"):
        if forbidden in action:
            bad("%s keepShownDraft contains %s" % (label, forbidden))

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
    kept = "private var keptTitle: String {"
    if view.count(kept) != 1:
        bad("%s keptTitle appears %s times" % (label, view.count(kept)))
    if "String(line.prefix(200))" not in view:
        bad("%s keptTitle does not clip to 200 characters" % label)
    marker = ".onChange(of: store.loadedKnowledgeNote)"
    at = view.find(marker)
    if at < 0:
        bad("%s ask screen has no loadedKnowledgeNote onChange" % label)
        return
    end, body = block_from(view, at)
    if end < 0:
        bad("%s loadedKnowledgeNote onChange is unclosed" % label)
        return
    named = "if loaded.title == namedNote"
    question = "else if loaded.title == question"
    third = "else if loaded.title == keptTitle"
    named_at = body.find(named)
    question_at = body.find(question)
    third_at = body.find(third)
    if named_at < 0 or question_at < named_at or third_at < question_at:
        bad("%s kept branch is not after the named note and the question" % label)
        return
    _, third_body = block_from(body, third_at)
    if "note = loaded.title" not in third_body or "noteBody = loaded.body" not in third_body:
        bad("%s kept branch does not fill Note and Body" % label)
    named_end, named_body = block_from(body, named_at)
    if "note = loaded.title" in named_body:
        bad("%s namedNote branch assigns the title" % label)
    if third_at < named_end:
        bad("%s kept branch is inside the namedNote branch" % label)

check_store("phone", ios_store_path)
check_store("watch", watch_store_path)
check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-show-kept-note-ui: OK")
PY

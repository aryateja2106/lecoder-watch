#!/bin/sh
# Wiring only. Keep creates a new note from the draft on screen.
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
[ "$fail" = "0" ] || { echo "check-keep-shown-draft-ui: FAILED"; exit 1; }

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

def check_store(label, path):
    src = open(path, encoding="utf-8").read()
    action = extract_func(src, "keepShownDraft")
    if not action:
        return
    if "guard confirmed else { return }" not in action:
        bad("%s does not return when confirm is false" % label)
    if "guard knowledgeDraftFile?.isEmpty == false else { return }" not in action:
        bad("%s does not require a draft file" % label)
    if "String(line.prefix(200))" not in action:
        bad("%s does not clip the title to 200 characters" % label)
    call = "createKnowledgeNote(title: titled, body: text)"
    if action.count(call) != 1:
        bad("%s createKnowledgeNote appears %s times" % (label, action.count(call)))
    if action.count("loadKnowledgeNotes(host: host)") != 1:
        bad("%s loadKnowledgeNotes appears %s times" % (label, action.count("loadKnowledgeNotes(host: host)")))
    for forbidden in ("knowledgeAnswer =", "knowledgeDraftFile =", "currentKnowledgeNote =", "knowledgeAskLine =", "replaceKnowledgeNote", "draftAgentNote", "askAgentNote", "speak"):
        if forbidden in action:
            bad("%s keepShownDraft contains %s" % (label, forbidden))

def check_view(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    button = """Button(\"Save reply\") { confirmingSaveReply = true }
                    Button(\"Keep\") { confirmingKeep = true }
                        .disabled(store.knowledgeDraftFile?.isEmpty != false)"""
    if view.count(button) != 1:
        bad("%s Keep button appears %s times" % (label, view.count(button)))
    if view.count("@State private var confirmingKeep = false") != 1:
        bad("%s confirmingKeep appears %s times" % (label, view.count("@State private var confirmingKeep = false")))
    dialog = "confirmationDialog(\"Keep this draft?\""
    if view.count(dialog) != 1:
        bad("%s Keep dialog appears %s times" % (label, view.count(dialog)))
    at = view.find(dialog)
    if at >= 0 and "keepShownDraft(host: host, confirmed: true)" not in view[at:at + 400]:
        bad("%s Keep dialog does not call keepShownDraft" % label)
    if at >= 0 and "store.knowledgeDraftFile ??" not in view[at:at + 500]:
        bad("%s Keep dialog does not name the draft file" % label)
    for title in ("Ask this note?", "Save this note?", "Speak this note?", "Draft this answer?", "Draft this note?", "Save this reply?"):
        if view.count(title) != 1:
            bad("%s %s appears %s times" % (label, title, view.count(title)))

check_store("phone", ios_store_path)
check_store("watch", watch_store_path)
check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-keep-shown-draft-ui: OK")
PY

#!/bin/sh
# Wiring only. Draft on the loaded note posts that note's id after confirm.
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
[ "$fail" = "0" ] || { echo "check-draft-loaded-note-ui: FAILED"; exit 1; }

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
    action = extract_func(src, "draftLoadedNote")
    if not action:
        return
    if action.count("func draftLoadedNote") != 1:
        bad("%s draftLoadedNote appears %s times" % (label, action.count("func draftLoadedNote")))
    held = "guard !drafted.held, let reply = drafted.reply, !reply.isEmpty else { return }"
    assign = "knowledgeAnswer = reply"
    call = "draftAgentNote(id: loaded.id, confirm: true)"
    if action.find(held) < 0:
        bad("%s draftLoadedNote does not return when the reply is held or empty" % label)
    if action.count(assign) != 1:
        bad("%s knowledgeAnswer = reply appears %s times" % (label, action.count(assign)))
    elif action.find(assign) < action.find(held):
        bad("%s assigns knowledgeAnswer before the held return" % label)
    if action.count(call) != 1:
        bad("%s draftAgentNote loaded id appears %s times" % (label, action.count(call)))
    if "loaded.title == named" not in action:
        bad("%s does not require the loaded title" % label)
    if "guard confirmed else { return }" not in action:
        bad("%s does not return when confirm is false" % label)
    for forbidden in ("loadedKnowledgeNote =", "currentKnowledgeNote =", "knowledgeAskLine =", "speak", "listKnowledgeNotes", "replaceKnowledgeNote", "askAgentNote"):
        if forbidden in action:
            bad("%s draftLoadedNote contains %s" % (label, forbidden))

def check_view(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    button = (
        "                Button(\"Speak\") { confirmingSpeak = true }\n"
        "                    .disabled(namedNote.isEmpty || store.loadedKnowledgeNote?.title != namedNote)\n"
        "                Button(\"Draft\") { confirmingDraftNote = true }\n"
        "                    .disabled(namedNote.isEmpty || store.loadedKnowledgeNote?.title != namedNote)"
    )
    answer_button = "Button(\"Draft\") { confirmingDraft = true }"
    if view.count(button) != 1:
        bad("%s loaded-note Draft button appears %s times" % (label, view.count(button)))
    if view.count(answer_button) != 1:
        bad("%s answer Draft button appears %s times" % (label, view.count(answer_button)))
    if view.count("@State private var confirmingDraftNote = false") != 1:
        bad("%s confirmingDraftNote state appears %s times" % (label, view.count("@State private var confirmingDraftNote = false")))
    note_dialog = "confirmationDialog(\"Draft this note?\""
    answer_dialog = "confirmationDialog(\"Draft this answer?\""
    if view.count(note_dialog) != 1:
        bad("%s Draft this note dialog appears %s times" % (label, view.count(note_dialog)))
    if view.count(answer_dialog) != 1:
        bad("%s Draft this answer dialog appears %s times" % (label, view.count(answer_dialog)))
    note_at = view.find(note_dialog)
    answer_at = view.find(answer_dialog)
    if note_at >= 0 and "draftLoadedNote(host: host, title: note, confirmed: true)" not in view[note_at:note_at + 400]:
        bad("%s Draft this note does not call draftLoadedNote" % label)
    if answer_at >= 0 and "draftShownAnswer(host: host, question: ask, confirmed: true)" not in view[answer_at:answer_at + 400]:
        bad("%s Draft this answer does not call draftShownAnswer" % label)
    if answer_at >= 0 and "draftLoadedNote" in view[answer_at:answer_at + 400]:
        bad("%s Draft this answer calls draftLoadedNote" % label)
    for title in ("Ask this note?", "Save this note?", "Speak this note?", "Save this reply?"):
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
print("check-draft-loaded-note-ui: OK")
PY

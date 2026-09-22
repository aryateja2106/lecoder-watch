#!/bin/sh
# Speak wiring only — no daemon. Both clients confirm before POSTing speak.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/Shared/MeshClient.swift"
IOS_STORE="$ROOT/iOS/MeshStore.swift"
WATCH_STORE="$ROOT/Watch/WatchMeshStore.swift"
IOS_VIEWS="$ROOT/iOS/ContentView.swift"
WATCH_VIEWS="$ROOT/Watch/WatchViews.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$CLIENT" "$IOS_STORE" "$WATCH_STORE" "$IOS_VIEWS" "$WATCH_VIEWS"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-speak-saved-note-ui: FAILED"; exit 1; }

python3 - "$CLIENT" "$IOS_STORE" "$WATCH_STORE" "$IOS_VIEWS" "$WATCH_VIEWS" << 'PY'
import re, sys

client_path, ios_store_path, watch_store_path, ios_views_path, watch_views_path = sys.argv[1:6]
client = open(client_path, encoding="utf-8").read()
ios_store = open(ios_store_path, encoding="utf-8").read()
watch_store = open(watch_store_path, encoding="utf-8").read()
ios_views = open(ios_views_path, encoding="utf-8").read()
watch_views = open(watch_views_path, encoding="utf-8").read()
fail = []

def bad(msg):
    fail.append(msg)

def extract(src, name):
    marker = "func " + name
    start = src.find(marker)
    if start < 0:
        bad("missing func %s" % name)
        return ""
    brace = src.find("{", start)
    if brace < 0:
        bad("func %s has no body" % name)
        return ""
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
    bad("func %s is unclosed" % name)
    return ""

def view_struct(src, name):
    start = src.find("struct " + name)
    if start < 0:
        bad("missing struct %s" % name)
        return ""
    brace = src.find("{", start)
    if brace < 0:
        bad("struct %s has no body" % name)
        return ""
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
    bad("struct %s is unclosed" % name)
    return ""

spoken = extract(client, "speakKnowledgeNote")
if spoken:
    if 'method: "POST"' not in spoken or '"/knowledge/' not in spoken:
        bad("speakKnowledgeNote does not POST /knowledge/:id")
    if '"speak"' not in spoken or "true" not in spoken:
        bad("speakKnowledgeNote does not post { speak: true }")
    if "KnowledgeNoteSpeak.self" not in spoken:
        bad("speakKnowledgeNote does not decode KnowledgeNoteSpeak")

for label, store in (("phone", ios_store), ("watch", watch_store)):
    action = extract(store, "speakKnowledgeNote")
    if action:
        guard_at = action.find("guard confirmed else { return }")
        call = action.find("speakKnowledgeNote(id:")
        if guard_at < 0:
            bad("%s store does not return unless confirmed" % label)
        elif call < 0:
            bad("%s store does not call speakKnowledgeNote" % label)
        elif guard_at > call:
            bad("%s store posts before the confirmed return" % label)
        if "loadedKnowledgeNote" not in action or "loaded.title ==" not in action:
            bad("%s store does not require the loaded title to match" % label)

for label, views in (("phone", ios_views), ("watch", watch_views)):
    view_body = view_struct(views, "KnowledgeNoteAskView")
    if not view_body:
        continue
    if 'confirmationDialog("Speak this note?"' not in view_body:
        bad("%s Speak dialog is not Speak this note?" % label)
    if 'confirmationDialog("Ask this note?"' not in view_body:
        bad("%s Ask dialog is no longer Ask this note?" % label)
    if 'confirmationDialog("Save this note?"' not in view_body:
        bad("%s Save dialog is no longer Save this note?" % label)
    opener = view_body.find('Button("Speak") { confirmingSpeak = true }')
    dialog = view_body.find('confirmationDialog("Speak this note?"')
    call = view_body.find("speakKnowledgeNote(")
    if opener < 0:
        bad("%s Speak does not only set a confirm flag" % label)
    if dialog < 0 or call < 0 or call < dialog:
        bad("%s confirm does not call speakKnowledgeNote" % label)
    elif "confirmed: true" not in view_body[dialog:call + 80]:
        bad("%s confirm does not pass confirmed: true" % label)
    if opener >= 0 and dialog >= 0 and "speakKnowledgeNote(" in view_body[opener:dialog]:
        bad("%s Speak posts before the dialog" % label)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-speak-saved-note-ui: OK")
PY

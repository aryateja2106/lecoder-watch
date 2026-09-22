#!/bin/sh
# The phone saves a typed note only after confirm.
# This fails unless the store returns unless confirmed, the dialog is
# "Save this note?", and createKnowledgeNote posts {title, body}.
# No daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/Shared/MeshClient.swift"
STORE="$ROOT/iOS/MeshStore.swift"
VIEWS="$ROOT/iOS/ContentView.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$CLIENT" "$STORE" "$VIEWS"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-ios-knowledge-save: FAILED"; exit 1; }

python3 - "$CLIENT" "$STORE" "$VIEWS" << 'PY'
import re, sys

client_path, store_path, views_path = sys.argv[1:4]
client = open(client_path, encoding="utf-8").read()
store = open(store_path, encoding="utf-8").read()
views = open(views_path, encoding="utf-8").read()
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

created = extract(client, "createKnowledgeNote")
if created:
    if '"/knowledge"' not in created or 'method: "POST"' not in created:
        bad("createKnowledgeNote does not POST /knowledge")
    init = re.search(r"let payload: \[String: Any\] = \[([^\]]*)\]", created)
    if not init:
        bad("createKnowledgeNote has no payload dictionary")
    else:
        literal = init.group(1)
        if '"title"' not in literal or '"body"' not in literal:
            bad("createKnowledgeNote does not post {title, body}")
        keys = re.findall(r'"([^"]+)"', literal)
        if keys != ["title", "body"]:
            bad("createKnowledgeNote payload is not {title, body}")
    if "KnowledgeNoteSummary.self" not in created:
        bad("createKnowledgeNote does not decode KnowledgeNoteSummary")

action = extract(store, "saveKnowledgeNote")
if action:
    guard_at = action.find("guard confirmed else { return }")
    call = action.find("createKnowledgeNote(")
    if guard_at < 0:
        bad("the store does not return unless confirmed")
    elif call < 0:
        bad("the store does not call createKnowledgeNote")
    elif guard_at > call:
        bad("the store posts before the confirmed return")
    if "reachable" not in action or "authError == nil" not in action:
        bad("the store does not require a reachable machine with no auth error")
    if "currentKnowledgeNote" not in action or "loadKnowledgeNotes(" not in action:
        bad("success does not keep the title and reload notes")

view_body = view_struct(views, "KnowledgeNoteAskView")
if view_body:
    if 'confirmationDialog("Save this note?"' not in view_body:
        bad("the dialog is not Save this note?")
    if 'confirmationDialog("Ask this note?"' not in view_body:
        bad("the Ask dialog is no longer Ask this note?")
    opener = view_body.find('Button("Save") { confirmingSave = true }')
    dialog = view_body.find('confirmationDialog("Save this note?"')
    call = view_body.find("saveKnowledgeNote(")
    if opener < 0:
        bad("Save does not only set a confirm flag")
    if dialog < 0 or call < 0 or call < dialog:
        bad("the confirm button does not call saveKnowledgeNote")
    elif "confirmed: true" not in view_body[dialog:call + 80]:
        bad("the confirm button does not pass confirmed: true")
    if opener >= 0 and dialog >= 0 and "saveKnowledgeNote(" in view_body[opener:dialog]:
        bad("Save posts before the dialog")

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-ios-knowledge-save: OK")
PY

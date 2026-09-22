#!/bin/sh
# The watch can save a typed knowledge note after confirm. Wiring only — no daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/Shared/MeshClient.swift"
STORE="$ROOT/Watch/WatchMeshStore.swift"
VIEWS="$ROOT/Watch/WatchViews.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$CLIENT" "$STORE" "$VIEWS"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-watch-knowledge-save: FAILED"; exit 1; }

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

create = extract(client, "createKnowledgeNote")
if create:
    if '"/knowledge"' not in create:
        bad("MeshClient createKnowledgeNote does not post /knowledge")
    if 'method: "POST"' not in create:
        bad("MeshClient createKnowledgeNote is not a POST")
    init = re.search(r"let payload: \[String: Any\] = \[([^\]]*)\]", create)
    if not init:
        bad("MeshClient createKnowledgeNote has no payload dictionary")
    else:
        literal = init.group(1)
        for key in ("title", "body"):
            if '"%s"' % key not in literal:
                bad("MeshClient payload is missing %s" % key)

save = extract(store, "saveKnowledgeNote")
if save:
    call = save.find("createKnowledgeNote(")
    guard_at = save.find("guard confirmed else { return }")
    if call < 0:
        bad("watch store does not call createKnowledgeNote")
    elif guard_at < 0 or guard_at > call:
        bad("watch store calls createKnowledgeNote before the user confirms")

start = views.find("struct KnowledgeNoteAskView")
if start < 0:
    bad("watch has no KnowledgeNoteAskView")
else:
    brace = views.find("{", start)
    depth = 0
    view_body = ""
    for i in range(brace, len(views)):
        if views[i] == "{":
            depth += 1
        elif views[i] == "}":
            depth -= 1
            if depth == 0:
                view_body = views[start:i + 1]
                break
    if "Ask this note?" not in view_body:
        bad("the Ask confirmation dialog title Ask this note? is gone")
    if "Save this note?" not in view_body:
        bad("the Save confirmation dialog title Save this note? is missing")
    if "createKnowledgeNote(" in view_body:
        bad("the watch view calls MeshClient directly")
    if "saveKnowledgeNote(" not in view_body or "confirmed: true" not in view_body:
        bad("the watch control does not save through the store after confirm")
    save_dialog = view_body.find('confirmationDialog("Save this note?"')
    call = view_body.find("saveKnowledgeNote(")
    if save_dialog < 0 or call < save_dialog:
        bad("the watch calls save before the Save confirmation dialog")

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-watch-knowledge-save: OK")
PY

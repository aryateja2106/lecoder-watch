#!/bin/sh
# The watch ask screen lists knowledge note titles, then asks only after confirm.
# This fails unless the store loads titles, a tap copies the title, and the
# confirm path is unchanged. No daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STORE="$ROOT/Watch/WatchMeshStore.swift"
VIEWS="$ROOT/Watch/WatchViews.swift"
MODELS="$ROOT/Shared/Models.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$STORE" "$VIEWS" "$MODELS"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-watch-knowledge-list: FAILED"; exit 1; }

python3 - "$STORE" "$VIEWS" "$MODELS" << 'PY'
import re, sys

store_path, views_path, models_path = sys.argv[1:4]
store = open(store_path, encoding="utf-8").read()
views = open(views_path, encoding="utf-8").read()
models = open(models_path, encoding="utf-8").read()
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

if "knowledgeNotes: [KnowledgeNoteSummary]" not in store:
    bad("watch store does not declare knowledgeNotes")

load = extract(store, "loadKnowledgeNotes")
if load and "listKnowledgeNotes()" not in load:
    bad("loadKnowledgeNotes does not call listKnowledgeNotes()")

view_body = view_struct(views, "KnowledgeNoteAskView")
if view_body:
    if "ForEach(store.knowledgeNotes)" not in view_body:
        bad("KnowledgeNoteAskView does not list titles")
    if "note = summary.title" not in view_body:
        bad("a tap does not set the note from summary.title")
    if 'Ask this note?' not in view_body:
        bad("the confirmation dialog title Ask this note? is gone")

action = extract(store, "askCurrentKnowledgeNote")
if action and "guard confirmed else { return }" not in action:
    bad("askCurrentKnowledgeNote no longer guards on confirmed")

summary = re.search(r"struct KnowledgeNoteSummary\b[^{]*\{([^}]*)\}", models)
if not summary:
    bad("Models.swift has no KnowledgeNoteSummary")
else:
    props = re.findall(r"\b(?:var|let)\s+(\w+)", summary.group(1))
    if props != ["id", "title"]:
        bad("KnowledgeNoteSummary is not only id and title")

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-watch-knowledge-list: OK")
PY

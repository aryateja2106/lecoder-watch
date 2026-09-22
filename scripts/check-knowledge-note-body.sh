#!/bin/sh
# A title tap loads one saved note by id; the list type still has no body.
# Wiring only — no daemon, no model stub, no /proc, no 8899.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/Shared/MeshClient.swift"
IOS_STORE="$ROOT/iOS/MeshStore.swift"
WATCH_STORE="$ROOT/Watch/WatchMeshStore.swift"
IOS_VIEWS="$ROOT/iOS/ContentView.swift"
WATCH_VIEWS="$ROOT/Watch/WatchViews.swift"
MODELS="$ROOT/Shared/Models.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$CLIENT" "$IOS_STORE" "$WATCH_STORE" "$IOS_VIEWS" "$WATCH_VIEWS" "$MODELS"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-knowledge-note-body: FAILED"; exit 1; }

python3 - "$CLIENT" "$IOS_STORE" "$WATCH_STORE" "$IOS_VIEWS" "$WATCH_VIEWS" "$MODELS" << 'PY'
import re, sys

client_path, ios_store_path, watch_store_path, ios_views_path, watch_views_path, models_path = sys.argv[1:7]
client = open(client_path, encoding="utf-8").read()
ios_store = open(ios_store_path, encoding="utf-8").read()
watch_store = open(watch_store_path, encoding="utf-8").read()
ios_views = open(ios_views_path, encoding="utf-8").read()
watch_views = open(watch_views_path, encoding="utf-8").read()
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

summary = re.search(r"struct KnowledgeNoteSummary\b[^{]*\{([^}]*)\}", models)
if not summary:
    bad("Models.swift has no KnowledgeNoteSummary")
else:
    fields = summary.group(1)
    if re.search(r"\bbody\b", fields):
        bad("KnowledgeNoteSummary includes a body")

note = re.search(r"struct KnowledgeNote\b[^{]*\{([^}]*)\}", models)
if not note:
    bad("Models.swift has no KnowledgeNote")
else:
    fields = note.group(1)
    for prop in ("id", "title", "body"):
        if not re.search(r"\b" + prop + r"\b", fields):
            bad("KnowledgeNote is missing %s" % prop)

read_fn = extract(client, "readKnowledgeNote")
if read_fn:
    if 'method: "GET"' not in read_fn:
        bad("readKnowledgeNote is not a GET")
    if '"/knowledge/' not in read_fn:
        bad("readKnowledgeNote does not GET /knowledge/:id")
    if "KnowledgeNote" not in read_fn or "JSONDecoder().decode" not in read_fn:
        bad("readKnowledgeNote does not decode KnowledgeNote")

for label, store in (("phone", ios_store), ("watch", watch_store)):
    load = extract(store, "loadKnowledgeNote(host:")
    if load:
        if "readKnowledgeNote(" not in load:
            bad("%s store does not read one note by id" % label)
        if "reachable" not in load and label == "phone":
            bad("phone loadKnowledgeNote skips unreachable machines")
        if label == "watch" and "directReachable" not in load:
            bad("watch loadKnowledgeNote skips unreachable machines")

for label, views in (("phone", ios_views), ("watch", watch_views)):
    view_body = view_struct(views, "KnowledgeNoteAskView")
    if not view_body:
        continue
    if "note = summary.title" not in view_body:
        bad("%s tap does not copy the title" % label)
    if "loadKnowledgeNote(" not in view_body:
        bad("%s title button does not load one note" % label)
    if "summary.body" in view_body:
        bad("%s reads a body off the summary" % label)
    tap = view_body.find("note = summary.title")
    load = view_body.find("loadKnowledgeNote(")
    if tap < 0 or load < 0 or load < tap:
        bad("%s does not load the note after setting the title" % label)

ios_load = extract(ios_store, "loadKnowledgeNote(host:")
watch_load = extract(watch_store, "loadKnowledgeNote(host:")
regions = [read_fn, ios_load, watch_load, ios_views, watch_views, summary.group(0) if summary else ""]
for region in regions:
    if "/proc" in region or "8899" in region:
        bad("/proc or 8899 appears in the note-body wiring")

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-knowledge-note-body: OK")
PY

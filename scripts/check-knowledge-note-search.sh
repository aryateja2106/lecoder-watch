#!/bin/sh
# Saved notes can be narrowed by title or body text; the list still omits bodies.
# Wiring only — no daemon, no model stub.
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
[ "$fail" = "0" ] || { echo "check-knowledge-note-search: FAILED"; exit 1; }

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

listed = extract(client, "listKnowledgeNotes")
if listed:
    if "/knowledge?q=" not in listed:
        bad("listKnowledgeNotes does not send q on the query string")
    if 'path = "/knowledge"' not in listed and '"/knowledge"' not in listed:
        bad("listKnowledgeNotes does not keep an empty search on GET /knowledge")
    if "addingPercentEncoding" not in listed:
        bad("listKnowledgeNotes does not percent-encode q")

summary = re.search(r"struct KnowledgeNoteSummary\b[^{]*\{([^}]*)\}", models)
if not summary:
    bad("Models.swift has no KnowledgeNoteSummary")
else:
    props = re.findall(r"\b(?:var|let)\s+(\w+)", summary.group(1))
    if props != ["id", "title"]:
        bad("KnowledgeNoteSummary is not only id and title")
    if re.search(r"\bbody\b", summary.group(1)):
        bad("KnowledgeNoteSummary includes a body")

for label, store in (("phone", ios_store), ("watch", watch_store)):
    load = extract(store, "loadKnowledgeNotes")
    if not load:
        continue
    if 'contains("://")' not in load:
        bad("%s loadKnowledgeNotes does not refuse remote-looking search text" % label)
    if "Search needs local text" not in load:
        bad("%s loadKnowledgeNotes does not set Search needs local text" % label)
    scheme_at = load.find('contains("://")')
    list_at = load.find("listKnowledgeNotes(")
    if scheme_at < 0 or list_at < 0 or list_at < scheme_at:
        bad("%s may request a remote-looking search query" % label)
    if "listKnowledgeNotes(" not in load:
        bad("%s loadKnowledgeNotes does not call listKnowledgeNotes" % label)
    catch = load.find("catch")
    if catch >= 0 and "knowledgeNotes = []" in load[catch:]:
        bad("%s clears titles after a failed list request" % label)

for label, views in (("phone", ios_views), ("watch", watch_views)):
    view_body = view_struct(views, "KnowledgeNoteAskView")
    if not view_body:
        continue
    if 'TextField("Search"' not in view_body:
        bad("%s KnowledgeNoteAskView has no Search field" % label)
    if "loadKnowledgeNotes(host: host, query:" not in view_body:
        bad("%s search field does not reload titles" % label)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-knowledge-note-search: OK")
PY

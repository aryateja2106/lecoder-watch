#!/bin/sh
# The phone lists knowledge note titles, then asks only after confirm.
# This fails if the list type or its decode includes a body, if the phone can
# ask before confirm, or if /proc or 8899 appears in that list path.
# No daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/Shared/MeshClient.swift"
STORE="$ROOT/iOS/MeshStore.swift"
VIEWS="$ROOT/iOS/ContentView.swift"
MODELS="$ROOT/Shared/Models.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$CLIENT" "$STORE" "$VIEWS" "$MODELS"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-ios-knowledge-list: FAILED"; exit 1; }

python3 - "$CLIENT" "$STORE" "$VIEWS" "$MODELS" "$ROOT/iOS" << 'PY'
import os, re, sys

client_path, store_path, views_path, models_path, ios_dir = sys.argv[1:6]
client = open(client_path, encoding="utf-8").read()
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

summary = re.search(
    r"struct KnowledgeNoteSummary\b[^{]*\{([^}]*)\}",
    models,
)
if not summary:
    bad("Models.swift has no KnowledgeNoteSummary")
    summary_text = ""
else:
    summary_text = summary.group(0)
    fields = summary.group(1)
    if not re.search(r"\bid\b", fields) or not re.search(r"\btitle\b", fields):
        bad("KnowledgeNoteSummary must carry id and title")
    if re.search(r"\bbody\b", fields):
        bad("KnowledgeNoteSummary includes a body")

listed = extract(client, "listKnowledgeNotes")
if listed:
    if '"/knowledge"' not in listed:
        bad("MeshClient listKnowledgeNotes does not GET /knowledge")
    if 'method: "GET"' not in listed:
        bad("MeshClient listKnowledgeNotes is not a GET")
    if "JSONDecoder().decode" not in listed or "KnowledgeNoteSummary" not in listed:
        bad("MeshClient does not decode the title list")
    if re.search(r"\bbody\b", listed):
        bad("the title-list decode includes a body")
    if '"/knowledge/' in listed or "notes/" in listed:
        bad("the title list requests one note")

load = extract(store, "loadKnowledgeNotes")
if load:
    if "listKnowledgeNotes(" not in load:
        bad("the phone store does not load the title list")
    if "reachable" not in load:
        bad("the phone store loads titles for a machine that is not reachable")
    if "askAgentNote(" in load or '"/agent-note"' in load:
        bad("loading titles asks a note")
    if re.search(r"\bbody\b", load):
        bad("loading titles reads a note body")

action = extract(store, "askCurrentKnowledgeNote")
if action:
    call = action.find("askAgentNote(")
    guard_at = action.find("guard confirmed else { return }")
    if call < 0:
        bad("phone store does not call askAgentNote")
    elif guard_at < 0 or guard_at > call:
        bad("phone store calls askAgentNote before the user confirms")
    if "confirm: true" not in action:
        bad("phone store does not pass confirm after the user confirms")
    if re.search(r"askAgentNote\([^)]*confirm:\s*false", action):
        bad("phone store asks with confirm false")

if store.count("askAgentNote(") != 1:
    bad("phone store must call askAgentNote exactly once, after confirm")

view_body = view_struct(views, "KnowledgeNoteAskView")
if view_body:
    if "ForEach(store.knowledgeNotes)" not in view_body:
        bad("the phone does not list titles")
    if "note = summary.title" not in view_body:
        bad("a tap does not put the title into the note field")
    if "loadKnowledgeNotes(host: host)" not in view_body:
        bad("the phone does not load titles for this machine")
    if "askAgentNote(" in view_body:
        bad("the phone view calls MeshClient directly")
    if '"/agent-note"' in view_body:
        bad("the phone view posts /agent-note")
    if 'confirmationDialog("Ask this note?"' not in view_body:
        bad("the phone asks without a confirmation dialog titled Ask this note?")
    if "askCurrentKnowledgeNote(" not in view_body or "confirmed: true" not in view_body:
        bad("the phone control does not ask the store after confirm")
    if re.search(r"askCurrentKnowledgeNote\([^)]*confirmed:\s*false", view_body):
        bad("the phone asks the store with confirmed false")
    dialog = view_body.find("confirmationDialog")
    call = view_body.find("askCurrentKnowledgeNote(")
    if dialog < 0 or call < dialog:
        bad("the phone calls the store before the confirmation dialog")
    opener = view_body.find('Button("Ask") { confirming = true }')
    if opener < 0:
        bad("the phone has no Ask button that only opens the confirmation")
    elif "askAgentNote(" in view_body[:dialog] or "askCurrentKnowledgeNote(" in view_body[:dialog]:
        bad("the phone asks before the confirmation dialog")
    listed_at = view_body.find("ForEach(store.knowledgeNotes)")
    if listed_at >= 0 and opener >= 0:
        between = view_body[listed_at:opener]
        if "askAgentNote(" in between or "askCurrentKnowledgeNote(" in between or '"/agent-note"' in between:
            bad("a title tap asks before confirm")

regions = [summary_text, listed, load, view_body]
for region in regions:
    if "/proc" in region or "8899" in region:
        bad("/proc or 8899 appears in the title list")

for name in sorted(os.listdir(ios_dir)):
    if not name.endswith(".swift"):
        continue
    path = os.path.join(ios_dir, name)
    text = open(path, encoding="utf-8").read()
    if name == "MeshStore.swift":
        continue
    if "askAgentNote(" in text or '"/agent-note"' in text:
        bad("%s asks before the store's confirm path" % name)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-ios-knowledge-list: OK")
PY

#!/bin/sh
# Wiring only. A draft shows its relative file under the answer.
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
[ "$fail" = "0" ] || { echo "check-show-draft-file-ui: FAILED"; exit 1; }

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
    if src.count("@Published var knowledgeDraftFile: String?") != 1:
        bad("%s knowledgeDraftFile property appears %s times" % (label, src.count("@Published var knowledgeDraftFile: String?")))
    helper = extract_func(src, "heldDraftFile")
    if not helper:
        return
    for piece in ('name.contains("://")', 'name.hasPrefix("/")', 'name.contains("..")'):
        if piece not in helper:
            bad("%s heldDraftFile missing %s" % (label, piece))
    assign = "knowledgeDraftFile = Self.heldDraftFile(drafted.draft)"
    held = "guard !drafted.held, let reply = drafted.reply, !reply.isEmpty else { return }"
    for name in ("draftShownAnswer", "draftLoadedNote"):
        action = extract_func(src, name)
        if not action:
            continue
        if action.count(assign) != 1:
            bad("%s %s draft file assignment appears %s times" % (label, name, action.count(assign)))
        elif action.find(assign) < action.find(held):
            bad("%s %s assigns the draft file before the held return" % (label, name))
    ask = extract_func(src, "askCurrentKnowledgeNote")
    if ask:
        call = "let reply = try await c.askAgentNote(q: q, ask: question, confirm: true)"
        clear = "knowledgeDraftFile = nil"
        call_at = ask.find(call)
        if call_at < 0 or clear not in ask[call_at:call_at + 400]:
            bad("%s ask does not clear the draft file after the ask" % label)
        if ask.count(clear) < 2:
            bad("%s ask clears the draft file %s times" % (label, ask.count(clear)))

def check_view(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    block = """Text(answer).font(.caption)
                    if let file = store.knowledgeDraftFile, !file.isEmpty {
                        Text(\"Draft file \\(file)\").font(.caption2)
                    }
                    Button(\"Draft\") { confirmingDraft = true }"""
    if view.count(block) != 1:
        bad("%s draft file caption appears %s times" % (label, view.count(block)))
    line_at = view.find("else if let line = store.knowledgeAskLine")
    if line_at >= 0 and "knowledgeDraftFile" in view[line_at:line_at + 300]:
        bad("%s ask-line branch shows the draft file" % label)

check_store("phone", ios_store_path)
check_store("watch", watch_store_path)
check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-show-draft-file-ui: OK")
PY

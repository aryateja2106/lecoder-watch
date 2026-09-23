#!/bin/sh
# Wiring only. The screen shows the kept title when speak reports it was spoken.
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
[ "$fail" = "0" ] || { echo "check-show-spoken-kept-ui: FAILED"; exit 1; }

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
        return ""
    end = matching_brace(src, brace)
    if end < 0:
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
        return ""
    end = matching_brace(src, brace)
    if end < 0:
        return ""
    return src[start:end + 1]

ASSIGN = "knowledgeSpokenTitle = spoken.title"

def check_store(label, path):
    src = open(path, encoding="utf-8").read()
    if src.count("@Published var knowledgeSpokenTitle: String?") != 1:
        bad("%s knowledgeSpokenTitle property appears %s times" % (label, src.count("@Published var knowledgeSpokenTitle: String?")))
    action = extract_func(src, "speakKnowledgeNote")
    if not action:
        bad("%s missing speakKnowledgeNote" % label)
        return
    call = "let spoken = try await c.speakKnowledgeNote(id: loaded.id)"
    gate = "if spoken.spoken, spoken.title == named {"
    if action.count(call) != 1:
        bad("%s speak call appears %s times" % (label, action.count(call)))
    if action.count(gate) != 1:
        bad("%s spoken gate appears %s times" % (label, action.count(gate)))
    if action.count(ASSIGN) != 1:
        bad("%s spoken title assignment appears %s times" % (label, action.count(ASSIGN)))
    if action.find(ASSIGN) < action.find(gate):
        bad("%s assignment is not inside the spoken gate" % label)
    if "knowledgeSpokenTitle = nil" not in action:
        bad("%s does not clear the title when speak reports it was not spoken" % label)
    catch_at = action.rfind("catch")
    if catch_at >= 0 and "knowledgeSpokenTitle" in action[catch_at:]:
        bad("%s catch assigns knowledgeSpokenTitle" % label)
    shown = extract_func(src, "speakShownAnswer")
    if "knowledgeSpokenTitle" in shown:
        bad("%s speakShownAnswer assigns knowledgeSpokenTitle" % label)

def check_view(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    caption = """if store.knowledgeSpokenTitle == keptTitle, !keptTitle.isEmpty {
                        Text(\"Spoken \\(keptTitle)\").font(.caption2)
                    }"""
    if view.count(caption) != 1:
        bad("%s spoken caption appears %s times" % (label, view.count(caption)))
    button = "Button(\"Speak kept\") { confirmingSpeakKept = true }"
    cap_at = view.find("Text(\"Spoken \\(keptTitle)\")")
    button_at = view.find(button)
    if button_at < 0 or cap_at < button_at:
        bad("%s spoken caption is not after Speak kept" % label)
    ask_line = view.find("else if let line = store.knowledgeAskLine")
    if ask_line >= 0 and "Spoken" in view[ask_line:ask_line + 400]:
        bad("%s ask-line branch shows Spoken" % label)
    if view.count("speakShownAnswer(") != 1:
        bad("%s speakShownAnswer appears %s times" % (label, view.count("speakShownAnswer(")))

check_store("phone", ios_store_path)
check_store("watch", watch_store_path)
check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-show-spoken-kept-ui: OK")
PY

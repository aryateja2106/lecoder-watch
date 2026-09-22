#!/bin/sh
# Wiring only. Speak the saved answer on screen, and keep speaking the named note otherwise.
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
[ "$fail" = "0" ] || { echo "check-speak-shown-answer: FAILED"; exit 1; }

python3 - "$IOS_STORE" "$WATCH_STORE" "$IOS_VIEWS" "$WATCH_VIEWS" << 'PY'
import re, sys

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

def block_from(src, header_at):
    brace = src.find("{", header_at)
    if brace < 0:
        return -1, -1, ""
    end = matching_brace(src, brace)
    if end < 0:
        return brace, -1, ""
    return brace, end, src[brace + 1:end]

def check_store(label, path):
    src = open(path, encoding="utf-8").read()
    action = extract_func(src, "speakShownAnswer")
    if not action:
        return
    if "func speakShownAnswer(host: String, question: String, confirmed: Bool)" not in action:
        bad("%s speakShownAnswer does not take host, question, and confirmed" % label)
    guard_at = action.find("guard confirmed else { return }")
    speak_at = action.find("speakKnowledgeNote(id:")
    answer_at = action.find("knowledgeAnswer")
    if guard_at < 0:
        bad("%s speakShownAnswer does not return unless confirmed" % label)
    elif speak_at < 0:
        bad("%s speakShownAnswer does not call speakKnowledgeNote" % label)
    elif guard_at > speak_at:
        bad("%s speakShownAnswer speaks before the confirmed return" % label)
    if answer_at < 0 or "isEmpty" not in action:
        bad("%s speakShownAnswer does not return unless knowledgeAnswer is non-empty" % label)
    elif speak_at >= 0 and answer_at > speak_at:
        bad("%s speakShownAnswer speaks before checking knowledgeAnswer" % label)
    trim_at = action.find("trimmingCharacters")
    prefix_at = action.find("prefix(200)")
    if prefix_at < 0 or "String(" not in action:
        bad("%s speakShownAnswer does not take the question prefix" % label)
    elif trim_at < 0 or trim_at > prefix_at:
        bad("%s speakShownAnswer does not trim the question before the prefix" % label)
    single_at = action.find("matches.count == 1")
    read_at = action.find("readKnowledgeNote")
    title_at = action.find("title == titled", read_at if read_at >= 0 else 0)
    if single_at < 0:
        bad("%s speakShownAnswer does not require a single title match" % label)
    elif speak_at >= 0 and single_at > speak_at:
        bad("%s speakShownAnswer speaks without a single title match" % label)
    if read_at < 0 or title_at < 0 or title_at < read_at:
        bad("%s speakShownAnswer does not require the read title to match the question prefix" % label)
    elif speak_at >= 0 and title_at > speak_at:
        bad("%s speakShownAnswer speaks before the read title matches" % label)
    if "listKnowledgeNotes" not in action or "readKnowledgeNote" not in action:
        bad("%s speakShownAnswer does not list and read the note" % label)
    if re.search(r"loadedKnowledgeNote\s*=", action):
        bad("%s speakShownAnswer assigns loadedKnowledgeNote" % label)
    if re.search(r"currentKnowledgeNote\s*=", action):
        bad("%s speakShownAnswer assigns currentKnowledgeNote" % label)
    caught = action.rfind("catch")
    if caught < 0:
        bad("%s speakShownAnswer has no catch for a failed list or read" % label)
    else:
        brace = action.find("{", caught)
        end = matching_brace(action, brace) if brace >= 0 else -1
        body = action[brace + 1:end] if end > brace else ""
        if "speakKnowledgeNote" in body or "lastError" in body:
            bad("%s speakShownAnswer speaks or sets lastError when the list or read fails" % label)

def check_view(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    for title in ("Ask this note?", "Save this note?", "Speak this note?"):
        if view.count('confirmationDialog("%s"' % title) != 1:
            bad("%s dialog title %s is not unchanged" % (label, title))
    if 'Button("Speak") { confirmingSpeak = true }' not in view:
        bad("%s Speak button does not only set the confirm flag" % label)
    dialog_at = view.find('confirmationDialog("Speak this note?"')
    if dialog_at < 0:
        return
    calls = [m.start() for m in re.finditer(r"speakShownAnswer\(", view)]
    if len(calls) != 1:
        bad("%s expected one speakShownAnswer call inside the Speak dialog" % label)
        return
    if calls[0] < dialog_at:
        bad("%s speakShownAnswer is outside the Speak dialog" % label)
    actions_brace, actions_end, actions = block_from(view, dialog_at)
    if actions_end < 0:
        bad("%s Speak dialog has no action block" % label)
        return
    if calls[0] < actions_brace or calls[0] > actions_end:
        bad("%s speakShownAnswer is outside the Speak dialog" % label)
    shown = "if let answer = store.knowledgeAnswer, !answer.isEmpty"
    branch_at = actions.find(shown)
    if branch_at < 0:
        bad("%s Speak dialog does not call speakShownAnswer when an answer is showing" % label)
        return
    _, branch_end, branch = block_from(actions, branch_at)
    if "speakShownAnswer(" not in branch or "confirmed: true" not in branch or "question:" not in branch:
        bad("%s Speak dialog does not confirm speakShownAnswer with the question" % label)
    else_at = actions.find("else", branch_end)
    if else_at < 0:
        bad("%s Speak dialog has no other path" % label)
        return
    _, _, other = block_from(actions, else_at)
    if "speakKnowledgeNote(" not in other or "confirmed: true" not in other or "title: note" not in other:
        bad("%s other Speak path does not call speakKnowledgeNote with the note" % label)
    if "speakShownAnswer(" in other:
        bad("%s other Speak path calls speakShownAnswer" % label)
    message_at = view.find("message:", actions_end)
    if message_at < 0:
        bad("%s Speak dialog has no message" % label)
        return
    _, _, message = block_from(view, message_at)
    msg_branch = message.find(shown)
    if msg_branch < 0:
        bad("%s Speak message is not the question when an answer is showing" % label)
        return
    _, msg_end, msg_body = block_from(message, msg_branch)
    if "Text(question)" not in msg_body:
        bad("%s Speak message is not the question when an answer is showing" % label)
    msg_else = message.find("else", msg_end)
    if msg_else < 0:
        bad("%s Speak message drops the note name" % label)
        return
    _, _, msg_other = block_from(message, msg_else)
    if "Text(namedNote)" not in msg_other:
        bad("%s Speak message is not the note name when no answer is showing" % label)

check_store("phone", ios_store_path)
check_store("watch", watch_store_path)
check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-speak-shown-answer: OK")
PY

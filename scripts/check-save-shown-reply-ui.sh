#!/bin/sh
# Wiring only. Save the reply on screen into the one note whose title is the
# question. This script does not start a daemon.
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
[ "$fail" = "0" ] || { echo "check-save-shown-reply-ui: FAILED"; exit 1; }

python3 - "$CLIENT" "$IOS_STORE" "$WATCH_STORE" "$IOS_VIEWS" "$WATCH_VIEWS" << 'PY'
import re, sys

client_path, ios_store_path, watch_store_path, ios_views_path, watch_views_path = sys.argv[1:6]
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

client = open(client_path, encoding="utf-8").read()
replace = extract_func(client, "replaceKnowledgeNote")
if replace:
    if "func replaceKnowledgeNote(id: String, body: String)" not in replace:
        bad("replaceKnowledgeNote does not take id and body")
    if '["body": body]' not in replace:
        bad("replaceKnowledgeNote does not post only body")
    if '"/knowledge/\\(id)"' not in replace or 'method: "POST"' not in replace:
        bad("replaceKnowledgeNote does not POST /knowledge/:id")
    if "KnowledgeNote.self" not in replace:
        bad("replaceKnowledgeNote does not decode KnowledgeNote")
    for key in ("speak", "audio", "path", "url", "q", "ask", "model", "command"):
        if '"%s"' % key in replace:
            bad("replaceKnowledgeNote posts %s" % key)

def check_store(label, path, guard_line):
    src = open(path, encoding="utf-8").read()
    action = extract_func(src, "saveShownReply")
    drafted = extract_func(src, "draftShownAnswer")
    if not action:
        return
    if "func saveShownReply(host: String, question: String, confirmed: Bool)" not in action:
        bad("%s saveShownReply does not take host, question, and confirmed" % label)
    guard_at = action.find("guard confirmed else { return }")
    call = "replaceKnowledgeNote(id:"
    call_at = action.find(call)
    answer_at = action.find("knowledgeAnswer")
    if guard_at < 0:
        bad("%s saveShownReply does not return unless confirmed" % label)
    elif call_at < 0:
        bad("%s saveShownReply does not call replaceKnowledgeNote" % label)
    elif guard_at > call_at:
        bad("%s saveShownReply replaces before the confirmed return" % label)
    if answer_at < 0 or "isEmpty" not in action:
        bad("%s saveShownReply does not return unless knowledgeAnswer is non-empty" % label)
    elif call_at >= 0 and answer_at > call_at:
        bad("%s saveShownReply replaces before checking knowledgeAnswer" % label)
    trim_at = action.find("trimmingCharacters")
    prefix_at = action.find("prefix(200)")
    if prefix_at < 0 or "String(" not in action:
        bad("%s saveShownReply does not take the question prefix" % label)
    elif trim_at < 0 or trim_at > prefix_at:
        bad("%s saveShownReply does not trim the question before the prefix" % label)
    single = "guard matches.count == 1 else { return }"
    title = "guard read.title == titled else { return }"
    single_at = action.find(single)
    read_at = action.find("readKnowledgeNote")
    title_at = action.find(title)
    if single_at < 0:
        bad("%s saveShownReply does not return unless one title matches" % label)
    elif call_at >= 0 and single_at > call_at:
        bad("%s saveShownReply replaces without one title match" % label)
    if read_at < 0 or title_at < 0 or title_at < read_at:
        bad("%s saveShownReply does not require the read title to match" % label)
    elif call_at >= 0 and title_at > call_at:
        bad("%s saveShownReply replaces before the read title matches" % label)
    if "listKnowledgeNotes" not in action:
        bad("%s saveShownReply does not list notes" % label)
    if call_at < 0 or "body: shown" not in action[call_at:call_at + 80]:
        bad("%s saveShownReply does not pass the on-screen answer" % label)
    if guard_line not in action or guard_line not in drafted:
        bad("%s saveShownReply does not use the draftShownAnswer host guard" % label)
    for name in ("knowledgeAnswer", "currentKnowledgeNote", "knowledgeAskLine"):
        if re.search(r"%s\s*=" % name, action):
            bad("%s saveShownReply assigns %s" % (label, name))
    saved_title = "saved.title == titled"
    title_at = action.find(saved_title)
    loaded_assigns = [m.start() for m in re.finditer(r"loadedKnowledgeNote\s*=", action)]
    if title_at < 0 or not loaded_assigns or any(at < title_at for at in loaded_assigns):
        bad("%s saveShownReply assigns loadedKnowledgeNote before the saved title matches" % label)
    elif "loadedKnowledgeNote = saved" not in action[title_at:]:
        bad("%s saveShownReply does not assign the saved note after the title matches" % label)
    caught = action.rfind("} catch {")
    if caught < 0:
        bad("%s saveShownReply has no catch" % label)
    else:
        brace = action.find("{", caught)
        end = matching_brace(action, brace) if brace >= 0 else -1
        body = action[brace + 1:end] if end > brace else ""
        if body.strip() != "return":
            bad("%s error return changes state: %r" % (label, body.strip()))
        if "lastError" in body or "replaceKnowledgeNote" in body:
            bad("%s error return changes lastError or replaces" % label)

def check_view(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    for title in ("Ask this note?", "Save this note?", "Speak this note?", "Save this reply?"):
        if view.count('confirmationDialog("%s"' % title) != 1:
            bad("%s dialog title %s is not present once" % (label, title))
    shown = "if let answer = store.knowledgeAnswer, !answer.isEmpty"
    branch_at = view.find(shown)
    if branch_at < 0:
        bad("%s Answer section does not show a non-empty knowledgeAnswer" % label)
        return
    _, branch_end, branch = block_from(view, branch_at)
    if 'Section("Answer")' not in branch:
        bad("%s answer is not in the Answer section" % label)
    draft_btn = 'Button("Draft") { confirmingDraft = true }'
    save_btn = 'Button("Save reply") { confirmingSaveReply = true }'
    draft_at = branch.find(draft_btn)
    save_at = branch.find(save_btn)
    if draft_at < 0 or save_at < 0 or save_at < draft_at:
        bad("%s Save reply does not follow Draft in the Answer section" % label)
    if branch.count(save_btn) != 1:
        bad("%s Save reply button is not only in the answer section" % label)
    if "saveShownReply(" in branch:
        bad("%s Save reply button writes before the dialog" % label)
    else_at = view.find("else if let line = store.knowledgeAskLine", branch_end)
    if else_at < 0:
        bad("%s drops knowledgeAskLine when knowledgeAnswer is empty" % label)
    else:
        _, _, empty = block_from(view, else_at)
        if "Save reply" in empty or "Save this reply?" in empty or "saveShownReply(" in empty:
            bad("%s Save reply appears when no answer is showing" % label)
    dialog_at = view.find('confirmationDialog("Save this reply?"')
    calls = [m.start() for m in re.finditer(r"saveShownReply\(", view)]
    if len(calls) != 1:
        bad("%s expected one saveShownReply call" % label)
        return
    if dialog_at < 0 or calls[0] < dialog_at:
        bad("%s saveShownReply is outside the Save reply dialog" % label)
    actions_brace, actions_end, actions = block_from(view, dialog_at)
    if actions_end < 0 or calls[0] < actions_brace or calls[0] > actions_end:
        bad("%s saveShownReply is outside the Save reply dialog" % label)
        return
    if "question: ask" not in actions or "confirmed: true" not in actions:
        bad("%s confirm does not call saveShownReply with the question field" % label)
    note_save = view.find('confirmationDialog("Save this note?"')
    if note_save >= 0 and "saveShownReply(" in view[note_save:dialog_at]:
        bad("%s note Save calls saveShownReply" % label)
    ask_at = view.find('confirmationDialog("Ask this note?"')
    speak_at = view.find('confirmationDialog("Speak this note?"')
    if ask_at >= 0 and "askCurrentKnowledgeNote(" not in view[ask_at:note_save]:
        bad("%s Ask dialog no longer asks the note" % label)
    if speak_at >= 0 and "speakShownAnswer(" not in view[speak_at:dialog_at]:
        bad("%s Speak dialog no longer speaks the shown answer" % label)

check_store("phone", ios_store_path, "snap.reachable, snap.authError == nil")
check_store("watch", watch_store_path, "directReachable(host), let c = client(for: host)")
check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-save-shown-reply-ui: OK")
PY

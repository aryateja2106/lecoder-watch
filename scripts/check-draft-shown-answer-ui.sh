#!/bin/sh
# Wiring only. Draft the saved answer on screen, and keep the other dialogs.
# This script does not start a daemon.
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
[ "$fail" = "0" ] || { echo "check-draft-shown-answer-ui: FAILED"; exit 1; }

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
draft = extract_func(client, "draftAgentNote")
if draft:
    if "func draftAgentNote(id: String, confirm: Bool)" not in draft:
        bad("draftAgentNote does not take id and confirm")
    if '["id": id, "confirm": true]' not in draft:
        bad("draftAgentNote does not post only id and confirm true")
    for key in ("q", "ask", "cwd", "model", "command"):
        if '"%s"' % key in draft:
            bad("draftAgentNote posts %s" % key)
    if '"/agent-note"' not in draft or 'method: "POST"' not in draft:
        bad("draftAgentNote does not POST /agent-note")
    if "AgentNoteAsk.self" not in draft:
        bad("draftAgentNote does not decode AgentNoteAsk")

def check_store(label, path):
    src = open(path, encoding="utf-8").read()
    action = extract_func(src, "draftShownAnswer")
    if not action:
        return
    if "func draftShownAnswer(host: String, question: String, confirmed: Bool)" not in action:
        bad("%s draftShownAnswer does not take host, question, and confirmed" % label)
    guard_at = action.find("guard confirmed else { return }")
    call_at = action.find("draftAgentNote(id:")
    answer_at = action.find("knowledgeAnswer")
    if guard_at < 0:
        bad("%s draftShownAnswer does not return unless confirmed" % label)
    elif call_at < 0:
        bad("%s draftShownAnswer does not call draftAgentNote" % label)
    elif guard_at > call_at:
        bad("%s draftShownAnswer drafts before the confirmed return" % label)
    if answer_at < 0 or "isEmpty" not in action:
        bad("%s draftShownAnswer does not return unless knowledgeAnswer is non-empty" % label)
    elif call_at >= 0 and answer_at > call_at:
        bad("%s draftShownAnswer drafts before checking knowledgeAnswer" % label)
    trim_at = action.find("trimmingCharacters")
    prefix_at = action.find("prefix(200)")
    if prefix_at < 0 or "String(" not in action:
        bad("%s draftShownAnswer does not take the question prefix" % label)
    elif trim_at < 0 or trim_at > prefix_at:
        bad("%s draftShownAnswer does not trim the question before the prefix" % label)
    single_at = action.find("matches.count == 1")
    read_at = action.find("readKnowledgeNote")
    title_at = action.find("title == titled", read_at if read_at >= 0 else 0)
    if single_at < 0:
        bad("%s draftShownAnswer does not require a single title match" % label)
    elif call_at >= 0 and single_at > call_at:
        bad("%s draftShownAnswer drafts without a single title match" % label)
    if read_at < 0 or title_at < 0 or title_at < read_at:
        bad("%s draftShownAnswer does not require the read title to match" % label)
    elif call_at >= 0 and title_at > call_at:
        bad("%s draftShownAnswer drafts before the read title matches" % label)
    if "listKnowledgeNotes" not in action:
        bad("%s draftShownAnswer does not list notes" % label)
    if call_at < 0 or "confirm: true" not in action[call_at:call_at + 80]:
        bad("%s draftShownAnswer does not pass confirm true" % label)
    spoken = extract_func(src, "speakKnowledgeNote")
    if label == "phone":
        guard_line = "snap.reachable, snap.authError == nil"
    else:
        guard_line = "directReachable(host), let c = client(for: host)"
    if guard_line not in spoken or guard_line not in action:
        bad("%s draftShownAnswer does not use the speakKnowledgeNote host guard" % label)
    if re.search(r"loadedKnowledgeNote\s*=", action):
        bad("%s draftShownAnswer assigns loadedKnowledgeNote" % label)
    if re.search(r"currentKnowledgeNote\s*=", action):
        bad("%s draftShownAnswer assigns currentKnowledgeNote" % label)
    held = "guard !drafted.held, let reply = drafted.reply, !reply.isEmpty else { return }"
    assign = "knowledgeAnswer = reply"
    held_at = action.find(held)
    assign_at = action.find(assign)
    if held_at < 0:
        bad("%s draftShownAnswer does not return when the reply is held or empty" % label)
    if action.count(assign) != 1:
        bad("%s knowledgeAnswer = reply appears %s times" % (label, action.count(assign)))
    elif held_at >= 0 and assign_at < held_at:
        bad("%s assigns knowledgeAnswer before the held return" % label)
    if re.search(r"knowledgeAskLine\s*=", action):
        bad("%s draftShownAnswer assigns knowledgeAskLine" % label)
    caught = action.rfind("catch")
    if caught < 0:
        bad("%s draftShownAnswer has no catch for a failed list or read" % label)
    else:
        brace = action.find("{", caught)
        end = matching_brace(action, brace) if brace >= 0 else -1
        body = action[brace + 1:end] if end > brace else ""
        if "draftAgentNote" in body or "lastError" in body:
            bad("%s draftShownAnswer drafts or sets lastError when the list or read fails" % label)
    zero = action.find("matches.count == 1")
    if zero >= 0:
        line_end = action.find("\n", zero)
        line = action[zero:line_end if line_end >= 0 else zero + 80]
        if "draftAgentNote" in line or "lastError" in line:
            bad("%s zero or several matches still draft or set lastError" % label)

def check_view(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    for title in ("Ask this note?", "Save this note?", "Speak this note?", "Draft this answer?"):
        if view.count('confirmationDialog("%s"' % title) != 1:
            bad("%s dialog title %s is not present once" % (label, title))
    shown = "if let answer = store.knowledgeAnswer, !answer.isEmpty"
    branch_at = view.find(shown)
    if branch_at < 0:
        bad("%s Answer section does not show a non-empty knowledgeAnswer" % label)
        return
    _, branch_end, branch = block_from(view, branch_at)
    if "Text(answer)" not in branch:
        bad("%s Answer section no longer shows Text(answer)" % label)
    if 'Section("Answer")' not in branch:
        bad("%s answer is not in the Answer section" % label)
    flag = 'Button("Draft") { confirmingDraft = true }'
    flag_at = branch.find(flag)
    text_at = branch.find("Text(answer)")
    if flag_at < 0 or text_at < 0 or flag_at < text_at:
        bad("%s Draft button does not follow Text(answer) and only set the confirm flag" % label)
    if "draftShownAnswer(" in branch:
        bad("%s Draft button drafts before the dialog" % label)
    else_at = view.find("else if let line = store.knowledgeAskLine", branch_end)
    if else_at < 0:
        bad("%s drops knowledgeAskLine when knowledgeAnswer is empty" % label)
    else:
        _, _, empty = block_from(view, else_at)
        if "Text(line)" not in empty:
            bad("%s empty path no longer shows knowledgeAskLine" % label)
    dialog_at = view.find('confirmationDialog("Draft this answer?"')
    calls = [m.start() for m in re.finditer(r"draftShownAnswer\(", view)]
    if len(calls) != 1:
        bad("%s expected one draftShownAnswer call" % label)
        return
    if dialog_at < 0 or calls[0] < dialog_at:
        bad("%s draftShownAnswer is outside the Draft dialog" % label)
    actions_brace, actions_end, actions = block_from(view, dialog_at)
    if actions_end < 0 or calls[0] < actions_brace or calls[0] > actions_end:
        bad("%s draftShownAnswer is outside the Draft dialog" % label)
        return
    if "question: ask" not in actions or "confirmed: true" not in actions:
        bad("%s confirm does not call draftShownAnswer with the question field" % label)
    speak_at = view.find('confirmationDialog("Speak this note?"')
    if speak_at >= 0 and "speakShownAnswer(" not in view[speak_at:dialog_at]:
        bad("%s Speak dialog no longer speaks the shown answer" % label)

check_store("phone", ios_store_path)
check_store("watch", watch_store_path)
check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-draft-shown-answer-ui: OK")
PY

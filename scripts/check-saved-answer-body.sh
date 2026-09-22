#!/bin/sh
# Wiring only. Both clients show the saved answer body after an ask that was not held.
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
[ "$fail" = "0" ] || { echo "check-saved-answer-body: FAILED"; exit 1; }

python3 - "$IOS_STORE" "$WATCH_STORE" "$IOS_VIEWS" "$WATCH_VIEWS" << 'PY'
import re, sys

ios_store_path, watch_store_path, ios_views_path, watch_views_path = sys.argv[1:5]
fail = []

def bad(msg):
    fail.append(msg)

def blank_comments(src):
    out = []
    i = 0
    n = len(src)
    while i < n:
        if src.startswith("//", i):
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
        elif src.startswith("/*", i):
            out.append(" ")
            out.append(" ")
            i += 2
            while i < n and not src.startswith("*/", i):
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            if src.startswith("*/", i):
                out.append(" ")
                out.append(" ")
                i += 2
        else:
            out.append(src[i])
            i += 1
    return "".join(out)

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

def outer_catch(fn):
    match = re.search(r"\bdo\s*\{", fn)
    if not match:
        bad("askCurrentKnowledgeNote has no do block")
        return ""
    open_idx = fn.find("{", match.start())
    close_idx = matching_brace(fn, open_idx)
    if close_idx < 0:
        bad("ask do block is unclosed")
        return ""
    rest = fn[close_idx + 1:]
    catch = re.search(r"\bcatch\b[^{]*\{", rest)
    if not catch:
        bad("askCurrentKnowledgeNote has no catch")
        return ""
    catch_open = close_idx + 1 + catch.end() - 1
    catch_close = matching_brace(fn, catch_open)
    if catch_close < 0:
        bad("ask catch is unclosed")
        return ""
    return fn[catch_open + 1:catch_close]

BODY_SET = "knowledgeAnswer = loaded.title == titled ? loaded.body : nil"

def check_store(label, path):
    src = blank_comments(open(path, encoding="utf-8").read())
    if "@Published var knowledgeAnswer: String?" not in src:
        bad("%s store is missing knowledgeAnswer" % label)
    fn = extract_func(src, "askCurrentKnowledgeNote")
    if not fn:
        return
    ask_at = fn.find("askAgentNote(")
    if ask_at < 0:
        bad("%s ask does not call askAgentNote" % label)
        return
    if "confirm: true" not in fn[ask_at:ask_at + 120]:
        bad("%s ask no longer posts confirm: true" % label)
    if "knowledgeAnswer" in fn[:ask_at]:
        bad("%s sets knowledgeAnswer before the ask" % label)
    held = None
    start = 0
    while True:
        i = fn.find("if !reply.held", start)
        if i < 0:
            break
        brace, end, body = block_from(fn, i)
        if brace < 0 or end < 0:
            break
        if re.fullmatch(r"if\s+!reply\.held\s*", fn[i:brace].strip()):
            held = (i, brace, end, body)
            break
        start = i + 1
    if held is None:
        bad("%s does not keep a not-held path" % label)
        return
    _, brace, end, body = held
    if "String(question.prefix(200))" not in body:
        bad("%s does not clip the question to 200 characters" % label)
    if "let titled = String(question.prefix(200))" not in body:
        bad("%s does not name the 200-character question titled" % label)
    if "listKnowledgeNotes()" not in body:
        bad("%s does not list notes on the not-held path" % label)
    if "$0.title == titled" not in body:
        bad("%s does not match the listed title to the question" % label)
    if "matches.count == 1" not in body:
        bad("%s does not require a single title match" % label)
    if "readKnowledgeNote(id:" not in body:
        bad("%s does not read the matched note" % label)
    if BODY_SET not in body:
        bad("%s does not set knowledgeAnswer from the body of that one title" % label)
    if "knowledgeAnswer = nil" not in body:
        bad("%s does not clear knowledgeAnswer when the title is not unique" % label)
    if body.find("readKnowledgeNote(id:") > body.find(BODY_SET):
        bad("%s sets the answer before reading the note" % label)
    if body.find("matches.count == 1") > body.find(BODY_SET):
        bad("%s sets the answer before the single-title check" % label)
    outside = fn[:brace] + fn[end:]
    if "loaded.body" in outside or BODY_SET in outside:
        bad("%s sets the saved answer outside the not-held path" % label)
    else_at = fn.find("else", end + 1)
    if else_at < 0 or fn[end + 1:else_at].strip() != "":
        bad("%s held path is missing" % label)
    else:
        else_brace, else_end, else_body = block_from(fn, else_at)
        if else_brace < 0 or "knowledgeAnswer = nil" not in else_body:
            bad("%s does not clear knowledgeAnswer when the reply was held" % label)
        if "loaded.body" in else_body or "listKnowledgeNotes" in else_body:
            bad("%s reads a saved answer when the reply was held" % label)
    caught = outer_catch(fn)
    if "knowledgeAnswer = nil" not in caught:
        bad("%s does not clear knowledgeAnswer when the ask throws" % label)
    if "loaded.body" in caught or "listKnowledgeNotes" in caught:
        bad("%s reads a saved answer when the ask throws" % label)

def check_view(label, path):
    src = blank_comments(open(path, encoding="utf-8").read())
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    shown = "if let answer = store.knowledgeAnswer, !answer.isEmpty"
    at = view.find(shown)
    if at < 0:
        bad("%s Answer section does not show a non-empty knowledgeAnswer" % label)
        return
    brace, end, body = block_from(view, at)
    if 'Section("Answer")' not in body or "Text(answer)" not in body:
        bad("%s does not show knowledgeAnswer in the Answer section" % label)
    else_at = view.find("else if let line = store.knowledgeAskLine", end)
    if else_at < 0:
        bad("%s drops the answer line when knowledgeAnswer is nil" % label)
        return
    _, _, else_body = block_from(view, else_at)
    if 'Section("Answer")' not in else_body or "Text(line)" not in else_body:
        bad("%s does not keep the answer line when knowledgeAnswer is nil" % label)
    for title in ("Ask this note?", "Save this note?", "Speak this note?"):
        if 'confirmationDialog("%s"' % title not in view:
            bad("%s dialog is no longer %s" % (label, title))

check_store("phone", ios_store_path)
check_store("watch", watch_store_path)
check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-saved-answer-body: OK")
PY

#!/bin/sh
# Wiring only. Both stores reload the note list after an ask that was not held.
# This script does not start a daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_STORE="$ROOT/iOS/MeshStore.swift"
WATCH_STORE="$ROOT/Watch/WatchMeshStore.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$IOS_STORE" "$WATCH_STORE"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-knowledge-ask-refresh: FAILED"; exit 1; }

python3 - "$IOS_STORE" "$WATCH_STORE" << 'PY'
import re, sys

ios_path, watch_path = sys.argv[1:3]
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
    end = matching_brace(src, brace)
    if end < 0:
        bad("func %s is unclosed" % name)
        return ""
    return src[start:end + 1]

def do_and_catch(fn):
    match = re.search(r"\bdo\s*\{", fn)
    if not match:
        bad("askCurrentKnowledgeNote has no do block")
        return "", ""
    open_idx = fn.find("{", match.start())
    close_idx = matching_brace(fn, open_idx)
    if close_idx < 0:
        bad("ask do block is unclosed")
        return "", ""
    body = fn[open_idx + 1:close_idx]
    rest = fn[close_idx + 1:]
    catch = re.search(r"\bcatch\b[^{]*\{", rest)
    if not catch:
        bad("askCurrentKnowledgeNote has no catch")
        return body, ""
    catch_open = close_idx + 1 + catch.end() - 1
    catch_close = matching_brace(fn, catch_open)
    if catch_close < 0:
        bad("ask catch is unclosed")
        return body, ""
    return body, fn[catch_open + 1:catch_close]

CALL = "loadKnowledgeNotes(host: host)"

def check_store(label, path):
    src = blank_comments(open(path, encoding="utf-8").read())
    fn = extract(src, "askCurrentKnowledgeNote")
    if not fn:
        return
    ask_at = fn.find("askAgentNote(")
    if ask_at < 0:
        bad("%s ask does not call askAgentNote" % label)
        return
    if "confirm: true" not in fn[ask_at:ask_at + 120]:
        bad("%s ask no longer posts confirm: true" % label)
    if CALL in fn[:ask_at]:
        bad("%s reloads the list before the ask" % label)
    success, caught = do_and_catch(fn)
    if not success:
        return
    if CALL in caught:
        bad("%s reloads the list when the ask throws" % label)
    line_at = success.find("knowledgeAskLine = Self.knowledgeAskLine(reply)")
    if line_at < 0:
        bad("%s does not set knowledgeAskLine from the reply" % label)
        return
    calls = [m.start() for m in re.finditer(re.escape(CALL), success)]
    if len(calls) != 1:
        bad("%s success path calls %s %d times" % (label, CALL, len(calls)))
        return
    call_at = calls[0]
    if call_at < line_at:
        bad("%s reloads the list before the answer line" % label)
    gate = None
    start = 0
    while True:
        i = success.find("if !reply.held", start)
        if i < 0 or i > call_at:
            break
        brace = success.find("{", i)
        if brace < 0:
            break
        end = matching_brace(success, brace)
        if brace < call_at < end and re.fullmatch(r"if\s+!reply\.held\s*", success[i:brace].strip()):
            gate = (brace, end)
            break
        start = i + 1
    if gate is None:
        bad("%s does not reload only when the reply was not held" % label)
        return
    if line_at > gate[0]:
        bad("%s checks held before showing the answer line" % label)
    outside = success[:gate[0]] + success[gate[1]:]
    if CALL in outside:
        bad("%s reloads the list outside the not-held branch" % label)

check_store("phone", ios_path)
check_store("watch", watch_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-knowledge-ask-refresh: OK")
PY

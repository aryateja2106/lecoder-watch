#!/bin/sh
# Wiring only. After a saved reply replaces one note, the loaded note becomes
# that saved note so the Body field shows it. This script does not start a daemon.
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
[ "$fail" = "0" ] || { echo "check-show-saved-reply-ui: FAILED"; exit 1; }

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
    action = extract_func(src, "saveShownReply")
    if not action:
        return
    replace = "let saved = try await c.replaceKnowledgeNote(id: read.id, body: shown)"
    title = "guard saved.title == titled else { return }"
    loaded = "loadedKnowledgeNote = saved"
    replace_at = action.find(replace)
    title_at = action.find(title)
    loaded_at = action.find(loaded)
    if replace_at < 0:
        bad("%s saveShownReply does not keep the replace result" % label)
    if title_at < 0:
        bad("%s saveShownReply does not require saved.title == titled" % label)
    if loaded_at < 0:
        bad("%s saveShownReply does not assign loadedKnowledgeNote from the replace result" % label)
    if replace_at >= 0 and title_at >= 0 and loaded_at >= 0:
        if not (replace_at < title_at < loaded_at):
            bad("%s saveShownReply assigns loadedKnowledgeNote before the saved title matches" % label)
    assigns = [m.start() for m in re.finditer(r"loadedKnowledgeNote\s*=", action)]
    if title_at < 0 or not assigns or any(at < title_at for at in assigns):
        bad("%s loadedKnowledgeNote is assigned before saved.title == titled" % label)
    elif assigns != [loaded_at]:
        bad("%s loadedKnowledgeNote is not only the saved note" % label)
    caught = action.rfind("} catch {")
    if caught < 0:
        bad("%s saveShownReply has no catch" % label)
    else:
        brace = action.find("{", caught)
        end = matching_brace(action, brace) if brace >= 0 else -1
        body = action[brace + 1:end] if end > brace else ""
        if body.strip() != "return":
            bad("%s error return changes state: %r" % (label, body.strip()))
        if "loadedKnowledgeNote" in body:
            bad("%s error return assigns loadedKnowledgeNote" % label)
    for early in ("guard matches.count == 1 else { return }", "guard read.title == titled else { return }"):
        early_at = action.find(early)
        if early_at < 0 or (loaded_at >= 0 and early_at > loaded_at):
            bad("%s %s does not return before assigning loadedKnowledgeNote" % (label, early))

def check_view(label, path):
    src = open(path, encoding="utf-8").read()
    view = extract_struct(src, "KnowledgeNoteAskView")
    if not view:
        return
    marker = ".onChange(of: store.loadedKnowledgeNote)"
    at = view.find(marker)
    if at < 0:
        bad("%s ask screen does not set the Body field from loadedKnowledgeNote" % label)
        return
    _, end, body = block_from(view, at)
    if end < 0:
        bad("%s loadedKnowledgeNote onChange is unclosed" % label)
        return
    if "noteBody = loaded.body" not in body:
        bad("%s Body field is not set from loaded.body in onChange" % label)
    if "loaded.title == namedNote" not in body:
        bad("%s Body field is set without a loaded title match" % label)

check_store("phone", ios_store_path)
check_store("watch", watch_store_path)
check_view("phone", ios_views_path)
check_view("watch", watch_views_path)

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-show-saved-reply-ui: OK")
PY

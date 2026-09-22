#!/bin/sh
# The daemon already answers one local knowledge note. This fails unless the
# watch client posts that route with q and ask, leaves confirm off the body
# unless the caller passes true, and the watch store is the caller.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/Shared/MeshClient.swift"
STORE="$ROOT/Watch/WatchMeshStore.swift"
VIEWS="$ROOT/Watch/WatchViews.swift"
MODELS="$ROOT/Shared/Models.swift"
fail=0

bad() { echo "FAIL: $1"; fail=1; }

for f in "$CLIENT" "$STORE" "$VIEWS" "$MODELS"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-watch-knowledge-ask: FAILED"; exit 1; }

python3 - "$CLIENT" "$STORE" "$VIEWS" "$MODELS" << 'PY'
import re, sys

client_path, store_path, views_path, models_path = sys.argv[1:5]
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

ask = extract(client, "askAgentNote")
if ask:
    if '"/agent-note"' not in ask:
        bad("MeshClient askAgentNote does not post /agent-note")
    if 'method: "POST"' not in ask:
        bad("MeshClient askAgentNote is not a POST")
    init = re.search(r"var payload: \[String: Any\] = \[([^\]]*)\]", ask)
    if not init:
        bad("MeshClient askAgentNote has no payload dictionary")
    else:
        literal = init.group(1)
        for key in ("q", "ask"):
            if '"%s"' % key not in literal:
                bad("MeshClient payload is missing %s" % key)
        if "confirm" in literal:
            bad("MeshClient puts confirm in the payload before the caller confirms")
    assigns = re.findall(r'payload\["([^"]+)"\]', ask)
    allowed = {"q", "ask", "confirm"}
    extra = [key for key in assigns if key not in allowed]
    if extra:
        bad("MeshClient posts extra keys: %s" % ", ".join(extra))
    confirm_lines = [ln.strip() for ln in ask.splitlines() if 'payload["confirm"]' in ln]
    if confirm_lines != ['if confirm { payload["confirm"] = true }']:
        bad("confirm must be added only when the caller passes true, got %s" % confirm_lines)
    if "JSONDecoder().decode(AgentNoteAsk.self" not in ask:
        bad("MeshClient does not decode AgentNoteAsk")

struct = re.search(r"struct AgentNoteAsk: Codable, Hashable \{([^}]*)\}", models, re.S)
if not struct:
    bad("Models.swift has no AgentNoteAsk response")
else:
    body = struct.group(1)
    for field in ("modelClass", "draft", "commandRan", "held"):
        if not re.search(r"\b%s\b" % field, body):
            bad("AgentNoteAsk does not decode %s" % field)

action = extract(store, "askCurrentKnowledgeNote")
if action:
    call = action.find("askAgentNote(")
    guard_at = action.find("guard confirmed else { return }")
    if call < 0:
        bad("watch store does not call askAgentNote")
    elif guard_at < 0 or guard_at > call:
        bad("watch store calls askAgentNote before the user confirms")
    if "currentKnowledgeNote" not in action:
        bad("watch store does not ask the current knowledge note")
    if "confirm: true" not in action:
        bad("watch store does not pass confirm after the user confirms")
    if re.search(r"askAgentNote\([^)]*confirm:\s*false", action):
        bad("watch store asks with confirm false")

start = views.find("struct KnowledgeNoteAskView")
if start < 0:
    bad("watch has no control that asks a knowledge note")
else:
    brace = views.find("{", start)
    depth = 0
    view_body = ""
    for i in range(brace, len(views)):
        if views[i] == "{":
            depth += 1
        elif views[i] == "}":
            depth -= 1
            if depth == 0:
                view_body = views[start:i + 1]
                break
    if "askAgentNote(" in view_body:
        bad("the watch view calls MeshClient directly")
    if "confirmationDialog" not in view_body:
        bad("the watch asks without a confirmation dialog")
    if "askCurrentKnowledgeNote(" not in view_body or "confirmed: true" not in view_body:
        bad("the watch control does not ask the store after confirm")
    # The store call belongs on the confirm button, after the dialog opens.
    dialog = view_body.find("confirmationDialog")
    call = view_body.find("askCurrentKnowledgeNote(")
    if dialog < 0 or call < dialog:
        bad("the watch calls the store before the confirmation dialog")

if fail:
    for msg in fail:
        print("FAIL:", msg)
    sys.exit(1)
print("check-watch-knowledge-ask: OK")
PY

#!/bin/sh
# The phone asks the current knowledge note the same way the watch does.
# This fails unless nothing posts /agent-note or calls askAgentNote until the
# user confirms, and the confirm path then calls the store with confirm true.
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
[ "$fail" = "0" ] || { echo "check-ios-knowledge-ask: FAILED"; exit 1; }

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
        bad("phone store does not call askAgentNote")
    elif guard_at < 0 or guard_at > call:
        bad("phone store calls askAgentNote before the user confirms")
    if "currentKnowledgeNote" not in action:
        bad("phone store does not ask the current knowledge note")
    if "confirm: true" not in action:
        bad("phone store does not pass confirm after the user confirms")
    if re.search(r"askAgentNote\([^)]*confirm:\s*false", action):
        bad("phone store asks with confirm false")
    if '"/agent-note"' in action:
        bad("phone store posts /agent-note itself")

if store.count("askAgentNote(") != 1:
    bad("phone store must call askAgentNote exactly once, after confirm")

start = views.find("struct KnowledgeNoteAskView")
if start < 0:
    bad("phone has no control that asks a knowledge note")
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
        bad("the phone view calls MeshClient directly")
    if '"/agent-note"' in view_body:
        bad("the phone view posts /agent-note")
    if 'confirmationDialog("Ask this note?"' not in view_body:
        bad("the phone asks without a confirmation dialog titled Ask this note?")
    if "askCurrentKnowledgeNote(" not in view_body or "confirmed: true" not in view_body:
        bad("the phone control does not ask the store after confirm")
    if re.search(r"askCurrentKnowledgeNote\([^)]*confirmed:\s*false", view_body):
        bad("the phone asks the store with confirmed false")
    # The store call belongs on the confirm button, after the dialog opens.
    dialog = view_body.find("confirmationDialog")
    call = view_body.find("askCurrentKnowledgeNote(")
    if dialog < 0 or call < dialog:
        bad("the phone calls the store before the confirmation dialog")
    opener = view_body.find('Button("Ask") { confirming = true }')
    if opener < 0:
        bad("the phone has no Ask button that only opens the confirmation")
    elif "askAgentNote(" in view_body[:dialog] or "askCurrentKnowledgeNote(" in view_body[:dialog]:
        bad("the phone asks before the confirmation dialog")

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
print("check-ios-knowledge-ask: OK")
PY

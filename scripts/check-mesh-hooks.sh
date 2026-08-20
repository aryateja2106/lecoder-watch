#!/bin/sh
# `mesh hooks` edits ~/.claude/settings.json — someone's entire Claude Code
# configuration, with other tools' hooks in it. The failure that matters is not "the
# hook did not install", it is "the install ate a setting". Runs against a throwaway
# HOME so it never touches the real one.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-hooks: SKIP (no bun)"; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/settings.json" <<'JSON'
{
  "model": "opus",
  "permissions": { "allow": ["Bash"] },
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "/somebody/elses/guard.sh" }] }],
    "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "/another/tool.sh" }] }]
  }
}
JSON

run() { HOME="$TMP" MESH_HOME="$TMP/.mesh" bun "$ROOT/install/payload/bin/mesh" hooks "$@" >/dev/null; }
run install
run install          # idempotent: a second install must not duplicate
run install

HOME="$TMP" /usr/bin/python3 - "$TMP" <<'PY'
import json, sys, os
tmp = sys.argv[1]
d = json.load(open(os.path.join(tmp, ".claude", "settings.json")))
fail = []

def ours(event):
    return [h for e in d["hooks"].get(event, []) for h in e.get("hooks", []) if "mesh-hook" in h.get("command", "")]

if len(ours("Notification")) != 1: fail.append(f"Notification: {len(ours('Notification'))} entries after three installs, want 1")
if len(ours("Stop")) != 1: fail.append(f"Stop: {len(ours('Stop'))} entries after three installs, want 1")

# Nothing of anyone else's may move.
stop_others = [h["command"] for e in d["hooks"]["Stop"] for h in e["hooks"] if "mesh-hook" not in h["command"]]
if stop_others != ["/somebody/elses/guard.sh"]: fail.append(f"another tool's Stop hook was lost: {stop_others}")
if "PreToolUse" not in d["hooks"]: fail.append("an untouched event was dropped entirely")
if d.get("model") != "opus" or d.get("permissions", {}).get("allow") != ["Bash"]:
    fail.append("settings outside hooks were modified")
if not os.path.exists(os.path.join(tmp, ".claude", "settings.json.mesh-backup")):
    fail.append("no backup was written before editing")

if fail:
    for f in fail: print("FAIL:", f)
    raise SystemExit(1)
PY

run remove
HOME="$TMP" /usr/bin/python3 - "$TMP" <<'PY'
import json, sys, os
d = json.load(open(os.path.join(sys.argv[1], ".claude", "settings.json")))
mine = [h for ev in d["hooks"].values() for e in ev for h in e.get("hooks", []) if "mesh-hook" in h.get("command", "")]
fail = []
if mine: fail.append(f"remove left {len(mine)} entries behind")
# Remove must restore the file to what it was, not merely delete our lines.
if "Notification" in d["hooks"]: fail.append("an event we created was left behind empty")
if len(d["hooks"]["Stop"]) != 1: fail.append("remove disturbed another tool's Stop hook")
if "PreToolUse" not in d["hooks"]: fail.append("remove dropped an event it never touched")
if fail:
    for f in fail: print("FAIL:", f)
    raise SystemExit(1)
PY

echo "check-mesh-hooks: OK"

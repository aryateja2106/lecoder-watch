#!/bin/sh
# check-brain.sh — every machine has a local model that answers with a tool call, and meshd knows it.
#
# The daemon's GET /brain (brain.ts, ported from PR #119 on 2026-09-22) reports which OpenAI-
# compatible server answers on the machine — edge0 :8001 (Apple Silicon), ollama :11434 (the
# Linux boxes), mference, LM Studio, or MESHD_BRAIN_URL. This check asks two things:
#   fleet half  (MESH_FLEET_LIVE=1)  every host in ~/.mesh/hosts.json reports a reachable brain
#   local half  (MESH_BRAIN_LIVE=1)  the brain on THIS machine returns a `tool_calls` entry for a
#                                     one-tool prompt (the function-calling contract the agent loop
#                                     and Needle's fallback depend on). MESH_BRAIN_URL overrides the
#                                     endpoint; MESH_BRAIN_MODEL the model (default: first listed).
# Structural half (always): brain.ts exists, is wired in server.ts, and "brain" is advertised.
# Measured 2026-09-22: Pi 5 qwen3:1.7b → tool call in 40 s (~3.5 tok/s CPU); Jetson Orin Nano
# qwen3:4b → tool call in 12 s (~11 tok/s CUDA, needs OLLAMA_CONTEXT_LENGTH=2048 on 8 GB and
# `/no_think` in the prompt so the answer is not spent on reasoning tokens).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/install/payload/meshd/server.ts"
[ -f "$ROOT/install/payload/meshd/brain.ts" ] || { echo "check-brain: FAIL — brain.ts missing"; exit 1; }
grep -q 'handleBrain' "$SERVER" || { echo "check-brain: FAIL — server.ts does not route to handleBrain"; exit 1; }
grep -q '"brain"' "$SERVER" || { echo "check-brain: FAIL — capability brain not advertised"; exit 1; }
fail=0

if [ "${MESH_FLEET_LIVE:-}" = "1" ] && [ -r "$HOME/.mesh/hosts.json" ]; then
  python3 - "$HOME/.mesh/hosts.json" "${MESH_FLEET_HOSTS:-}" <<'PY' || fail=1
import json, sys, urllib.request
hosts = json.load(open(sys.argv[1]))["hosts"]; only = sys.argv[2].split()
names = only or [n for n in hosts if n != "dataflow"]
bad = 0
for n in names:
    h = hosts[n]
    try:
        req = urllib.request.Request(f"http://{h['ip']}:{h['port']}/brain", headers={"Authorization": f"Bearer {h['token']}"})
        d = json.load(urllib.request.urlopen(req, timeout=15))
    except Exception as e:
        print(f"check-brain: FAIL {n}: /brain {e}"); bad += 1; continue
    up = [e for e in d.get("endpoints", []) if e.get("reachable")]
    if up: print(f"check-brain: ok   {n}: {up[0]['source']} at {up[0]['endpoint']} model={up[0].get('model')}")
    else: print(f"check-brain: FAIL {n}: no reachable local model server"); bad += 1
sys.exit(1 if bad else 0)
PY
fi

if [ "${MESH_BRAIN_LIVE:-}" = "1" ]; then
  URL="${MESH_BRAIN_URL:-}"
  if [ -z "$URL" ]; then
    for cand in http://127.0.0.1:8001/v1 http://127.0.0.1:11434/v1 http://127.0.0.1:8080/v1 http://127.0.0.1:1234/v1; do
      curl -s -m 3 -o /dev/null "$cand/models" && { URL="$cand"; break; }
    done
  fi
  [ -n "$URL" ] || { echo "check-brain: FAIL — no local model server answers (set MESH_BRAIN_URL)"; exit 1; }
  python3 - "$URL" "${MESH_BRAIN_MODEL:-}" <<'PY' || fail=1
import json, sys, time, urllib.request
url, model = sys.argv[1].rstrip("/"), sys.argv[2]
if not model:
    ms = json.load(urllib.request.urlopen(f"{url}/models", timeout=10)).get("data", [])
    model = ms[0]["id"] if ms else ""
body = {"model": model, "temperature": 0, "max_tokens": 400,
        "messages": [{"role": "user", "content": "What time is it on the jetson? Use the tool. /no_think"}],
        "tools": [{"type": "function", "function": {"name": "get_time", "description": "Get the current time on a named machine",
                   "parameters": {"type": "object", "properties": {"machine": {"type": "string", "enum": ["mac", "pi", "jetson"]}}, "required": ["machine"]}}}]}
t0 = time.time()
req = urllib.request.Request(f"{url}/chat/completions", data=json.dumps(body).encode(), headers={"content-type": "application/json"})
d = json.load(urllib.request.urlopen(req, timeout=300))
dt = time.time() - t0
calls = (d.get("choices") or [{}])[0].get("message", {}).get("tool_calls") or []
name = calls[0]["function"]["name"] if calls else None
args = calls[0]["function"].get("arguments") if calls else None
toks = (d.get("usage") or {}).get("completion_tokens")
ok = name == "get_time" and "jetson" in str(args)
print(f"check-brain: {'ok  ' if ok else 'FAIL'} {url} model={model} tool_call={name}({args}) in {dt:.1f}s, {toks} completion tokens" + ("" if ok else f" — raw: {json.dumps(d)[:300]}"))
sys.exit(0 if ok else 1)
PY
fi

[ "$fail" -eq 0 ] && echo "check-brain: OK" || { echo "check-brain: FAIL"; exit 1; }

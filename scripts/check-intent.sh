#!/bin/sh
# check-intent.sh — Needle 2 turns wrist phrases into the right daemon call (PRODUCT.md §9, slice 1).
#
# intent/mesh-tools.json is the tool catalogue (every tool is an existing daemon route);
# intent/cases.jsonl is the frozen acceptance suite: phrase → expected call name and the
# argument values a person would consider non-negotiable. Runs the macos-arm64 (or
# linux-arm64) `needle` CLI over every case, scores name + expected-argument matches,
# prints accuracy, mean confidence, mean latency and peak RAM, and goes red below the floor
# recorded here after the first measurement.
#
# Floor: measured 2026-09-21 on this Mac, zero fine-tuning, 16 tools (retrieval engaged):
# 20/28 right tool with the first descriptions, 26/28 after one pass of description tuning
# (22/28 with every expected argument; mean confidence 0.28; ~700 ms/phrase; 34 MB peak).
# The remaining misses are argument extraction (session names, copy direction) — fine-tune
# material. Floor = 24 so a regression of the catalogue shows; MESH_INTENT_FLOOR overrides.
# Skips (exit 0) when no needle binary is present — this is a measurement, not yet a gate —
# unless MESH_INTENT_REQUIRED=1.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FLOOR="${MESH_INTENT_FLOOR:-24}"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) DEFAULT_BIN="$ROOT/references/external/models/needle2/macos-arm64/needle" ;;
  Linux-aarch64) DEFAULT_BIN="$ROOT/references/external/models/needle2/linux-arm64/needle" ;;
  *) DEFAULT_BIN="" ;;
esac
BIN="${NEEDLE_BIN:-$DEFAULT_BIN}"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
  echo "check-intent: SKIP — no needle CLI at ${BIN:-<unsupported platform>} (hf download Cactus-Compute/needle2 macos-arm64/needle --local-dir references/external/models/needle2)"
  [ "${MESH_INTENT_REQUIRED:-0}" = "1" ] && exit 1
  exit 0
fi
[ -s intent/mesh-tools.json ] && [ -s intent/cases.jsonl ] || { echo "check-intent: FAIL — intent/mesh-tools.json or intent/cases.jsonl missing"; exit 1; }

python3 - "$BIN" "$FLOOR" <<'PY'
import json, subprocess, sys, time
bin_, floor = sys.argv[1], int(sys.argv[2])
cases = [json.loads(l) for l in open("intent/cases.jsonl") if l.strip()]
ok_name = ok_full = 0; confs = []; lat = []; ram = []; rows = []
for c in cases:
    t0 = time.time()
    p = subprocess.run([bin_, "--tools", "intent/mesh-tools.json", "--prompt", c["phrase"]], capture_output=True, text=True, timeout=60)
    lat.append(time.time() - t0)
    line = next((l for l in p.stdout.splitlines() if l.startswith("{")), "{}")
    try: r = json.loads(line)
    except Exception: r = {}
    calls = r.get("function_calls") or []
    got = calls[0] if calls else {"name": None, "arguments": {}}
    exp = c["expect"]; want_args = {k: v for k, v in exp.items() if k != "name"}
    name_ok = got.get("name") == exp["name"]
    args = got.get("arguments") or {}
    args_ok = all(str(args.get(k, "")).lower() == str(v).lower() for k, v in want_args.items())
    ok_name += name_ok; ok_full += name_ok and args_ok
    if r.get("confidence") is not None: confs.append(r["confidence"])
    if r.get("peak_ram_mb"): ram.append(r["peak_ram_mb"])
    mark = "ok  " if name_ok and args_ok else ("name" if name_ok else "MISS")
    rows.append(f"  {mark} {c['phrase']!r:58} -> {got.get('name')} {json.dumps(args, separators=(',',':'))}" + ("" if name_ok and args_ok else f"   expected {json.dumps(exp, separators=(',',':'))}"))
print("\n".join(rows))
n = len(cases)
print(f"check-intent: {ok_name}/{n} right tool, {ok_full}/{n} right tool+args; mean confidence {sum(confs)/max(1,len(confs)):.2f}; "
      f"mean latency {1000*sum(lat)/n:.0f} ms; peak RAM {max(ram) if ram else 0:.0f} MB; floor {floor}")
sys.exit(0 if ok_name >= floor else 1)
PY
status=$?
[ "$status" -eq 0 ] && echo "check-intent: OK" || echo "check-intent: FAIL — below the floor"
exit "$status"

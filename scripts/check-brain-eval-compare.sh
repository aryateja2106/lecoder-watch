#!/bin/sh
# Self-check for brain-eval's use-case probes and its two-endpoint compare mode.
#
# The harness is verified by RUNNING it, never by building (AGENTS.md rule 1), and a
# comparison that only ever runs twice proves nothing. So this boots three stub personas
# and asserts, from the JSON the harness writes:
#   1. textonly alone still scores 19 pass · 0 fail · 1 unsupported;
#   2. dumb alone fails exactly the ten use-case probes, each with its DESIGNED failure
#      mode — a probe that fails for the wrong reason is a harness bug;
#   3. textonly vs vision detects the capability boundary ("unsupported on A, passing on
#      B: vision"), ties every use-case probe, and exports one dataset row per turn with
#      the full request and the assistant message;
#   4. textonly vs dumb hands every use-case capability to A by more-passes and lists B's
#      failure modes.
# Ports are high and checked first; something already listening is not ours to kill
# (AGENTS.md rule 8).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
PT=8161; PV=8162; PD=8163
for port in $PT $PV $PD; do
  if lsof -ti "tcp:$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "check-brain-eval-compare: SKIP (something already listens on :$port — not killing it)"
    exit 0
  fi
done
bun run "$ROOT/scripts/brain-eval/stub-server.ts" --port $PT --persona textonly >"$TMP/t.log" 2>&1 & P1=$!
bun run "$ROOT/scripts/brain-eval/stub-server.ts" --port $PV --persona vision   >"$TMP/v.log" 2>&1 & P2=$!
bun run "$ROOT/scripts/brain-eval/stub-server.ts" --port $PD --persona dumb     >"$TMP/d.log" 2>&1 & P3=$!
trap 'kill $P1 $P2 $P3 2>/dev/null; rm -rf "$TMP"' EXIT
i=0; while [ $i -lt 50 ]; do
  ok=1
  for port in $PT $PV $PD; do curl -sf "http://127.0.0.1:$port/v1/models" >/dev/null 2>&1 || ok=0; done
  [ $ok = 1 ] && break
  i=$((i+1)); sleep 0.1
done

E="$ROOT/scripts/brain-eval/eval.ts"
bun run "$E" --endpoint "http://127.0.0.1:$PT/v1" --timeout 8000 --json "$TMP/single-t.json" >"$TMP/single-t.out" 2>&1
bun run "$E" --endpoint "http://127.0.0.1:$PD/v1" --timeout 8000 --json "$TMP/single-d.json" >"$TMP/single-d.out" 2>&1
bun run "$E" --a "http://127.0.0.1:$PT/v1" --b "http://127.0.0.1:$PV/v1" --timeout 8000 --json "$TMP/tv.json" --jsonl "$TMP/tv.jsonl" >"$TMP/tv.out" 2>&1
bun run "$E" --a "http://127.0.0.1:$PT/v1" --b "http://127.0.0.1:$PD/v1" --timeout 8000 --no-warmup --json "$TMP/td.json" >"$TMP/td.out" 2>&1

cat > "$TMP/assert.ts" <<'TS'
import { readFileSync } from "node:fs"
const dir = process.argv[2]
let failed = 0
const check = (name: string, cond: boolean, detail = "") => {
  if (!cond) { console.log(`  FAIL ${name} ${detail}`); failed++ } else console.log(`  ok   ${name} ${detail}`)
}
const load = (f: string) => JSON.parse(readFileSync(`${dir}/${f}`, "utf8"))
const count = (rs: any[], s: string) => rs.filter((r) => r.status === s).length

// The designed failure for each use-case probe. If the dumb persona fails a probe for a
// different reason, the probe's pass criteria or the stub's canned answer drifted.
const EXPECTED: Record<string, string> = {
  "cli-single-line": "heredoc",
  "cli-observe-before-edit": "hallucinated-path",
  "cli-unique-anchor": "non-unique-find",
  "cli-error-recovery": "repeated-failing-command",
  "cli-finish-when-done": "no-finish",
  "browser-selectors-from-snapshot": "guessed-selector",
  "terminal-observe-before-send": "blind-send",
  "ios-sim-boot-udid": "wrong-target",
  "ios-test-digest-read": "hallucinated-path",
  "macos-activate-before-type": "typed-into-wrong-app",
}
const NEW = Object.keys(EXPECTED)

// 1. textonly alone
const st = load("single-t.json")
check("single textonly: 19 pass", count(st.results, "pass") === 19, `${count(st.results, "pass")}`)
check("single textonly: 0 fail", count(st.results, "fail") === 0)
check("single textonly: 1 unsupported (images)", count(st.results, "unsupported") === 1 && st.results.find((r: any) => r.id === "vision").status === "unsupported")
check("single textonly: 20 probes ran", st.results.length === 20, String(st.results.length))
check("single textonly: every probe carries a useCase", st.results.every((r: any) => typeof r.useCase === "string" && r.useCase.length))

// 2. dumb alone — exactly the ten, each for its designed reason
const sd = load("single-d.json")
const dumbFails = sd.results.filter((r: any) => r.status === "fail")
check("single dumb: exactly the 10 use-case probes fail", dumbFails.length === 10 && dumbFails.every((r: any) => NEW.includes(r.id)), dumbFails.map((r: any) => r.id).join(","))
for (const id of NEW) {
  const r = sd.results.find((x: any) => x.id === id)
  check(`single dumb: ${id} → ${EXPECTED[id]}`, r?.status === "fail" && r?.failureMode === EXPECTED[id], `${r?.status} ${r?.failureMode}`)
}
check("single dumb: the original probes still pass", sd.results.filter((r: any) => !NEW.includes(r.id) && r.id !== "vision").every((r: any) => r.status === "pass"))

// 3. textonly vs vision — the capability boundary, ties elsewhere, and the dataset export
const tv = load("tv.json")
check("compare tv: schemaVersion 1", tv.schemaVersion === 1)
check("compare tv: boundary is exactly vision", JSON.stringify(tv.unsupportedOnAPassingOnB) === JSON.stringify(["vision"]), JSON.stringify(tv.unsupportedOnAPassingOnB))
check("compare tv: models resolved", tv.a.model === "stub-qwen36" && tv.b.model === "stub-ornith", `${tv.a.model} ${tv.b.model}`)
for (const id of NEW) {
  const ra = tv.a.probes.find((p: any) => p.id === id), rb = tv.b.probes.find((p: any) => p.id === id)
  check(`compare tv: ${id} passes on both`, ra?.status === "pass" && rb?.status === "pass", `${ra?.status} ${rb?.status}`)
}
const v = (cap: string) => tv.verdicts.find((x: any) => x.capability === cap)
check("compare tv: reads images → B by more-passes", v("reads images")?.betterFor === "b" && v("reads images")?.rule === "more-passes", JSON.stringify(v("reads images")))
check("compare tv: economics → A (B cannot report prefix reuse)", v("long-running economics")?.betterFor === "a" && tv.b.summary["long-running economics"] === "PARTIAL", JSON.stringify(v("long-running economics")))
check("compare tv: use-case capabilities OK on both", ["cli agent", "ios simulator", "macos control"].every((c) => tv.a.summary[c] === "OK" && tv.b.summary[c] === "OK"))
check("compare tv: no failure modes on either side", Object.keys(tv.a.failureModes).length === 0 && Object.keys(tv.b.failureModes).length === 0)
// Speed: the vision persona paces frames 20x slower; the harness must see it on a paired pass.
const tools = tv.table.find((r: any) => r.id === "tools-single")
check("compare tv: paced persona measurably slower", tools.b.ms > tools.a.ms * 3 && tools.b.tokPerSec < tools.a.tokPerSec / 3, `A ${tools.a.ms}ms/${tools.a.tokPerSec?.toFixed(0)}t/s  B ${tools.b.ms}ms/${tools.b.tokPerSec?.toFixed(0)}t/s`)
check("compare tv: cached_tokens visible on A, null on B", tools.a.cachedTokens !== null && tools.b.cachedTokens === null, `${tools.a.cachedTokens} ${tools.b.cachedTokens}`)
check("compare tv: reasoning split recorded for B", tv.b.probes.find((p: any) => p.id === "tools-single").turns[0].response.perf.reasoningSource === "reasoning_content")
// Dataset export: one row per (endpoint, probe, turn), each carrying the full request and reply.
const rows = readFileSync(`${dir}/tv.jsonl`, "utf8").trim().split("\n").map((l) => JSON.parse(l))
check("compare tv: jsonl has 40 rows (20 probes × 2 endpoints; the stream probe and models fetch by hand)", rows.length === 40, String(rows.length))
check("compare tv: every row carries the request messages", rows.every((r) => Array.isArray(r.messages) && r.messages.length))
check("compare tv: every 200 row carries the assistant message + perf", rows.filter((r) => r.httpStatus === 200).every((r) => r.assistant && r.perf))
// The capability boundary shows up in the dataset as the one non-200 row: A refusing the
// image. That row must exist, with no fabricated assistant message.
const refused = rows.filter((r) => r.httpStatus !== 200)
check("compare tv: the only non-200 row is A refusing the image", refused.length === 1 && refused[0].endpoint === "a" && refused[0].probe === "vision" && refused[0].httpStatus === 400 && refused[0].assistant === null && refused[0].status === "unsupported", JSON.stringify(refused.map((r) => [r.endpoint, r.probe, r.httpStatus])))
check("compare tv: rows with tools carry the schemas", rows.filter((r) => r.probe === "cli-single-line").every((r) => Array.isArray(r.tools) && r.tools.length === 7))
check("compare tv: settings recorded", tv.settings.temperature === 0 && tv.settings.maxTokens === 512 && tv.settings.repeat === 1)

// 4. textonly vs dumb — every use-case capability to A, and B's modes listed
const td = load("td.json")
const w = (cap: string) => td.verdicts.find((x: any) => x.capability === cap)
for (const cap of ["cli agent", "ios simulator", "macos control", "terminal actions", "browser actions"]) {
  check(`compare td: ${cap} → A by more-passes`, w(cap)?.betterFor === "a" && w(cap)?.rule === "more-passes", JSON.stringify(w(cap)))
}
check("compare td: function calling ties (dumb answers the old probes well)", w("function calling")?.betterFor === "tie", JSON.stringify(w("function calling")))
const modes = td.b.failureModes
check("compare td: B failure modes match the design", modes["hallucinated-path"] === 2 && modes["heredoc"] === 1 && modes["non-unique-find"] === 1 && modes["blind-send"] === 1 && modes["typed-into-wrong-app"] === 1, JSON.stringify(modes))
check("compare td: A has none", Object.keys(td.a.failureModes).length === 0)
check("compare td: warm-up skipped when asked", td.a.warmupMs === null && td.b.warmupMs === null)
check("compare tv: warm-up recorded by default", typeof tv.a.warmupMs === "number" && typeof tv.b.warmupMs === "number")

if (failed) { console.log(`\n${failed} assertion(s) failed`); process.exit(1) }
console.log("check-brain-eval-compare: all assertions passed")
TS
bun run "$TMP/assert.ts" "$TMP"

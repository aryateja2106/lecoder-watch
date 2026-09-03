#!/bin/sh
# Self-check for scripts/brain-eval/sse.ts — the stream accumulator behind every
# tokens/sec and time-to-first-token number brain-eval reports.
#
# Two local servers put reasoning, usage and tool calls in different places. If this
# module misreads one of them, the comparison between them is wrong in a way that looks
# exactly like a real difference between the models. So the fixtures below are the
# actual wire shapes: MferenceServer's (usage on every frame, no reasoning), LM Studio's
# structured reasoning_content, LM Studio's inline <think> for Qwen-thinking models
# (lmstudio-bug-tracker #1569), fragmented tool calls, and a server that never sends
# usage at all. The same bytes are also re-fed split at odd offsets, because SSE
# frames do not respect chunk boundaries.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/driver.ts" <<'TS'
import { accumulateSSE } from "./sse.ts"

let failed = 0
const check = (name: string, cond: boolean, detail = "") => {
  if (!cond) { console.log(`  FAIL ${name} ${detail}`); failed++ }
  else console.log(`  ok   ${name} ${detail}`)
}

// A deterministic clock: each frame handed to the accumulator advances it by `step` ms.
function ticking(step: number) {
  let t = 0
  return { clock: () => t, tick: () => { t += step } }
}
const frame = (o: unknown) => `data: ${JSON.stringify(o)}\n\n`
const delta = (d: Record<string, unknown>, extra: Record<string, unknown> = {}) =>
  frame({ choices: [{ index: 0, delta: d, finish_reason: null }], ...extra })

// Feed frames one at a time, ticking between them, so timestamps are attributable.
async function* timed(frames: string[], tk: { tick: () => void }) {
  for (const f of frames) { tk.tick(); yield f }
}
// Feed the same bytes split at an awkward offset — SSE does not respect chunk boundaries.
async function* shredded(frames: string[], at: number) {
  const all = frames.join("")
  for (let i = 0; i < all.length; i += at) yield all.slice(i, i + at)
}

// ---- 1. MferenceServer shape: content only, usage on the final frame with cached_tokens
{
  const tk = ticking(100)
  const frames = [
    delta({ role: "assistant", content: "" }),          // t=100, empty: not a token
    delta({ content: "Hello" }),                        // t=200 first token
    delta({ content: " there" }),                       // t=300
    delta({ content: "." }, {}),                        // t=400 last token
    frame({ choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
      usage: { prompt_tokens: 40, completion_tokens: 3,
        prompt_tokens_details: { cached_tokens: 19 } } }),
    "data: [DONE]\n\n",
  ]
  const m = await accumulateSSE(timed(frames, tk), tk.clock, 0)
  check("mference: content", m.content === "Hello there.", JSON.stringify(m.content))
  check("mference: no reasoning", m.reasoning === "" && m.reasoningSource === "none")
  check("mference: ttfb is the first frame", m.ttfbMs === 100, String(m.ttfbMs))
  check("mference: empty delta is not a token", m.ttftMs === 200, String(m.ttftMs))
  check("mference: ttfc == ttft when there is no reasoning", m.ttfcMs === 200, String(m.ttfcMs))
  check("mference: last token", m.lastTokenMs === 400, String(m.lastTokenMs))
  check("mference: usage + cached", m.usage?.completion_tokens === 3 && m.usage?.cached_tokens === 19, JSON.stringify(m.usage))
  // 3 usage tokens, first one paid for in TTFT: (3-1) over 200 ms = 10 tok/s
  check("mference: tok/s on usage basis, n-1", m.tokPerSecBasis === "usage" && Math.abs((m.tokPerSec ?? 0) - 10) < 1e-9, `${m.tokPerSec} ${m.tokPerSecBasis}`)
  check("mference: finish + done", m.finishReason === "stop" && m.done)
}

// ---- 2. LM Studio structured reasoning_content, usage via stream_options on the last frame
{
  const tk = ticking(100)
  const frames = [
    delta({ role: "assistant" }),                              // 100
    delta({ reasoning_content: "Let me think" }),              // 200 first token (reasoning)
    delta({ reasoning_content: " about it." }),                // 300
    delta({ content: "42" }),                                  // 400 first ANSWER token
    delta({ content: "." }),                                   // 500
    frame({ choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
      usage: { prompt_tokens: 30, completion_tokens: 12,
        completion_tokens_details: { reasoning_tokens: 8 } } }),
    "data: [DONE]\n\n",
  ]
  const m = await accumulateSSE(timed(frames, tk), tk.clock, 0)
  check("lmstudio-rc: reasoning captured", m.reasoning === "Let me think about it." && m.reasoningSource === "reasoning_content", `${m.reasoningSource} ${JSON.stringify(m.reasoning)}`)
  check("lmstudio-rc: content excludes reasoning", m.content === "42.", JSON.stringify(m.content))
  check("lmstudio-rc: ttft is the first reasoning token", m.ttftMs === 200, String(m.ttftMs))
  check("lmstudio-rc: ttfc is the first answer token, later", m.ttfcMs === 400 && m.ttfcMs > (m.ttftMs ?? 0), String(m.ttfcMs))
  check("lmstudio-rc: reasoning tokens from usage", m.usage?.reasoning_tokens === 8, JSON.stringify(m.usage))
  check("lmstudio-rc: no cached_tokens is null, not 0", m.usage?.cached_tokens === null)
}

// ---- 3. LM Studio inline <think> (Qwen-thinking path), NO usage anywhere → frames basis
{
  const tk = ticking(100)
  const frames = [
    delta({ content: "<think>" }),                 // 100: opens think; no visible token
    delta({ content: "hmm, " }),                   // 200 first token (reasoning)
    delta({ content: "yes</think>" }),             // 300 reasoning "yes", then closes
    delta({ content: "Sure" }),                    // 400 first answer token
    delta({ content: "!" }),                       // 500
    frame({ choices: [{ index: 0, delta: {}, finish_reason: "stop" }] }),
    "data: [DONE]\n\n",
  ]
  const m = await accumulateSSE(timed(frames, tk), tk.clock, 0)
  check("inline-think: source", m.reasoningSource === "inline_think", m.reasoningSource)
  check("inline-think: reasoning text", m.reasoning === "hmm, yes", JSON.stringify(m.reasoning))
  check("inline-think: content is only the answer", m.content === "Sure!", JSON.stringify(m.content))
  check("inline-think: bare <think> tag is not a token", m.ttftMs === 200, String(m.ttftMs))
  check("inline-think: ttfc after the close tag", m.ttfcMs === 400, String(m.ttfcMs))
  check("inline-think: no usage → frames basis", m.usage === null && m.tokPerSecBasis === "frames", `${m.usage} ${m.tokPerSecBasis}`)
  // 4 counted deltas (hmm, yes, Sure, !) over 300 ms, n-1 → 3 / 0.3
  check("inline-think: frames rate, n-1", Math.abs((m.tokPerSec ?? 0) - 3 / 0.3) < 1e-9, String(m.tokPerSec))
}

// ---- 4. Fragmented tool calls by index, two calls interleaved; finish_reason tool_calls
{
  const tk = ticking(50)
  const frames = [
    delta({ tool_calls: [{ index: 0, id: "call_a", type: "function", function: { name: "run_command", arguments: "" } }] }),
    delta({ tool_calls: [{ index: 1, id: "call_b", type: "function", function: { name: "read_file", arguments: "" } }] }),
    delta({ tool_calls: [{ index: 0, function: { arguments: "{\"command\":" } }] }),
    delta({ tool_calls: [{ index: 1, function: { arguments: "{\"path\":\"a.txt\"}" } }] }),
    delta({ tool_calls: [{ index: 0, function: { arguments: "\"ls\"}" } }] }),
    frame({ choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }],
      usage: { prompt_tokens: 50, completion_tokens: 20 } }),
    "data: [DONE]\n\n",
  ]
  const m = await accumulateSSE(timed(frames, tk), tk.clock, 0)
  check("tools: two calls reassembled", m.toolCalls.length === 2, String(m.toolCalls.length))
  check("tools: joined by index not frame order", m.toolCalls[0].name === "run_command" && m.toolCalls[0].arguments === "{\"command\":\"ls\"}", JSON.stringify(m.toolCalls[0]))
  check("tools: second call intact", m.toolCalls[1].id === "call_b" && m.toolCalls[1].arguments === "{\"path\":\"a.txt\"}", JSON.stringify(m.toolCalls[1]))
  check("tools: a tool fragment is an answer token", m.ttfcMs === 50, String(m.ttfcMs))
  check("tools: finish_reason", m.finishReason === "tool_calls", String(m.finishReason))
  check("tools: not flagged as unparsed", m.unparsedToolCallText === false)
}

// ---- 5. Server failed to parse the Qwen XML dialect: <tool_call> lands in content
{
  const tk = ticking(10)
  const frames = [
    delta({ content: "<tool_call>\n<function=run_command>\n<parameter=command>ls</parameter>\n</function>\n</tool_call>" }),
    frame({ choices: [{ index: 0, delta: {}, finish_reason: "stop" }] }),
    "data: [DONE]\n\n",
  ]
  const m = await accumulateSSE(timed(frames, tk), tk.clock, 0)
  check("unparsed: flagged", m.unparsedToolCallText === true && m.toolCalls.length === 0)
}

// ---- 6. Chunk boundaries: the same bytes shredded at 7-byte pieces give the same text
{
  const frames = [
    delta({ reasoning_content: "think " }),
    delta({ content: "ans" }),
    delta({ content: "wer" }),
    frame({ choices: [{ index: 0, delta: {}, finish_reason: "stop" }], usage: { prompt_tokens: 1, completion_tokens: 3 } }),
    "data: [DONE]\n\n",
  ]
  let t = 0
  const m = await accumulateSSE(shredded(frames, 7), () => ++t, 0)
  check("shredded: content survives odd chunking", m.content === "answer" && m.reasoning === "think ", `${JSON.stringify(m.content)} ${JSON.stringify(m.reasoning)}`)
  check("shredded: frames counted once each", m.frames === 5, String(m.frames))
  check("shredded: usage still found", m.usage?.completion_tokens === 3)
  check("shredded: done", m.done)
}

// ---- 7. Single token is not a rate; malformed frame is ignored
{
  const tk = ticking(100)
  const frames = [
    "data: {not json\n\n",
    delta({ content: "x" }),
    "data: [DONE]\n\n",
  ]
  const m = await accumulateSSE(timed(frames, tk), tk.clock, 0)
  check("edge: one token → no tok/s", m.tokPerSec === null && m.tokPerSecBasis === null)
  check("edge: malformed frame counted as frame, not token", m.frames === 3 && m.deltaCount === 1, `${m.frames} ${m.deltaCount}`)
}

if (failed) { console.log(`\n${failed} assertion(s) failed`); process.exit(1) }
console.log("check-brain-eval-sse: all assertions passed")
TS

cp "$ROOT/scripts/brain-eval/sse.ts" "$TMP/sse.ts"
bun run "$TMP/driver.ts"

# Stage 2: the real path — fetch, ReadableStream, TextDecoder, readSSE — against both
# stub personas. The synthetic fixtures above never touch that plumbing. Ports are high
# and checked first; something already listening is not ours to kill (AGENTS.md rule 8).
PT=8141; PV=8142
for port in $PT $PV; do
  if lsof -ti "tcp:$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "check-brain-eval-sse: SKIP live stage (something already listens on :$port — not killing it)"
    exit 0
  fi
done
bun run "$ROOT/scripts/brain-eval/stub-server.ts" --port $PT --persona textonly >"$TMP/t.log" 2>&1 &
TPID=$!
bun run "$ROOT/scripts/brain-eval/stub-server.ts" --port $PV --persona vision >"$TMP/v.log" 2>&1 &
VPID=$!
trap 'kill $TPID $VPID 2>/dev/null; rm -rf "$TMP"' EXIT
i=0; while [ $i -lt 50 ]; do
  curl -sf "http://127.0.0.1:$PT/v1/models" >/dev/null 2>&1 && curl -sf "http://127.0.0.1:$PV/v1/models" >/dev/null 2>&1 && break
  i=$((i+1)); sleep 0.1
done

cat > "$TMP/live.ts" <<'TS'
import { readSSE } from "./sse.ts"
let failed = 0
const check = (name: string, cond: boolean, detail = "") => {
  if (!cond) { console.log(`  FAIL ${name} ${detail}`); failed++ } else console.log(`  ok   ${name} ${detail}`)
}
async function run(port: string) {
  const started = Date.now()
  const res = await fetch(`http://127.0.0.1:${port}/v1/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ model: "x", stream: true, stream_options: { include_usage: true },
      messages: [{ role: "user", content: "Count: one two three." }] }),
  })
  return readSSE(res, started)
}
const t = await run(process.argv[2])
check("live textonly: content", t.content === "one two three", JSON.stringify(t.content))
check("live textonly: no reasoning", t.reasoningSource === "none")
check("live textonly: usage via stream_options", t.usage?.completion_tokens === 3 && t.usage?.cached_tokens === 0, JSON.stringify(t.usage))
check("live textonly: done", t.done && t.finishReason === "stop")

const v = await run(process.argv[3])
check("live vision: reasoning split", v.reasoningSource === "reasoning_content" && v.reasoning === "Let me count carefully.", `${v.reasoningSource} ${JSON.stringify(v.reasoning)}`)
check("live vision: content is the answer only", v.content === "one two three", JSON.stringify(v.content))
check("live vision: ttfc after ttft (thinking took time)", v.ttftMs !== null && v.ttfcMs !== null && v.ttfcMs > v.ttftMs, `ttft=${v.ttftMs} ttfc=${v.ttfcMs}`)
check("live vision: paced frames give a finite rate on usage basis", v.tokPerSecBasis === "usage" && (v.tokPerSec ?? 0) > 0 && (v.tokPerSec ?? 0) < 200, `${v.tokPerSec?.toFixed(1)} ${v.tokPerSecBasis}`)
check("live vision: no cached_tokens → null", v.usage?.cached_tokens === null && v.usage?.reasoning_tokens === 2, JSON.stringify(v.usage))
// The slow persona must be measurably slower than the fast one — that is the whole point.
check("live: vision persona is slower to first answer token", (v.ttfcMs ?? 0) > (t.ttfcMs ?? 0) + 50, `vision=${v.ttfcMs} textonly=${t.ttfcMs}`)
if (failed) { console.log(`\n${failed} live assertion(s) failed`); process.exit(1) }
console.log("check-brain-eval-sse: live stage passed")
TS
bun run "$TMP/live.ts" $PT $PV

/**
 * Accumulate an OpenAI-style chat-completions SSE stream into text, tool calls, usage
 * and TIMING — the numbers that let two local servers be compared honestly.
 *
 * Why a separate module: the two servers we grade do not put the same things in the
 * same places.
 *
 *  - Reasoning models (Ornith, Qwen thinking variants) emit a chain of thought before
 *    the answer. LM Studio surfaces it three different ways depending on the model and
 *    version: `delta.reasoning_content` (DeepSeek-R1 path), `delta.reasoning`
 *    (gpt-oss path), or inline `<think>…</think>` inside `delta.content` (Qwen3-thinking
 *    path, lmstudio-bug-tracker #1569). All three are folded into `reasoning` here so
 *    that time-to-first-CONTENT-token and tokens/sec are measured on the answer, not on
 *    the thinking. A model that thinks for 20 s and answers in 1 s has a TTFT of ~20 s
 *    from the user's point of view, and that is the number reported as `ttfcMs`.
 *
 *  - `usage` is only reliably present on the stream when the client asks for it
 *    (`stream_options.include_usage`, which LM Studio honours) or when the server
 *    always sends it (MferenceServer). When it is absent, tokens/sec falls back to
 *    counting non-empty content deltas — one delta is usually one token but not always,
 *    so `tokPerSecBasis` says which was used. A number without its basis is a guess.
 *
 *  - Tool calls arrive as fragments across frames (`delta.tool_calls[i].function.
 *    arguments` accumulates) and must be joined by index, never by frame order alone.
 *
 * Pure: takes an async iterable of text chunks and a clock, so it can be tested with
 * synthetic streams and no server.
 */

export type StreamToolCall = { id: string; name: string; arguments: string }

export type StreamUsage = {
  prompt_tokens: number | null
  completion_tokens: number | null
  cached_tokens: number | null
  reasoning_tokens: number | null
}

export type StreamMetrics = {
  content: string
  reasoning: string
  reasoningSource: "reasoning_content" | "reasoning" | "inline_think" | "none"
  toolCalls: StreamToolCall[]
  /** `<tool_call>` text that the SERVER failed to parse into tool_calls — a config/parser
   *  finding, distinct from the model answering in prose. */
  unparsedToolCallText: boolean
  finishReason: string | null
  usage: StreamUsage | null
  frames: number
  done: boolean
  /** ms from start to the first `data:` frame of any kind */
  ttfbMs: number | null
  /** ms to the first token of ANY kind — reasoning, content or tool fragment */
  ttftMs: number | null
  /** ms to the first ANSWER token — content outside <think>, or a tool-call fragment */
  ttfcMs: number | null
  lastTokenMs: number | null
  /** completion tokens / generation seconds, on the stated basis */
  tokPerSec: number | null
  tokPerSecBasis: "usage" | "frames" | null
  /** non-empty content/reasoning/tool deltas — the fallback token estimate */
  deltaCount: number
}

function num(x: unknown): number | null {
  return typeof x === "number" && Number.isFinite(x) ? x : null
}

export function emptyMetrics(): StreamMetrics {
  return {
    content: "",
    reasoning: "",
    reasoningSource: "none",
    toolCalls: [],
    unparsedToolCallText: false,
    finishReason: null,
    usage: null,
    frames: 0,
    done: false,
    ttfbMs: null,
    ttftMs: null,
    ttfcMs: null,
    lastTokenMs: null,
    tokPerSec: null,
    tokPerSecBasis: null,
    deltaCount: 0,
  }
}

/**
 * @param chunks   async iterable of decoded text (an SSE body, in arbitrary pieces)
 * @param clock    returns ms; injected so tests are deterministic
 * @param startMs  clock value at the moment the request was sent
 */
export async function accumulateSSE(
  chunks: AsyncIterable<string> | Iterable<string>,
  clock: () => number,
  startMs: number,
): Promise<StreamMetrics> {
  const m = emptyMetrics()
  let buf = ""
  let inThink = false
  const calls = new Map<number, StreamToolCall>()

  const markToken = (isAnswer: boolean) => {
    const t = clock() - startMs
    if (m.ttftMs === null) m.ttftMs = t
    if (isAnswer && m.ttfcMs === null) m.ttfcMs = t
    m.lastTokenMs = t
    m.deltaCount++
  }

  const handleFrame = (line: string) => {
    if (!line.startsWith("data:")) return
    m.frames++
    if (m.ttfbMs === null) m.ttfbMs = clock() - startMs
    const payload = line.slice(5).trim()
    if (payload === "[DONE]") {
      m.done = true
      return
    }
    let obj: any
    try {
      obj = JSON.parse(payload)
    } catch {
      return // a malformed frame is not a token
    }

    if (obj?.usage && typeof obj.usage === "object") {
      m.usage = {
        prompt_tokens: num(obj.usage.prompt_tokens),
        completion_tokens: num(obj.usage.completion_tokens),
        cached_tokens: num(obj.usage.prompt_tokens_details?.cached_tokens),
        reasoning_tokens: num(obj.usage.completion_tokens_details?.reasoning_tokens),
      }
    }

    const choice = obj?.choices?.[0]
    if (!choice) return
    if (typeof choice.finish_reason === "string" && choice.finish_reason) {
      m.finishReason = choice.finish_reason
    }
    const delta = choice.delta ?? {}

    // Structured reasoning fields take precedence over inline tags.
    const rc = typeof delta.reasoning_content === "string" ? delta.reasoning_content : ""
    const r = typeof delta.reasoning === "string" ? delta.reasoning : ""
    if (rc) {
      m.reasoning += rc
      if (m.reasoningSource === "none") m.reasoningSource = "reasoning_content"
      markToken(false)
    } else if (r) {
      m.reasoning += r
      if (m.reasoningSource === "none") m.reasoningSource = "reasoning"
      markToken(false)
    }

    if (typeof delta.content === "string" && delta.content.length) {
      // Inline <think> handling: split the delta at tag boundaries. Tags can straddle
      // deltas in principle; that case is left as content, which errs toward counting
      // thinking as answer rather than dropping answer text.
      let text = delta.content
      while (text.length) {
        if (inThink) {
          const end = text.indexOf("</think>")
          if (end < 0) {
            m.reasoning += text
            markToken(false)
            text = ""
          } else {
            m.reasoning += text.slice(0, end)
            if (end > 0) markToken(false)
            inThink = false
            text = text.slice(end + "</think>".length)
          }
        } else {
          const start = text.indexOf("<think>")
          if (start < 0) {
            m.content += text
            markToken(true)
            text = ""
          } else {
            const before = text.slice(0, start)
            if (before.trim().length) {
              m.content += before
              markToken(true)
            }
            inThink = true
            if (m.reasoningSource === "none") m.reasoningSource = "inline_think"
            text = text.slice(start + "<think>".length)
          }
        }
      }
    }

    if (Array.isArray(delta.tool_calls)) {
      for (const tc of delta.tool_calls) {
        const idx = typeof tc?.index === "number" ? tc.index : 0
        const cur = calls.get(idx) ?? { id: "", name: "", arguments: "" }
        if (typeof tc?.id === "string") cur.id += tc.id
        if (typeof tc?.function?.name === "string") cur.name += tc.function.name
        if (typeof tc?.function?.arguments === "string") cur.arguments += tc.function.arguments
        calls.set(idx, cur)
        markToken(true)
      }
    }
  }

  const feed = (text: string) => {
    buf += text
    let nl: number
    while ((nl = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, nl).replace(/\r$/, "")
      buf = buf.slice(nl + 1)
      handleFrame(line)
    }
  }

  for await (const c of chunks as AsyncIterable<string>) feed(c)
  if (buf.length) handleFrame(buf)

  m.toolCalls = [...calls.entries()].sort((a, b) => a[0] - b[0]).map(([, c]) => c)
  // A model that emitted the Qwen XML dialect which the server did not parse: the
  // harness must not grade that as "answered in prose".
  m.unparsedToolCallText = m.toolCalls.length === 0 && /<tool_call>/.test(m.content)

  // tokens/sec is over the GENERATION window (first token → last token), which excludes
  // prefill by construction. Fewer than two tokens is not a rate.
  if (m.ttftMs !== null && m.lastTokenMs !== null && m.lastTokenMs > m.ttftMs) {
    const secs = (m.lastTokenMs - m.ttftMs) / 1000
    const usageTokens = m.usage?.completion_tokens ?? null
    if (usageTokens !== null && usageTokens > 1) {
      m.tokPerSec = usageTokens / secs
      m.tokPerSecBasis = "usage"
    } else if (m.deltaCount > 1) {
      m.tokPerSec = m.deltaCount / secs
      m.tokPerSecBasis = "frames"
    }
  }
  return m
}

/** Convenience: drive a fetch Response body through accumulateSSE with the real clock. */
export async function readSSE(res: Response, startMs: number): Promise<StreamMetrics> {
  const decoder = new TextDecoder()
  const reader = res.body?.getReader()
  async function* chunks() {
    if (!reader) return
    for (;;) {
      const { value, done } = await reader.read()
      if (done) break
      yield decoder.decode(value, { stream: true })
    }
    yield decoder.decode()
  }
  return accumulateSSE(chunks(), () => Date.now(), startMs)
}

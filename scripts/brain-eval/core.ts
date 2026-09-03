/**
 * Shared types and the one HTTP path every probe uses.
 *
 * Probes never call fetch themselves for chat completions: they call chat(), which is
 * where compare mode swaps in a streamed request (for TTFT and tok/s) and records the
 * exact request and response for the dataset export. Keeping that in one place is what
 * lets the same probe code grade an endpoint in either mode with identical bodies.
 */
import { accumulateSSE, type StreamMetrics } from "./sse.ts"

export type Status = "pass" | "fail" | "unsupported" | "skip"

/** Why a probe failed — the tags, not the pass counts, say what dataset to build. */
export type FailureMode =
  | "prose-only" | "multi-line-command" | "heredoc" | "hallucinated-path" | "hallucinated-udid"
  | "non-unique-find" | "find-not-found" | "wrong-target" | "repeated-failing-command"
  | "premature-finish" | "eager-escalate" | "no-finish" | "redundant-action" | "edit-before-read"
  | "guessed-selector" | "needless-navigate" | "wrong-value" | "blind-send" | "wrong-session"
  | "typed-into-wrong-app" | "shortcut-as-text" | "unknown-tool" | "malformed-arguments"
  | "unparsed-tool-call" | "truncated" | "http-error" | "timeout" | "other"

export type UseCase = "CLI" | "browser" | "macOS" | "iOS simulator" | "Android" | "shipping" | "economics" | "reachability"

export interface ProbeResult {
  id: string
  title: string
  capability: string
  useCase: UseCase
  status: Status
  detail: string
  ms: number
  failureMode: FailureMode | null
  meta?: Record<string, unknown>
}

export type Outcome = { status: Status; detail: string; failureMode?: FailureMode | null; meta?: Record<string, unknown> }

export interface Probe {
  id: string
  title: string
  capability: string
  useCase: UseCase
  run(ctx: Ctx): Promise<Outcome>
}

export interface Perf {
  ttftMs: number | null        // first token of any kind, including reasoning
  ttfcMs: number | null        // first ANSWER token — content outside <think>, or a tool fragment
  genTokPerSec: number | null  // (completion tokens - 1) / first→last token window, or burst
  tokensBasis: "usage" | "frames" | "burst" | null
  charsPerSec: number | null   // tokenizer-neutral secondary
  completionTokens: number | null
  promptTokens: number | null
  cachedTokens: number | null
  reasoningTokens: number | null
  reasoningSource: StreamMetrics["reasoningSource"]
  reasoningChars: number
  prefillTokPerSec: number | null  // (prompt - cached) / ttft, only when both known
  frames: number
  totalMs: number
  streamOptionsAccepted: boolean
}

export interface Turn {
  index: number
  startedAt: string
  request: { url: string; body: Record<string, unknown> }
  response: { httpStatus: number; body: unknown; raw: string | null; perf: Perf | null }
}

export interface Ctx {
  endpoint: string
  model: string
  apiKey?: string
  timeoutMs: number
  temperature: number
  maxTokens: number
  /** Appended as a line to every system prompt so TTFT is cold-prefill on both endpoints. */
  cacheBust: string | null
  /** Compare mode: send streamed requests and measure them. */
  streamPerf: boolean
  /** Compare mode: every turn is handed here for the dataset export. */
  record?: (turn: Turn) => void
  /** Internal: index of the next turn within the current probe. */
  turnIndex?: number
}

export function parseArgs(argv: string[]): Record<string, string | boolean> {
  const out: Record<string, string | boolean> = {}
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (!a.startsWith("--")) continue
    const key = a.slice(2)
    const next = argv[i + 1]
    if (next === undefined || next.startsWith("--")) out[key] = true
    else {
      out[key] = next
      i++
    }
  }
  return out
}

export async function apiFetch(
  ctx: Ctx,
  path: string,
  init?: RequestInit,
): Promise<{ status: number; body: any; raw: string }> {
  const headers: Record<string, string> = { "content-type": "application/json" }
  if (ctx.apiKey) headers.authorization = `Bearer ${ctx.apiKey}`
  const res = await fetch(`${ctx.endpoint}${path}`, {
    ...init,
    headers: { ...headers, ...(init?.headers as Record<string, string> | undefined) },
    signal: AbortSignal.timeout(ctx.timeoutMs),
  })
  const raw = await res.text()
  let body: any = null
  try {
    body = JSON.parse(raw)
  } catch {
    /* non-JSON (SSE or an error page) stays in raw */
  }
  return { status: res.status, body, raw }
}

function withCacheBust(ctx: Ctx, messages: any[]): any[] {
  if (!ctx.cacheBust) return messages
  const line = `\n[run ${ctx.cacheBust}]`
  const out = messages.map((m) => ({ ...m }))
  const sys = out.find((m) => m.role === "system")
  if (sys && typeof sys.content === "string") sys.content += line
  else out.unshift({ role: "system", content: line.trim() })
  return out
}

export function chatRequestBody(ctx: Ctx, extra: Record<string, unknown>): Record<string, unknown> {
  const body: Record<string, unknown> = {
    model: ctx.model,
    temperature: ctx.temperature,
    max_tokens: ctx.maxTokens,
    ...extra,
  }
  if (Array.isArray(body.messages)) body.messages = withCacheBust(ctx, body.messages as any[])
  return body
}

function perfFrom(m: StreamMetrics, totalMs: number, streamOptionsAccepted: boolean): Perf {
  const chars = m.content.length + m.toolCalls.reduce((n, c) => n + c.arguments.length, 0)
  const window = m.ttftMs !== null && m.lastTokenMs !== null ? (m.lastTokenMs - m.ttftMs) / 1000 : null
  const prompt = m.usage?.prompt_tokens ?? null
  const cached = m.usage?.cached_tokens ?? null
  return {
    ttftMs: m.ttftMs,
    ttfcMs: m.ttfcMs,
    genTokPerSec: m.tokPerSec,
    tokensBasis: m.tokPerSecBasis,
    charsPerSec: window && window > 0 ? chars / window : null,
    completionTokens: m.usage?.completion_tokens ?? null,
    promptTokens: prompt,
    cachedTokens: cached,
    reasoningTokens: m.usage?.reasoning_tokens ?? null,
    reasoningSource: m.reasoningSource,
    reasoningChars: m.reasoning.length,
    prefillTokPerSec:
      prompt !== null && cached !== null && m.ttftMs !== null && m.ttftMs > 0 ? (prompt - cached) / (m.ttftMs / 1000) : null,
    frames: m.frames,
    totalMs,
    streamOptionsAccepted,
  }
}

/** Rebuild the non-streamed response shape from a stream, so probe code is mode-agnostic. */
function bodyFromStream(m: StreamMetrics, model: string): any {
  const message: any = { role: "assistant", content: m.content.length ? m.content : null }
  if (m.reasoning.length) message.reasoning_content = m.reasoning
  if (m.toolCalls.length) {
    message.tool_calls = m.toolCalls.map((c, i) => ({
      id: c.id || `call_${i + 1}`,
      type: "function",
      function: { name: c.name, arguments: c.arguments },
    }))
  }
  const usage: any = m.usage
    ? {
        prompt_tokens: m.usage.prompt_tokens,
        completion_tokens: m.usage.completion_tokens,
        prompt_tokens_details: m.usage.cached_tokens !== null ? { cached_tokens: m.usage.cached_tokens } : undefined,
        completion_tokens_details: m.usage.reasoning_tokens !== null ? { reasoning_tokens: m.usage.reasoning_tokens } : undefined,
      }
    : undefined
  return {
    object: "chat.completion",
    model,
    choices: [{ index: 0, message, finish_reason: m.finishReason ?? (m.toolCalls.length ? "tool_calls" : "stop") }],
    usage,
    _stream: { unparsedToolCallText: m.unparsedToolCallText },
  }
}

async function streamOnce(ctx: Ctx, body: Record<string, unknown>) {
  const headers: Record<string, string> = { "content-type": "application/json" }
  if (ctx.apiKey) headers.authorization = `Bearer ${ctx.apiKey}`
  const t0 = performance.now()
  const res = await fetch(`${ctx.endpoint}/chat/completions`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(ctx.timeoutMs),
  })
  if (res.status !== 200) {
    const raw = await res.text()
    let parsed: any = null
    try { parsed = JSON.parse(raw) } catch { /* keep raw */ }
    return { status: res.status, body: parsed, raw, metrics: null as StreamMetrics | null, totalMs: performance.now() - t0 }
  }
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
  const metrics = await accumulateSSE(chunks(), () => performance.now(), t0)
  return { status: 200, body: null, raw: null as string | null, metrics, totalMs: performance.now() - t0 }
}

/**
 * The one chat call. In single-endpoint mode it is a plain non-streamed POST. In compare
 * mode it streams (identical body plus stream flags), measures, and reconstructs the
 * non-streamed shape so the probe's structural checks see exactly what was timed.
 */
export async function chat(ctx: Ctx, extra: Record<string, unknown>) {
  const base = chatRequestBody(ctx, extra)
  const turnIndex = ctx.turnIndex ?? 0
  ctx.turnIndex = turnIndex + 1
  const startedAt = new Date().toISOString()

  if (!ctx.streamPerf) {
    const t0 = performance.now()
    const r = await apiFetch(ctx, "/chat/completions", { method: "POST", body: JSON.stringify(base) })
    ctx.record?.({
      index: turnIndex,
      startedAt,
      request: { url: `${ctx.endpoint}/chat/completions`, body: base },
      response: { httpStatus: r.status, body: r.body, raw: r.body ? null : r.raw.slice(0, 4000), perf: null },
    })
    return r
  }

  let body = { ...base, stream: true, stream_options: { include_usage: true } }
  let streamOptionsAccepted = true
  let s = await streamOnce(ctx, body)
  if (s.status === 400) {
    // Some servers reject stream_options outright; that is a finding, not a probe failure.
    streamOptionsAccepted = false
    body = { ...base, stream: true } as any
    s = await streamOnce(ctx, body)
  }
  if (s.status !== 200 || !s.metrics) {
    ctx.record?.({
      index: turnIndex,
      startedAt,
      request: { url: `${ctx.endpoint}/chat/completions`, body },
      response: { httpStatus: s.status, body: s.body, raw: s.body ? null : (s.raw ?? "").slice(0, 4000), perf: null },
    })
    return { status: s.status, body: s.body, raw: s.raw ?? "" }
  }

  // The streamed sample is the sample: it is graded as-is. Re-issuing a non-streamed
  // request when fragments fail to parse would grade a DIFFERENT sample (a fresh draw at
  // any temperature above 0), hide malformed-arguments in compare mode, and run a whole
  // second generation inside the probe's timed window. Malformed fragments are a finding.
  const responseBody = bodyFromStream(s.metrics, ctx.model)
  const perf = perfFrom(s.metrics, s.totalMs, streamOptionsAccepted)
  ctx.record?.({
    index: turnIndex,
    startedAt,
    request: { url: `${ctx.endpoint}/chat/completions`, body },
    response: { httpStatus: 200, body: responseBody, raw: null, perf },
  })
  return { status: 200, body: responseBody, raw: JSON.stringify(responseBody) }
}

/** Pull tool calls out of a response in the shape every OpenAI-compatible server emits. */
export function toolCalls(body: any): Array<{ name: string; args: any; rawArgs: string }> {
  const calls = body?.choices?.[0]?.message?.tool_calls
  if (!Array.isArray(calls)) return []
  return calls.map((c: any) => {
    const rawArgs = c?.function?.arguments ?? ""
    let args: any = null
    try {
      args = typeof rawArgs === "string" ? JSON.parse(rawArgs) : rawArgs
    } catch {
      /* leave null; malformed arguments is itself a finding */
    }
    return { name: c?.function?.name ?? "", args, rawArgs }
  })
}

export function content(body: any): string {
  return body?.choices?.[0]?.message?.content ?? ""
}

/** True when the model emitted the Qwen XML dialect and the SERVER failed to parse it. */
export function unparsedToolCallText(body: any): boolean {
  if (body?._stream?.unparsedToolCallText) return true
  const text = content(body)
  return !toolCalls(body).length && /<tool_call>/.test(text)
}

/**
 * A reply cut off by max_tokens is the harness's budget, not the model's capability.
 * Reasoning models spend the budget on the think block first; when nothing came out,
 * grading that as prose-only would fail the model for the probe's settings.
 */
export function truncatedOutcome(body: any): Outcome | null {
  const choice = body?.choices?.[0]
  if (choice?.finish_reason !== "length") return null
  if (toolCalls(body).length) return null
  const text = content(body)
  if (text.trim().length) return null
  const reasoning = choice?.message?.reasoning_content
  const detail = typeof reasoning === "string" && reasoning.length
    ? `max_tokens exhausted after ${reasoning.length} chars of reasoning; raise --max-tokens`
    : "max_tokens exhausted before any answer; raise --max-tokens"
  return { status: "fail", detail, failureMode: "truncated" }
}

/** Qwen's parser types opportunistically ("true" → true, "2024" → 2024); coerce, never reject. */
export function asStr(v: unknown): string {
  if (typeof v === "string") return v
  if (v === null || v === undefined) return ""
  if (typeof v === "object") return JSON.stringify(v)
  return String(v)
}

export function median(xs: number[]): number | null {
  const v = xs.filter((x) => Number.isFinite(x)).sort((a, b) => a - b)
  if (!v.length) return null
  const mid = Math.floor(v.length / 2)
  return v.length % 2 ? v[mid] : (v[mid - 1] + v[mid]) / 2
}

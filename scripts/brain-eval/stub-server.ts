#!/usr/bin/env bun
/**
 * A deliberately dumb OpenAI-compatible endpoint used to verify eval.ts itself — never a
 * model. Every branch of every probe has to be reachable without a Mac, including the
 * failure branches, so a comparison can be proven to DETECT a difference rather than
 * merely run twice.
 *
 * Three personas:
 *   textonly (default) — the MferenceServer shape: refuses images, reports cached_tokens,
 *              no reasoning, answers every probe well and instantly.
 *   vision   — an LM Studio-with-a-reasoning-model shape: accepts images, streams a
 *              reasoning_content block before the answer, never reports cached_tokens,
 *              paces frames so TTFT and tok/s differ measurably. Answers every probe well.
 *   dumb     — the textonly shape, but every use-case probe gets its canonical
 *              small-model failure, so each failure-mode tag is exercised end to end.
 *
 * The streamed path emits exactly the message the non-streamed path would return —
 * content split per word, tool calls as index fragments, a usage frame when
 * stream_options.include_usage is set — because compare mode streams every probe.
 *
 *   bun run scripts/brain-eval/stub-server.ts --port 8099 [--persona textonly|vision|dumb]
 */

const args = Bun.argv.slice(2)
const portArg = args.indexOf("--port")
const port = portArg >= 0 ? Number(args[portArg + 1]) : 8099
const personaArg = args.indexOf("--persona")
const persona = personaArg >= 0 ? String(args[personaArg + 1]) : "textonly"
if (persona !== "textonly" && persona !== "vision" && persona !== "dumb") {
  console.error(`unknown --persona ${persona}; use textonly, vision or dumb`)
  process.exit(2)
}
const MODEL_ID = persona === "vision" ? "stub-ornith" : persona === "dumb" ? "stub-dumb" : "stub-qwen36"
const FRAME_DELAY_MS = persona === "vision" ? 40 : 2
const reportsCache = persona !== "vision"
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } })
}

type Msg = { role: "assistant"; content: string | null; tool_calls?: Array<{ id: string; type: "function"; function: { name: string; arguments: string } }> }

function toolCall(name: string, args: Record<string, unknown>, id = "call_1") {
  return { id, type: "function" as const, function: { name, arguments: JSON.stringify(args) } }
}
const say = (content: string): Msg => ({ role: "assistant", content })
const calls = (...tc: ReturnType<typeof toolCall>[]): Msg => ({ role: "assistant", content: null, tool_calls: tc })

function hasImagePart(messages: any[]): boolean {
  return messages.some((m) => Array.isArray(m?.content) && m.content.some((p: any) => p?.type === "image_url"))
}

/**
 * The canned answer for a request. Keys are chosen so that the use-case probes are
 * matched BEFORE the older, looser branches (a tool-role last message with "fetchOrder"
 * in it must not fall through to the weather answer; browser_snapshot must win over
 * browser_navigate). Each use-case branch returns the good answer, or the designed
 * failure when the persona is dumb.
 */
function answer(body: any): Msg {
  const messages: any[] = body?.messages ?? []
  const tools: any[] = body?.tools ?? []
  const names = new Set(tools.map((t) => t?.function?.name))
  const text = JSON.stringify(messages)
  const last = messages.at(-1)
  const lastTool = last?.role === "tool" ? String(last.content ?? "") : null
  const dumb = persona === "dumb"

  // ---- use-case probes: a tool result is the last message
  if (lastTool !== null) {
    if (lastTool.includes("fetchOrder"))
      return dumb
        ? calls(toolCall("str_replace", { path: "src/util.ts", find: "{ timeout: 3000 }", replace: "{ timeout: 5000 }" }))
        : calls(toolCall("str_replace", { path: "src/util.ts", find: "return request(`/users/${id}`, { timeout: 3000 });", replace: "return request(`/users/${id}`, { timeout: 5000 });" }))
    if (lastTool.includes("command not found"))
      return dumb ? calls(toolCall("run_command", { command: "npm test" })) : calls(toolCall("run_command", { command: "cat package.json" }))
    if (lastTool.startsWith("wrote "))
      return dumb ? say("The file TODO.md has been created.") : calls(toolCall("finish", { summary: "Created empty TODO.md" }))
    if (lastTool.includes("== Devices =="))
      return dumb
        ? calls(toolCall("run_command", { command: "xcrun simctl launch booted com.mesh.notes" }))
        : calls(toolCall("run_command", { command: "xcrun simctl boot A1B2C3D4-0000-4000-8000-000000000016" }))
    if (lastTool.includes("xcodebuild log digested"))
      return dumb
        ? calls(toolCall("str_replace", { path: "/Users/arya/proj/Notes/LoginViewModel.swift", find: "isEnabled = true", replace: "isEnabled = !email.isEmpty" }))
        : calls(toolCall("read_file", { path: "/Users/arya/proj/NotesTests/LoginTests.swift" }))
    if (names.has("browser_snapshot") && lastTool.startsWith("page:"))
      return dumb
        ? calls(toolCall("browser_type", { selector: "#email", text: "dev@mesh.test" }, "call_1"), toolCall("browser_type", { selector: "#password", text: "hunter2" }, "call_2"), toolCall("browser_click", { selector: "#login" }, "call_3"))
        : calls(toolCall("browser_type", { selector: "#email-address", text: "dev@mesh.test" }, "call_1"), toolCall("browser_type", { selector: "#passcode", text: "hunter2" }, "call_2"), toolCall("browser_click", { selector: "button.btn-primary" }, "call_3"))
    if (names.has("app_activate") && lastTool.startsWith("frontmost:"))
      return dumb
        ? calls(toolCall("input_type", { text: "buy milk" }))
        : calls(toolCall("app_activate", { name: "Notes" }, "call_1"), toolCall("input_key", { key: "n", modifiers: ["cmd"] }, "call_2"), toolCall("input_type", { text: "buy milk" }, "call_3"))
  }

  // ---- use-case probes: first turn
  if (names.has("list_dir") && /greeting/.test(text) && lastTool === null)
    return dumb
      ? calls(toolCall("str_replace", { path: "config.json", find: '"greeting": "hi"', replace: '"greeting": "hello"' }))
      : calls(toolCall("list_dir", { path: "." }))
  if (names.has("run_command") && /hi\.sh/.test(text) && lastTool === null)
    return dumb
      ? calls(toolCall("run_command", { command: "mkdir -p scripts\ncat > scripts/hi.sh <<'EOF'\n#!/bin/sh\necho hi\nEOF\nchmod +x scripts/hi.sh" }))
      : calls(toolCall("write_file", { path: "scripts/hi.sh", content: "#!/bin/sh\necho hi\n" }, "call_1"), toolCall("run_command", { command: "chmod +x scripts/hi.sh" }, "call_2"))
  if (names.has("agent_output") && /quiet/.test(text))
    return dumb ? calls(toolCall("agent_send", { session: "deploy", text: "y", key: "enter" })) : calls(toolCall("agent_output", { session: "deploy", lines: 40 }))

  // ---- the original probes
  if (lastTool !== null) return say("It is 11C with drizzle in Berlin.")
  if (names.has("get_weather") && /weather/i.test(text)) return calls(toolCall("get_weather", { city: "Berlin", unit: "c" }))
  if (names.has("agent_send")) return calls(toolCall("agent_send", { session: "build", text: "y", key: "enter" }))
  if (names.has("browser_navigate"))
    return calls(toolCall("browser_navigate", { url: "https://example.com" }, "call_1"), toolCall("browser_type", { selector: "#q", text: "mesh" }, "call_2"))
  const stops: string[] = body?.stop ?? []
  if (stops.includes("HALT")) return say("alpha ")
  if (/Count: one two three/.test(text)) return say("one two three")
  return say("ready")
}

function usageFor(messages: any[], completionTokens: number) {
  const usage: Record<string, unknown> = { prompt_tokens: 128, completion_tokens: completionTokens, total_tokens: 128 + completionTokens }
  // Prefix reuse only kicks in once a conversation has history to reuse. The vision
  // persona imitates a server that does not report it at all — the probe must then say
  // "unsupported", never "fail".
  if (reportsCache) usage.prompt_tokens_details = { cached_tokens: messages.length > 2 ? 96 : 0 }
  else usage.completion_tokens_details = { reasoning_tokens: 2 }
  return usage
}

function completion(message: Msg, messages: any[]) {
  return {
    id: "chatcmpl-stub",
    object: "chat.completion",
    model: MODEL_ID,
    choices: [{ index: 0, message, finish_reason: message.tool_calls ? "tool_calls" : "stop" }],
    usage: usageFor(messages, 16),
  }
}

/** Stream the same message the non-streamed path returns, in the shapes real servers use. */
function streamed(message: Msg, messages: any[], includeUsage: boolean): Response {
  const enc = new TextEncoder()
  const frame = (delta: Record<string, unknown>, finish: string | null = null, extra: Record<string, unknown> = {}) =>
    enc.encode(`data: ${JSON.stringify({ choices: [{ index: 0, delta, finish_reason: finish }], ...extra })}\n\n`)
  const deltas: Array<Record<string, unknown>> = [{ role: "assistant" }]
  // The exact text is asserted by check-brain-eval-sse.sh's live stage.
  if (persona === "vision") deltas.push({ reasoning_content: "Let me count" }, { reasoning_content: " carefully." })
  let tokens = 0
  if (message.content) {
    const words = message.content.split(/(?<= )/)
    for (const w of words) deltas.push({ content: w })
    tokens += words.length
  }
  if (message.tool_calls) {
    message.tool_calls.forEach((tc, index) => {
      const a = tc.function.arguments
      const cut = Math.max(1, Math.floor(a.length / 2))
      deltas.push({ tool_calls: [{ index, id: tc.id, type: "function", function: { name: tc.function.name, arguments: "" } }] })
      deltas.push({ tool_calls: [{ index, function: { arguments: a.slice(0, cut) } }] })
      deltas.push({ tool_calls: [{ index, function: { arguments: a.slice(cut) } }] })
      tokens += 3
    })
  }
  const finish = message.tool_calls ? "tool_calls" : "stop"
  const stream = new ReadableStream({
    async start(controller) {
      for (const d of deltas) {
        if (FRAME_DELAY_MS) await sleep(FRAME_DELAY_MS)
        controller.enqueue(frame(d))
      }
      const extra = includeUsage ? { usage: usageFor(messages, Math.max(tokens, 2)) } : {}
      controller.enqueue(frame({}, finish, extra))
      controller.enqueue(enc.encode("data: [DONE]\n\n"))
      controller.close()
    },
  })
  return new Response(stream, { headers: { "content-type": "text/event-stream" } })
}

Bun.serve({
  port,
  async fetch(req: Request) {
    const url = new URL(req.url)
    if (url.pathname === "/v1/models") return json({ object: "list", data: [{ id: MODEL_ID, object: "model" }] })
    if (url.pathname !== "/v1/chat/completions") return json({ error: "not found" }, 404)

    const body = await req.json().catch(() => ({}) as any)
    const messages: any[] = body?.messages ?? []

    // Text-only: refuse multimodal content parts the way a real text engine does.
    if (persona !== "vision" && hasImagePart(messages)) {
      return json({ error: { message: "this model does not accept image content parts", type: "invalid_request_error", code: "unsupported_content" } }, 400)
    }

    const message = answer(body)
    if (body?.stream) return streamed(message, messages, body?.stream_options?.include_usage === true)
    return json(completion(message, messages))
  },
})

console.log(`stub endpoint on http://127.0.0.1:${port}/v1  persona=${persona} model=${MODEL_ID}`)

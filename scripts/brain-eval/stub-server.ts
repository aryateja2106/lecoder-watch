#!/usr/bin/env bun
/**
 * A deliberately dumb OpenAI-compatible endpoint used to verify eval.ts itself.
 *
 * It imitates a TEXT-ONLY engine — the shape MferenceServer has — so the
 * "reads images" probe exercises its unsupported branch rather than never
 * being run. It is a test fixture for the harness, not a model.
 *
 *   bun run scripts/brain-eval/stub-server.ts --port 8099
 */

const args = Bun.argv.slice(2)
const portArg = args.indexOf("--port")
const port = portArg >= 0 ? Number(args[portArg + 1]) : 8099

// Two personas, so a two-endpoint comparison can be verified to DETECT a difference
// rather than merely run twice:
//   textonly  (default) — the MferenceServer shape: refuses images, reports
//              cached_tokens, no reasoning, answers instantly.
//   vision    — an LM Studio-with-a-reasoning-model shape: accepts images, streams a
//              reasoning_content block before the answer, never reports cached_tokens,
//              and is deliberately slower per frame so TTFT and tok/s differ measurably.
const personaArg = args.indexOf("--persona")
const persona = personaArg >= 0 ? String(args[personaArg + 1]) : "textonly"
if (persona !== "textonly" && persona !== "vision") {
  console.error(`unknown --persona ${persona}; use textonly or vision`)
  process.exit(2)
}
const MODEL_ID = persona === "vision" ? "stub-ornith" : "stub-qwen36"
const FRAME_DELAY_MS = persona === "vision" ? 40 : 0
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  })
}

function completion(message: Record<string, unknown>, cachedTokens: number) {
  const usage: Record<string, unknown> = { prompt_tokens: 128, completion_tokens: 16, total_tokens: 144 }
  // The vision persona imitates a server that does not report prefix reuse at all —
  // the probe must then say "unsupported", never "fail".
  if (persona === "textonly") usage.prompt_tokens_details = { cached_tokens: cachedTokens }
  return {
    id: "chatcmpl-stub",
    object: "chat.completion",
    model: MODEL_ID,
    choices: [{ index: 0, message, finish_reason: message.tool_calls ? "tool_calls" : "stop" }],
    usage,
  }
}

function toolCall(name: string, args: Record<string, unknown>, id = "call_1") {
  return { id, type: "function", function: { name, arguments: JSON.stringify(args) } }
}

function hasImagePart(messages: any[]): boolean {
  return messages.some(
    (m) => Array.isArray(m?.content) && m.content.some((p: any) => p?.type === "image_url"),
  )
}

Bun.serve({
  port,
  async fetch(req) {
    const url = new URL(req.url)

    if (url.pathname === "/v1/models") {
      return json({ object: "list", data: [{ id: MODEL_ID, object: "model" }] })
    }

    if (url.pathname !== "/v1/chat/completions") return json({ error: "not found" }, 404)

    const body = await req.json().catch(() => ({}) as any)
    const messages: any[] = body?.messages ?? []

    // Text-only: refuse multimodal content parts the way a real text engine does.
    if (persona === "textonly" && hasImagePart(messages)) {
      return json(
        {
          error: {
            message: "this model does not accept image content parts",
            type: "invalid_request_error",
            code: "unsupported_content",
          },
        },
        400,
      )
    }

    if (body?.stream) {
      const includeUsage = body?.stream_options?.include_usage === true
      const deltas: Array<Record<string, unknown>> =
        persona === "vision"
          ? [{ reasoning_content: "Let me count" }, { reasoning_content: " carefully." }, { content: "one" }, { content: " two" }, { content: " three" }]
          : [{ content: "one" }, { content: " two" }, { content: " three" }]
      const enc = new TextEncoder()
      const stream = new ReadableStream({
        async start(controller) {
          for (const d of deltas) {
            if (FRAME_DELAY_MS) await sleep(FRAME_DELAY_MS)
            controller.enqueue(enc.encode(`data: ${JSON.stringify({ choices: [{ delta: d, index: 0, finish_reason: null }] })}\n\n`))
          }
          const last: Record<string, unknown> = { choices: [{ delta: {}, index: 0, finish_reason: "stop" }] }
          if (includeUsage) {
            const usage: Record<string, unknown> = { prompt_tokens: 128, completion_tokens: deltas.length, total_tokens: 128 + deltas.length }
            if (persona === "textonly") usage.prompt_tokens_details = { cached_tokens: messages.length > 2 ? 96 : 0 }
            else usage.completion_tokens_details = { reasoning_tokens: 2 }
            last.usage = usage
          }
          controller.enqueue(enc.encode(`data: ${JSON.stringify(last)}\n\n`))
          controller.enqueue(enc.encode("data: [DONE]\n\n"))
          controller.close()
        },
      })
      return new Response(stream, { headers: { "content-type": "text/event-stream" } })
    }

    const text = JSON.stringify(messages)
    // Prefix reuse only kicks in once a conversation has history to reuse.
    const cached = messages.length > 2 ? 96 : 0

    if (messages.at(-1)?.role === "tool") {
      return json(
        completion({ role: "assistant", content: "It is 11C with drizzle in Berlin." }, cached),
      )
    }

    const tools: any[] = body?.tools ?? []
    const names = new Set(tools.map((t) => t?.function?.name))

    if (names.has("get_weather") && /weather/i.test(text)) {
      return json(
        completion(
          { role: "assistant", content: null, tool_calls: [toolCall("get_weather", { city: "Berlin", unit: "c" })] },
          cached,
        ),
      )
    }

    if (names.has("agent_send")) {
      return json(
        completion(
          {
            role: "assistant",
            content: null,
            tool_calls: [toolCall("agent_send", { session: "build", text: "y", key: "enter" })],
          },
          cached,
        ),
      )
    }

    if (names.has("browser_navigate")) {
      return json(
        completion(
          {
            role: "assistant",
            content: null,
            tool_calls: [
              toolCall("browser_navigate", { url: "https://example.com" }, "call_1"),
              toolCall("browser_type", { selector: "#q", text: "mesh" }, "call_2"),
            ],
          },
          cached,
        ),
      )
    }

    const stops: string[] = body?.stop ?? []
    if (stops.includes("HALT")) return json(completion({ role: "assistant", content: "alpha " }, cached))

    return json(completion({ role: "assistant", content: "ready" }, cached))
  },
})

console.log(`stub endpoint on http://127.0.0.1:${port}/v1  persona=${persona} model=${MODEL_ID}`)

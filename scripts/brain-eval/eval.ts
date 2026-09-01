#!/usr/bin/env bun
/**
 * brain-eval — a capability scorecard for any OpenAI-compatible endpoint.
 *
 * The point is comparability: the SAME probes run against our own inference
 * (MferenceServer) and against LM Studio, so "which brain should this machine
 * use" is answered with numbers instead of vibes. It answers, specifically:
 * can this model call functions, drive a terminal, drive a browser, and read
 * an image — the four things a long-running agent on a Mac actually needs.
 *
 * Nothing here is Mference-specific. It speaks plain Chat Completions.
 *
 *   bun run scripts/brain-eval/eval.ts --endpoint http://127.0.0.1:8080/v1
 *   bun run scripts/brain-eval/eval.ts --endpoint http://127.0.0.1:1234/v1 --json out.json
 *
 * Exit code is 0 whenever the run completed: a model failing a probe is a
 * measurement, not a script error. Use --strict to exit 1 on any failure.
 */

type Status = "pass" | "fail" | "unsupported" | "skip"

interface ProbeResult {
  id: string
  title: string
  capability: string
  status: Status
  detail: string
  ms: number
  meta?: Record<string, unknown>
}

interface Ctx {
  endpoint: string
  model: string
  apiKey?: string
  timeoutMs: number
}

// A 1x1 PNG. Content does not matter — we are probing whether the endpoint
// accepts an image part at all, which is the line between a text-only engine
// and a vision one.
const TINY_PNG =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

function parseArgs(argv: string[]): Record<string, string | boolean> {
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

async function apiFetch(
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

function chatBody(ctx: Ctx, extra: Record<string, unknown>) {
  return JSON.stringify({ model: ctx.model, temperature: 0, max_tokens: 512, ...extra })
}

async function chat(ctx: Ctx, extra: Record<string, unknown>) {
  return apiFetch(ctx, "/chat/completions", { method: "POST", body: chatBody(ctx, extra) })
}

/** Pull tool calls out of a response in the shape every OpenAI-compatible server emits. */
function toolCalls(body: any): Array<{ name: string; args: any; rawArgs: string }> {
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

function content(body: any): string {
  return body?.choices?.[0]?.message?.content ?? ""
}

const WEATHER_TOOL = {
  type: "function",
  function: {
    name: "get_weather",
    description: "Get the current weather for a city.",
    parameters: {
      type: "object",
      properties: {
        city: { type: "string", description: "City name" },
        unit: { type: "string", enum: ["c", "f"] },
      },
      required: ["city"],
    },
  },
}

// Shaped after meshd's real session routes, so a pass here means the model
// could actually drive our daemon.
const TERMINAL_TOOLS = [
  {
    type: "function",
    function: {
      name: "agent_output",
      description: "Read the visible text of a terminal session's pane.",
      parameters: {
        type: "object",
        properties: { session: { type: "string" }, lines: { type: "integer" } },
        required: ["session"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "agent_send",
      description:
        "Send keystrokes to a terminal session. Use text for literal typing, key for a named key.",
      parameters: {
        type: "object",
        properties: {
          session: { type: "string" },
          text: { type: "string" },
          key: {
            type: "string",
            enum: ["enter", "ctrl-c", "ctrl-d", "up", "down", "tab", "escape"],
          },
        },
        required: ["session"],
      },
    },
  },
]

const BROWSER_TOOLS = [
  {
    type: "function",
    function: {
      name: "browser_navigate",
      description: "Navigate the browser to a URL.",
      parameters: {
        type: "object",
        properties: { url: { type: "string" } },
        required: ["url"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "browser_type",
      description: "Type text into an element matched by a CSS selector.",
      parameters: {
        type: "object",
        properties: { selector: { type: "string" }, text: { type: "string" } },
        required: ["selector", "text"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "browser_click",
      description: "Click an element matched by a CSS selector.",
      parameters: {
        type: "object",
        properties: { selector: { type: "string" } },
        required: ["selector"],
      },
    },
  },
]

interface Probe {
  id: string
  title: string
  capability: string
  run(ctx: Ctx): Promise<Omit<ProbeResult, "id" | "title" | "capability" | "ms">>
}

const PROBES: Probe[] = [
  {
    id: "models",
    title: "Endpoint lists a model",
    capability: "reachability",
    async run(ctx) {
      const { status, body } = await apiFetch(ctx, "/models")
      if (status !== 200) return { status: "fail", detail: `GET /models returned ${status}` }
      const ids = (body?.data ?? []).map((m: any) => m.id)
      return {
        status: ids.length ? "pass" : "fail",
        detail: ids.length ? `serving: ${ids.join(", ")}` : "no models listed",
        meta: { models: ids },
      }
    },
  },
  {
    id: "chat-basic",
    title: "Answers a plain prompt",
    capability: "reachability",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [{ role: "user", content: "Reply with exactly the word: ready" }],
        max_tokens: 16,
      })
      if (status !== 200) return { status: "fail", detail: `HTTP ${status}: ${raw.slice(0, 200)}` }
      const text = content(body).trim()
      return {
        status: text.length ? "pass" : "fail",
        detail: text.length ? `answered ${JSON.stringify(text.slice(0, 60))}` : "empty content",
        meta: { usage: body?.usage },
      }
    },
  },
  {
    id: "stream",
    title: "Streams SSE and terminates",
    capability: "reachability",
    async run(ctx) {
      const headers: Record<string, string> = { "content-type": "application/json" }
      if (ctx.apiKey) headers.authorization = `Bearer ${ctx.apiKey}`
      const res = await fetch(`${ctx.endpoint}/chat/completions`, {
        method: "POST",
        headers,
        body: chatBody(ctx, {
          messages: [{ role: "user", content: "Count: one two three." }],
          stream: true,
          max_tokens: 48,
        }),
        signal: AbortSignal.timeout(ctx.timeoutMs),
      })
      if (res.status !== 200) return { status: "fail", detail: `HTTP ${res.status}` }
      const text = await res.text()
      const frames = text.split("\n").filter((l) => l.startsWith("data:")).length
      const done = text.includes("[DONE]")
      return {
        status: frames > 0 && done ? "pass" : "fail",
        detail: `${frames} SSE frames, [DONE]=${done}`,
        meta: { frames, done },
      }
    },
  },
  {
    id: "tools-single",
    title: "Emits one correct function call",
    capability: "function calling",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          { role: "user", content: "What is the weather in Berlin right now? Use the tool." },
        ],
        tools: [WEATHER_TOOL],
      })
      if (status !== 200) return { status: "fail", detail: `HTTP ${status}: ${raw.slice(0, 200)}` }
      const calls = toolCalls(body)
      if (!calls.length)
        return {
          status: "fail",
          detail: `no tool_calls; finish_reason=${body?.choices?.[0]?.finish_reason}`,
        }
      const c = calls[0]
      if (c.name !== "get_weather")
        return { status: "fail", detail: `called unknown tool ${JSON.stringify(c.name)}` }
      if (!c.args || typeof c.args !== "object")
        return { status: "fail", detail: `arguments did not parse as JSON: ${c.rawArgs.slice(0, 120)}` }
      const city = String(c.args.city ?? "")
      const ok = city.toLowerCase().includes("berlin")
      return {
        status: ok ? "pass" : "fail",
        detail: ok ? `get_weather(city=${city})` : `wrong/missing city: ${JSON.stringify(c.args)}`,
        meta: { call: c.name, args: c.args },
      }
    },
  },
  {
    id: "tools-loop",
    title: "Completes a two-turn tool loop",
    capability: "function calling",
    async run(ctx) {
      const first = await chat(ctx, {
        messages: [{ role: "user", content: "What is the weather in Berlin? Use the tool." }],
        tools: [WEATHER_TOOL],
      })
      if (first.status !== 200) return { status: "fail", detail: `first turn HTTP ${first.status}` }
      const msg = first.body?.choices?.[0]?.message
      const calls = first.body?.choices?.[0]?.message?.tool_calls
      if (!Array.isArray(calls) || !calls.length)
        return { status: "skip", detail: "no tool call on turn one; see tools-single" }
      const second = await chat(ctx, {
        messages: [
          { role: "user", content: "What is the weather in Berlin? Use the tool." },
          msg,
          {
            role: "tool",
            tool_call_id: calls[0].id,
            content: JSON.stringify({ city: "Berlin", temp_c: 11, sky: "drizzle" }),
          },
        ],
        tools: [WEATHER_TOOL],
      })
      if (second.status !== 200)
        return { status: "fail", detail: `second turn HTTP ${second.status}: ${second.raw.slice(0, 160)}` }
      const text = content(second.body)
      const usedResult = /11|drizzl/i.test(text)
      return {
        status: usedResult ? "pass" : "fail",
        detail: usedResult
          ? `folded tool result into: ${JSON.stringify(text.slice(0, 80))}`
          : `ignored the tool result: ${JSON.stringify(text.slice(0, 120))}`,
        meta: { answer: text.slice(0, 300) },
      }
    },
  },
  {
    id: "tools-terminal",
    title: "Answers a blocked terminal prompt",
    capability: "terminal actions",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          {
            role: "system",
            content:
              "You operate a Mac through persistent terminal sessions. Act using the tools; do not describe what you would do.",
          },
          {
            role: "user",
            content:
              "Session 'build' is stuck showing:\n\n    Install dependencies? [y/N]\n\nAnswer yes so the build continues.",
          },
        ],
        tools: TERMINAL_TOOLS,
      })
      if (status !== 200) return { status: "fail", detail: `HTTP ${status}: ${raw.slice(0, 200)}` }
      const calls = toolCalls(body)
      if (!calls.length) return { status: "fail", detail: "no tool call; model only talked" }
      const send = calls.find((c) => c.name === "agent_send")
      if (!send)
        return { status: "fail", detail: `expected agent_send, got ${calls.map((c) => c.name).join(",")}` }
      if (!send.args) return { status: "fail", detail: `arguments did not parse: ${send.rawArgs.slice(0, 120)}` }
      const text = String(send.args.text ?? "")
      const key = String(send.args.key ?? "")
      const answeredYes = /^y(es)?$/i.test(text.trim()) || /^y(es)?\s*$/i.test(text)
      const sessionOk = String(send.args.session ?? "") === "build"
      const ok = answeredYes && sessionOk
      return {
        status: ok ? "pass" : "fail",
        detail: ok
          ? `agent_send(session=build, text=${JSON.stringify(text)}${key ? `, key=${key}` : ""})`
          : `wrong args: ${JSON.stringify(send.args)}`,
        meta: { calls: calls.map((c) => ({ name: c.name, args: c.args })) },
      }
    },
  },
  {
    id: "tools-browser",
    title: "Sequences browser actions",
    capability: "browser actions",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          {
            role: "system",
            content: "You control a web browser with the given tools. Take the first action now.",
          },
          {
            role: "user",
            content:
              "Go to https://example.com and type the word mesh into the search box, whose CSS selector is #q.",
          },
        ],
        tools: BROWSER_TOOLS,
      })
      if (status !== 200) return { status: "fail", detail: `HTTP ${status}: ${raw.slice(0, 200)}` }
      const calls = toolCalls(body)
      if (!calls.length) return { status: "fail", detail: "no tool call; model only talked" }
      const names = calls.map((c) => c.name)
      const nav = calls.find((c) => c.name === "browser_navigate")
      const typed = calls.find((c) => c.name === "browser_type")
      // Either it starts with navigate (correct) or it emits the whole plan at once.
      const navOk = nav && String(nav.args?.url ?? "").includes("example.com")
      const typeOk = !typed || (String(typed.args?.selector ?? "") === "#q" && /mesh/i.test(String(typed.args?.text ?? "")))
      const ok = Boolean(navOk) && typeOk
      return {
        status: ok ? "pass" : "fail",
        detail: ok
          ? `sequence: ${names.join(" → ")}`
          : `bad first action: ${JSON.stringify(calls.map((c) => ({ n: c.name, a: c.args })))}`.slice(0, 220),
        meta: { calls: calls.map((c) => ({ name: c.name, args: c.args })) },
      }
    },
  },
  {
    id: "vision",
    title: "Accepts an image in the prompt",
    capability: "reads images",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: "Describe this image in one word." },
              { type: "image_url", image_url: { url: TINY_PNG } },
            ],
          },
        ],
        max_tokens: 32,
      })
      // A text-only engine rejects the multimodal content part outright. That
      // is not a bug in the engine and not a failure of this script — it is
      // the capability boundary we are here to measure.
      if (status === 400 || status === 415 || status === 422)
        return {
          status: "unsupported",
          detail: `endpoint refuses image parts (HTTP ${status}) — text-only model`,
          meta: { httpStatus: status, error: raw.slice(0, 200) },
        }
      if (status !== 200) return { status: "fail", detail: `HTTP ${status}: ${raw.slice(0, 200)}` }
      const text = content(body).trim()
      if (!text)
        return { status: "unsupported", detail: "accepted the image but returned nothing" }
      return {
        status: "pass",
        detail: `answered ${JSON.stringify(text.slice(0, 60))}`,
        meta: { answer: text },
      }
    },
  },
  {
    id: "prompt-cache",
    title: "Reuses a conversation prefix",
    capability: "long-running economics",
    async run(ctx) {
      const base = [
        { role: "system", content: "You are a terse assistant working a long task." },
        { role: "user", content: "Step one: name a primary colour. One word." },
      ]
      const first = await chat(ctx, { messages: base, max_tokens: 16 })
      if (first.status !== 200) return { status: "fail", detail: `first HTTP ${first.status}` }
      const reply = first.body?.choices?.[0]?.message ?? { role: "assistant", content: "red" }
      const second = await chat(ctx, {
        messages: [...base, reply, { role: "user", content: "Step two: name another. One word." }],
        max_tokens: 16,
      })
      if (second.status !== 200) return { status: "fail", detail: `second HTTP ${second.status}` }
      const cached = second.body?.usage?.prompt_tokens_details?.cached_tokens
      if (typeof cached !== "number")
        return {
          status: "unsupported",
          detail: "endpoint does not report cached_tokens (prefix reuse unknown)",
          meta: { usage: second.body?.usage },
        }
      return {
        status: cached > 0 ? "pass" : "fail",
        detail: `cached_tokens=${cached} of prompt_tokens=${second.body?.usage?.prompt_tokens}`,
        meta: { usage: second.body?.usage },
      }
    },
  },
  {
    id: "stop",
    title: "Honours a stop sequence",
    capability: "long-running economics",
    async run(ctx) {
      const { status, body } = await chat(ctx, {
        messages: [
          { role: "user", content: "Write exactly: alpha HALT bravo" },
        ],
        stop: ["HALT"],
        max_tokens: 64,
      })
      if (status !== 200) return { status: "fail", detail: `HTTP ${status}` }
      const text = content(body)
      const leaked = text.includes("bravo")
      return {
        status: leaked ? "fail" : "pass",
        detail: leaked ? `text ran past the stop: ${JSON.stringify(text.slice(0, 80))}` : "stopped at the sequence",
        meta: { text: text.slice(0, 200) },
      }
    },
  },
]

function pad(s: string, n: number) {
  return s.length >= n ? s.slice(0, n) : s + " ".repeat(n - s.length)
}

const MARK: Record<Status, string> = {
  pass: "PASS",
  fail: "FAIL",
  unsupported: "N/A ",
  skip: "SKIP",
}

async function main() {
  const args = parseArgs(Bun.argv.slice(2))
  if (args.help) {
    console.log(
      [
        "brain-eval — capability scorecard for an OpenAI-compatible endpoint",
        "",
        "  --endpoint URL   default http://127.0.0.1:8080/v1 (LM Studio: :1234/v1)",
        "  --model NAME     default: first model the endpoint lists",
        "  --api-key KEY    sent as a bearer token when set",
        "  --timeout MS     per-request timeout, default 120000",
        "  --only IDS       comma-separated probe ids",
        "  --json PATH      write full results as JSON",
        "  --strict         exit 1 if any probe fails",
      ].join("\n"),
    )
    return
  }

  const endpoint = String(args.endpoint ?? "http://127.0.0.1:8080/v1").replace(/\/$/, "")
  const ctx: Ctx = {
    endpoint,
    model: String(args.model ?? ""),
    apiKey: args["api-key"] ? String(args["api-key"]) : undefined,
    timeoutMs: Number(args.timeout ?? 120000),
  }

  // Resolve the model up front so every probe names the same one.
  if (!ctx.model) {
    try {
      const { body } = await apiFetch(ctx, "/models")
      ctx.model = body?.data?.[0]?.id ?? "local-model"
    } catch {
      ctx.model = "local-model"
    }
  }

  const only = args.only ? String(args.only).split(",").map((s) => s.trim()) : null
  const probes = only ? PROBES.filter((p) => only.includes(p.id)) : PROBES

  console.log(`\nbrain-eval → ${endpoint}   model=${ctx.model}\n`)

  const results: ProbeResult[] = []
  for (const probe of probes) {
    const started = Date.now()
    let outcome: Omit<ProbeResult, "id" | "title" | "capability" | "ms">
    try {
      outcome = await probe.run(ctx)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      outcome = { status: "fail", detail: `threw: ${msg}` }
    }
    const result: ProbeResult = {
      id: probe.id,
      title: probe.title,
      capability: probe.capability,
      ms: Date.now() - started,
      ...outcome,
    }
    results.push(result)
    console.log(
      `  ${MARK[result.status]}  ${pad(result.title, 34)} ${pad(`${result.ms}ms`, 9)} ${result.detail}`,
    )
  }

  // Roll the probes up into the four questions that decide whether this brain
  // can run a long task on a Mac.
  const caps = new Map<string, Status[]>()
  for (const r of results) {
    if (!caps.has(r.capability)) caps.set(r.capability, [])
    caps.get(r.capability)!.push(r.status)
  }
  console.log("\n  capability summary")
  const summary: Record<string, string> = {}
  for (const [cap, statuses] of caps) {
    let verdict: string
    if (statuses.every((s) => s === "unsupported")) verdict = "UNSUPPORTED"
    else if (statuses.some((s) => s === "fail")) verdict = "PARTIAL/FAILING"
    else if (statuses.every((s) => s === "pass")) verdict = "OK"
    else verdict = "PARTIAL"
    summary[cap] = verdict
    console.log(`    ${pad(cap, 24)} ${verdict}`)
  }

  const failed = results.filter((r) => r.status === "fail").length
  console.log(
    `\n  ${results.filter((r) => r.status === "pass").length} pass · ${failed} fail · ` +
      `${results.filter((r) => r.status === "unsupported").length} unsupported · ` +
      `${results.filter((r) => r.status === "skip").length} skip\n`,
  )

  if (args.json) {
    const payload = {
      endpoint,
      model: ctx.model,
      recordedAt: new Date().toISOString(),
      summary,
      results,
    }
    await Bun.write(String(args.json), JSON.stringify(payload, null, 2) + "\n")
    console.log(`  wrote ${args.json}\n`)
  }

  if (args.strict && failed > 0) process.exit(1)
}

main()

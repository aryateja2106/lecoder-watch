#!/usr/bin/env bun
// A scripted stand-in for a local model, used to exercise the mesh-code agent loop
// end to end without a GPU. It plays a fixed sequence of tool calls, INCLUDING the
// failure modes a small model actually produces — malformed JSON arguments, an invented
// tool name, and a command repeated after it fails — so the loop's guardrails are
// exercised rather than assumed.
//
//   bun run scripts/brain-eval/scripted-model.ts --port 8097

const portArg = Bun.argv.indexOf("--port")
const port = portArg >= 0 ? Number(Bun.argv[portArg + 1]) : 8097

function call(id: string, name: string, args: unknown) {
  return {
    id,
    type: "function",
    function: { name, arguments: typeof args === "string" ? args : JSON.stringify(args) },
  }
}

// One entry per assistant turn.
const SCRIPT: Array<{ text: string | null; calls: any[] }> = [
  { text: "Setting up.", calls: [call("c1", "run_command", { command: "mkdir -p /tmp/mc-demo && echo ready" })] },
  {
    text: null,
    calls: [
      call("c2", "write_file", {
        path: "/tmp/mc-demo/app.js",
        content: "const n = process.argv[2] ?? '3';\nconsole.log('sum', Number(n) + 39);\n",
      }),
    ],
  },
  { text: null, calls: [call("c3", "run_command", { command: "node /tmp/mc-demo/app.js 3" })] },
  // malformed arguments: not valid JSON at all
  { text: null, calls: [call("c4", "run_command", "{command: 'oops' this is not json")] },
  // a tool that does not exist
  { text: null, calls: [call("c5", "teleport", { destination: "mars" })] },
  // the same failing command, twice, to trip the repeat guard
  { text: null, calls: [call("c6", "run_command", { command: "false" })] },
  { text: null, calls: [call("c7", "run_command", { command: "false" })] },
  { text: null, calls: [call("c8", "run_command", { command: "false" })] },
  { text: null, calls: [call("c9", "read_file", { path: "/tmp/mc-demo/app.js" })] },
  { text: null, calls: [call("c10", "finish", { summary: "Wrote app.js and verified it prints sum 42." })] },
]

Bun.serve({
  port,
  async fetch(req) {
    const url = new URL(req.url)
    if (url.pathname === "/v1/models")
      return Response.json({ object: "list", data: [{ id: "scripted-qwen36", object: "model" }] })
    if (url.pathname !== "/v1/chat/completions") return Response.json({ error: "not found" }, { status: 404 })

    const body: any = await req.json().catch(() => ({}))
    const messages: any[] = body?.messages ?? []
    // Stateless: the step is how many assistant turns have already happened.
    const step = messages.filter((m) => m.role === "assistant").length
    const entry = SCRIPT[step] ?? { text: "Nothing left to do.", calls: [] }

    return Response.json({
      id: "chatcmpl-scripted",
      object: "chat.completion",
      model: "scripted-qwen36",
      choices: [
        {
          index: 0,
          message: { role: "assistant", content: entry.text, ...(entry.calls.length ? { tool_calls: entry.calls } : {}) },
          finish_reason: entry.calls.length ? "tool_calls" : "stop",
        },
      ],
      usage: {
        prompt_tokens: 100 + step * 40,
        completion_tokens: 20,
        total_tokens: 120 + step * 40,
        // Prefix reuse grows as the append-only history grows — what makes long runs cheap.
        prompt_tokens_details: { cached_tokens: step === 0 ? 0 : 100 + (step - 1) * 40 },
      },
    })
  },
})
console.log(`scripted model on http://127.0.0.1:${port}/v1`)

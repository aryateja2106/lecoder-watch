/**
 * Use-case probes: one decision each, on a fixed history, using the tools the agent
 * actually gives the model in production. Every probe targets a specific, common
 * small-model failure and reports it as a tag — the tags, not the pass counts, say
 * which dataset to build.
 *
 * Fixtures are shaped byte-for-byte like the tool results install/payload/agent/tools.ts
 * emits (5-wide gutter on read_file, "exit code N\n\n…" on run_command, the digest note
 * from mobile.ts), because a model that can act on a stand-in but not on the real shape
 * has not been measured.
 *
 * Nothing here needs a Mac. Nothing here has been run against one either — the first
 * real run should be diffed against the stub expectations before any number is quoted.
 */
import { TOOLS, TOOL_NAMES } from "../../install/payload/agent/tools.ts"
import { asStr, chat, content, toolCalls, unparsedToolCallText, type FailureMode, type Outcome, type Probe } from "./core.ts"

// One system prompt for every mesh-code-shaped probe: a stable prefix is what the
// single-prefix cache on our own engine can reuse. 49 words.
export const MESH_CODE_SYSTEM =
  "You are mesh-code, a coding agent on a Mac. Working directory: /Users/arya/proj. Act only through tools; never describe what you would do. run_command takes a single line. Read before you edit. If a command fails, change approach instead of repeating it. Call finish when the task is done."

// The un-numbered file behind cli-unique-anchor; the edit is simulated against it.
export const UTIL_TS = [
  "export async function fetchUser(id: string) {",
  "  return request(`/users/${id}`, { timeout: 3000 });",
  "}",
  "",
  "export async function fetchOrder(id: string) {",
  "  return request(`/orders/${id}`, { timeout: 3000 });",
  "}",
].join("\n")

/** Exactly what tools.ts read_file returns: 5-wide right-aligned gutter, two spaces. */
export function numbered(text: string): string {
  return text
    .split("\n")
    .map((l, i) => `${String(i + 1).padStart(5)}  ${l}`)
    .join("\n")
}

export const SIMCTL_LIST = [
  "exit code 0",
  "",
  "== Devices ==",
  "-- iOS 18.4 --",
  "    iPhone 16 (A1B2C3D4-0000-4000-8000-000000000016) (Shutdown)",
  "    iPhone 16 Plus (A1B2C3D4-0000-4000-8000-000000000018) (Shutdown)",
  "    iPhone 16 Pro (A1B2C3D4-0000-4000-8000-000000000017) (Booted)",
  "    iPad Air 11-inch (M3) (A1B2C3D4-0000-4000-8000-000000000021) (Shutdown)",
].join("\n")
const LISTED_UDIDS = new Set([
  "A1B2C3D4-0000-4000-8000-000000000016",
  "A1B2C3D4-0000-4000-8000-000000000018",
  "A1B2C3D4-0000-4000-8000-000000000017",
  "A1B2C3D4-0000-4000-8000-000000000021",
])

export const XCODE_DIGEST = [
  "exit code 65",
  "",
  "[xcodebuild log digested (48213 -> 171 chars)]",
  "",
  "1 failed, 11 passed",
  "",
  "FAIL LoginTests.testSignInDisabledWhenEmpty",
  "  /Users/arya/proj/NotesTests/LoginTests.swift:42",
  "  XCTAssertFalse failed - sign-in button enabled with empty email",
].join("\n")

export const PAGE_SNAPSHOT = [
  "page: Mesh — Sign in",
  "form#signin",
  '  input#email-address [type=email] placeholder "Email"',
  '  input#passcode [type=password] placeholder "Password"',
  '  input#remember [type=checkbox] "Remember me"',
  '  button.btn-primary [type=submit] "Sign in"',
  'a.forgot "Forgot your password?"',
].join("\n")

export const APPS_LIST = "frontmost: Safari\nrunning: Finder, Safari, Notes, Terminal, LM Studio"

const tool = (name: string, description: string, properties: Record<string, unknown>, required: string[] = []) => ({
  type: "function" as const,
  function: { name, description, parameters: { type: "object", properties, required } },
})

// Byte-identical to what tools-terminal and tools-browser have always sent — shaped
// after meshd's real session routes, so a pass means the model could drive the daemon,
// and shared so the observe-before-send probe reuses tools-terminal's cached prefix.
export const TERMINAL_TOOLS = [
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

export const BROWSER_TOOLS = [
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
export const BROWSER_TOOLS_WITH_SNAPSHOT = [
  tool("browser_snapshot", "Return an outline of the interactive elements on the current page with their CSS selectors.", {}),
  ...BROWSER_TOOLS,
]

export const MACOS_TOOLS = [
  tool("apps_list", "List running apps and which one is frontmost.", {}),
  tool("app_activate", "Bring an app to the front by name.", { name: { type: "string" } }, ["name"]),
  tool("input_key", "Press one key with optional modifiers.", { key: { type: "string" }, modifiers: { type: "array", items: { type: "string", enum: ["cmd", "shift", "alt", "ctrl"] } } }, ["key"]),
  tool("input_type", "Type literal text into the frontmost app.", { text: { type: "string" } }, ["text"]),
]

const fail = (failureMode: FailureMode, detail: string, meta?: Record<string, unknown>): Outcome => ({ status: "fail", detail, failureMode, meta })
const pass = (detail: string, meta?: Record<string, unknown>): Outcome => ({ status: "pass", detail, failureMode: null, meta })

type Call = { name: string; args: any; rawArgs: string }

/** The checks every tool-using probe shares. Returns the calls, or the failure. */
function structural(status: number, body: any, raw: string, allowed: Set<string>): { calls: Call[] } | { out: Outcome } {
  if (status !== 200) return { out: fail("http-error", `HTTP ${status}: ${raw.slice(0, 200)}`) }
  const calls = toolCalls(body)
  if (!calls.length) {
    if (unparsedToolCallText(body))
      return { out: fail("unparsed-tool-call", "model emitted <tool_call> XML the server did not parse", { text: content(body).slice(0, 300) }) }
    return { out: fail("prose-only", `no tool call; model only talked: ${JSON.stringify(content(body).slice(0, 120))}`) }
  }
  const unknown = calls.find((c) => !allowed.has(c.name))
  if (unknown) return { out: fail("unknown-tool", `invented tool ${JSON.stringify(unknown.name)}`, { calls: brief(calls) }) }
  const bad = calls.find((c) => c.args === null || typeof c.args !== "object")
  if (bad) return { out: fail("malformed-arguments", `arguments did not parse for ${bad.name}: ${bad.rawArgs.slice(0, 120)}`) }
  return { calls }
}

const brief = (calls: Call[]) => calls.map((c) => ({ name: c.name, args: c.args }))
const cmd = (c: Call) => asStr(c.args?.command)
const multiLine = (c: Call) => /\n/.test(cmd(c))
const heredoc = (c: Call) => /<</.test(cmd(c))

const MESH_NAMES = new Set(TOOL_NAMES)
const BROWSER_NAMES = new Set(BROWSER_TOOLS_WITH_SNAPSHOT.map((t) => t.function.name))
const TERMINAL_NAMES = new Set(TERMINAL_TOOLS.map((t) => t.function.name))
const MACOS_NAMES = new Set(MACOS_TOOLS.map((t) => t.function.name))

const sys = (text: string) => ({ role: "system", content: text })
const user = (text: string) => ({ role: "user", content: text })
const assistantCall = (id: string, name: string, args: Record<string, unknown>) => ({
  role: "assistant",
  content: null,
  tool_calls: [{ id, type: "function", function: { name, arguments: JSON.stringify(args) } }],
})
const toolResult = (id: string, text: string) => ({ role: "tool", tool_call_id: id, content: text })

/** Shared gate for mesh-code probes: first call must not be finish/escalate; run_command must be one line. */
function meshGate(calls: Call[]): Outcome | null {
  if (calls[0].name === "finish") return fail("premature-finish", `finish before doing anything: ${JSON.stringify(calls[0].args)}`, { calls: brief(calls) })
  if (calls[0].name === "escalate") return fail("eager-escalate", `escalated on the first move: ${JSON.stringify(calls[0].args?.reason ?? "")}`, { calls: brief(calls) })
  for (const c of calls) {
    if (c.name !== "run_command") continue
    if (heredoc(c)) return fail("heredoc", `run_command with a heredoc: ${JSON.stringify(cmd(c).slice(0, 120))}`, { calls: brief(calls) })
    if (multiLine(c)) return fail("multi-line-command", `run_command with a newline: ${JSON.stringify(cmd(c).slice(0, 120))}`, { calls: brief(calls) })
  }
  return null
}

export const AGENT_PROBES: Probe[] = [
  {
    id: "cli-single-line",
    title: "Writes a script without a multi-line command",
    capability: "cli agent",
    useCase: "CLI",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [sys(MESH_CODE_SYSTEM), user("Create scripts/hi.sh with exactly these two lines:\n#!/bin/sh\necho hi\nThen make it executable.")],
        tools: TOOLS,
      })
      const s = structural(status, body, raw, MESH_NAMES)
      if ("out" in s) return s.out
      const g = meshGate(s.calls)
      if (g) return g
      const wrote = s.calls.find((c) => c.name === "write_file" && /scripts\/hi\.sh$/.test(asStr(c.args.path)) && /echo hi/.test(asStr(c.args.content)))
      const touched = s.calls.find((c) => c.name === "run_command" && /hi\.sh/.test(cmd(c)))
      if (!wrote && !touched) return fail("wrong-target", `nothing touched scripts/hi.sh`, { calls: brief(s.calls) })
      return pass(`${s.calls.map((c) => c.name).join(" → ")}`, { calls: brief(s.calls) })
    },
  },
  {
    id: "cli-observe-before-edit",
    title: "Lists before editing an unnamed file",
    capability: "cli agent",
    useCase: "CLI",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [sys(MESH_CODE_SYSTEM), user("The app's config file has the wrong greeting. Change the greeting to hello.")],
        tools: TOOLS,
      })
      const s = structural(status, body, raw, MESH_NAMES)
      if ("out" in s) return s.out
      const g = meshGate(s.calls)
      if (g) return g
      const first = s.calls[0]
      const observes =
        first.name === "list_dir" || (first.name === "run_command" && /^(ls|find|fd|grep|rg|tree)\b/.test(cmd(first).trim()))
      if (!observes) return fail("hallucinated-path", `acted on a path it never listed: ${first.name}(${JSON.stringify(first.args).slice(0, 100)})`, { calls: brief(s.calls) })
      return pass(`looked first: ${first.name}(${JSON.stringify(first.args)})`, { calls: brief(s.calls) })
    },
  },
  {
    id: "cli-unique-anchor",
    title: "str_replace with a unique find string",
    capability: "cli agent",
    useCase: "CLI",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          sys(MESH_CODE_SYSTEM),
          user("In src/util.ts, change the timeout of fetchUser from 3000 to 5000. fetchOrder must stay at 3000."),
          assistantCall("call_r1", "read_file", { path: "src/util.ts" }),
          toolResult("call_r1", numbered(UTIL_TS)),
        ],
        tools: TOOLS,
      })
      const s = structural(status, body, raw, MESH_NAMES)
      if ("out" in s) return s.out
      const g = meshGate(s.calls)
      if (g) return g
      if (s.calls.some((c) => c.name === "read_file")) return fail("redundant-action", "read the file again instead of editing", { calls: brief(s.calls) })
      const edits = s.calls.filter((c) => c.name === "str_replace" || c.name === "write_file")
      if (!edits.length) return fail("wrong-target", `no edit: ${s.calls.map((c) => c.name).join(",")}`, { calls: brief(s.calls) })
      const e = edits[0]
      const want = "/users/${id}`, { timeout: 5000 }"
      const keep = "/orders/${id}`, { timeout: 3000 }"
      if (e.name === "str_replace") {
        const find = asStr(e.args.find)
        const hits = find.length ? UTIL_TS.split(find).length - 1 : 0
        if (hits === 0) return fail("find-not-found", `find matches nothing (gutter copied?): ${JSON.stringify(find.slice(0, 80))}`, { calls: brief(s.calls) })
        if (hits > 1) return fail("non-unique-find", `find matches ${hits} places; production refuses it: ${JSON.stringify(find.slice(0, 80))}`, { calls: brief(s.calls) })
        const after = UTIL_TS.split(find).join(asStr(e.args.replace))
        if (!after.includes(want) || !after.includes(keep)) return fail("wrong-target", `edit changed the wrong call`, { calls: brief(s.calls), after })
        return pass(`unique anchor, fetchUser → 5000, fetchOrder kept`, { calls: brief(s.calls) })
      }
      const c = asStr(e.args.content)
      if (!c.includes(want) || !c.includes(keep) || c.split("3000").length - 1 !== 1) return fail("wrong-target", `rewrite lost or changed a line`, { calls: brief(s.calls) })
      return pass(`full rewrite, both calls correct`, { calls: brief(s.calls) })
    },
  },
  {
    id: "cli-error-recovery",
    title: "Changes approach after exit code 127",
    capability: "cli agent",
    useCase: "CLI",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          sys(MESH_CODE_SYSTEM),
          user("Run the test suite and tell me whether it passes."),
          assistantCall("call_c1", "run_command", { command: "npm test" }),
          toolResult("call_c1", "exit code 127\n\nsh: npm: command not found"),
        ],
        tools: TOOLS,
      })
      const s = structural(status, body, raw, MESH_NAMES)
      if ("out" in s) return s.out
      const first = s.calls[0]
      if (first.name === "finish") return fail("premature-finish", `finish after a failed command: ${JSON.stringify(first.args?.summary ?? "").slice(0, 100)}`, { calls: brief(s.calls) })
      if (first.name === "escalate") return fail("eager-escalate", `escalated after one failure`, { calls: brief(s.calls) })
      const g = meshGate(s.calls)
      if (g) return g
      if (first.name === "run_command") {
        const c = cmd(first).replace(/\s+/g, " ").trim()
        if (c === "npm test" || /^npm\s+(run\s+)?test\b/.test(c)) return fail("repeated-failing-command", `re-ran the failing command: ${JSON.stringify(c)}`, { calls: brief(s.calls) })
        return pass(`changed approach: ${JSON.stringify(c)}`, { calls: brief(s.calls) })
      }
      if (first.name === "list_dir" || first.name === "read_file") return pass(`investigated: ${first.name}(${JSON.stringify(first.args)})`, { calls: brief(s.calls) })
      return fail("other", `unexpected first move ${first.name}`, { calls: brief(s.calls) })
    },
  },
  {
    id: "cli-finish-when-done",
    title: "Calls finish after the task completed",
    capability: "cli agent",
    useCase: "CLI",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          sys(MESH_CODE_SYSTEM),
          user("Create an empty file named TODO.md."),
          assistantCall("call_w1", "write_file", { path: "TODO.md", content: "" }),
          toolResult("call_w1", "wrote /Users/arya/proj/TODO.md (0 characters, 1 lines)"),
        ],
        tools: TOOLS,
      })
      if (status !== 200) return fail("http-error", `HTTP ${status}: ${raw.slice(0, 200)}`)
      const calls = toolCalls(body)
      if (!calls.length) {
        if (unparsedToolCallText(body)) return fail("unparsed-tool-call", "model emitted <tool_call> XML the server did not parse")
        return fail("no-finish", `narrated completion instead of calling finish: ${JSON.stringify(content(body).slice(0, 100))}`)
      }
      const unknown = calls.find((c) => !MESH_NAMES.has(c.name))
      if (unknown) return fail("unknown-tool", `invented tool ${JSON.stringify(unknown.name)}`, { calls: brief(calls) })
      if (calls.some((c) => c.name === "write_file" || c.name === "str_replace")) return fail("redundant-action", `edited again after success`, { calls: brief(calls) })
      const fin = calls.find((c) => c.name === "finish")
      if (!fin) return fail("no-finish", `did something else instead of finish: ${calls.map((c) => c.name).join(",")}`, { calls: brief(calls) })
      if (!asStr(fin.args?.summary).trim()) return fail("malformed-arguments", `finish without a summary`, { calls: brief(calls) })
      const stray = calls.filter((c) => c.name !== "finish" && !(c.name === "list_dir" || (c.name === "run_command" && /^(ls|stat|test -f|cat|wc)\b/.test(cmd(c).trim()))))
      if (stray.length) return fail("redundant-action", `non-verification call alongside finish: ${stray.map((c) => c.name).join(",")}`, { calls: brief(calls) })
      return pass(`finish(${JSON.stringify(asStr(fin.args.summary).slice(0, 60))})`, { calls: brief(calls) })
    },
  },
  {
    id: "browser-selectors-from-snapshot",
    title: "Uses only selectors present in the page outline",
    capability: "browser actions",
    useCase: "browser",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          sys("You control a web browser through the tools. Use only selectors that appear in the page outline. Take the next action now."),
          user("Sign in with email dev@mesh.test and password hunter2. The page is already open."),
          assistantCall("call_s1", "browser_snapshot", {}),
          toolResult("call_s1", PAGE_SNAPSHOT),
        ],
        tools: BROWSER_TOOLS_WITH_SNAPSHOT,
      })
      const s = structural(status, body, raw, BROWSER_NAMES)
      if ("out" in s) return s.out
      const calls = s.calls
      if (calls[0].name === "browser_navigate") return fail("needless-navigate", `navigated although the page is open`, { calls: brief(calls) })
      const known = new Set(["email-address", "passcode", "remember", "signin"])
      for (const c of calls) {
        if (c.name !== "browser_type" && c.name !== "browser_click") continue
        const sel = asStr(c.args.selector)
        const ids = [...sel.matchAll(/#([\w-]+)/g)].map((m) => m[1])
        const foreign = ids.find((id) => !known.has(id))
        if (foreign) return fail("guessed-selector", `#${foreign} is not in the outline`, { calls: brief(calls) })
        const grounded = ids.length > 0 || /\.btn-primary|button\[type=submit\]|\.forgot/.test(sel)
        if (!grounded) return fail("guessed-selector", `selector not from the outline: ${JSON.stringify(sel)}`, { calls: brief(calls) })
      }
      const typed = calls.filter((c) => c.name === "browser_type")
      const email = typed.find((c) => /email-address/.test(asStr(c.args.selector)))
      if (!email) return fail("wrong-target", `never typed into #email-address`, { calls: brief(calls) })
      if (asStr(email.args.text) !== "dev@mesh.test") return fail("wrong-value", `typed ${JSON.stringify(asStr(email.args.text))} into the email field`, { calls: brief(calls) })
      const pw = typed.find((c) => /passcode/.test(asStr(c.args.selector)))
      if (pw && asStr(pw.args.text) !== "hunter2") return fail("wrong-value", `typed ${JSON.stringify(asStr(pw.args.text))} into the password field`, { calls: brief(calls) })
      const clickIdx = calls.findIndex((c) => c.name === "browser_click")
      if (clickIdx >= 0) {
        const sel = asStr(calls[clickIdx].args.selector)
        if (!/btn-primary|button\[type=submit\]|#signin/.test(sel)) return fail("wrong-target", `clicked ${JSON.stringify(sel)}`, { calls: brief(calls) })
        const lastType = Math.max(...calls.map((c, i) => (c.name === "browser_type" ? i : -1)))
        if (clickIdx < lastType) return fail("wrong-target", `clicked submit before finishing typing`, { calls: brief(calls) })
      }
      return pass(`${calls.map((c) => `${c.name}(${asStr(c.args.selector)})`).join(" → ")}`, { calls: brief(calls) })
    },
  },
  {
    id: "terminal-observe-before-send",
    title: "Reads the pane before typing into it",
    capability: "terminal actions",
    useCase: "macOS",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          sys("You operate a Mac through persistent terminal sessions. Act using the tools; do not describe what you would do."),
          user("Session 'deploy' went quiet ten minutes ago. If it is waiting on a yes/no question, answer yes; otherwise leave it alone."),
        ],
        tools: TERMINAL_TOOLS,
      })
      const s = structural(status, body, raw, TERMINAL_NAMES)
      if ("out" in s) return s.out
      const calls = s.calls
      if (calls.some((c) => c.name === "agent_send")) return fail("blind-send", `sent keystrokes without reading the pane: ${JSON.stringify(calls.find((c) => c.name === "agent_send")?.args)}`, { calls: brief(calls) })
      const look = calls[0]
      if (look.name !== "agent_output") return fail("other", `first call ${look.name}`, { calls: brief(calls) })
      if (asStr(look.args.session) !== "deploy") return fail("wrong-session", `read session ${JSON.stringify(asStr(look.args.session))}`, { calls: brief(calls) })
      return pass(`agent_output(session=deploy) before anything else`, { calls: brief(calls) })
    },
  },
  {
    id: "ios-sim-boot-udid",
    title: "Boots the right simulator by listed UDID",
    capability: "ios simulator",
    useCase: "iOS simulator",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          sys(MESH_CODE_SYSTEM),
          user("Boot the iPhone 16 simulator (not the Pro or Plus) and launch com.mesh.notes on it."),
          assistantCall("call_l1", "run_command", { command: "xcrun simctl list devices available" }),
          toolResult("call_l1", SIMCTL_LIST),
        ],
        tools: TOOLS,
      })
      const s = structural(status, body, raw, MESH_NAMES)
      if ("out" in s) return s.out
      const g = meshGate(s.calls)
      if (g) return g
      const first = s.calls[0]
      if (first.name !== "run_command") return fail("other", `first call ${first.name}`, { calls: brief(s.calls) })
      const c = cmd(first)
      if (/simctl list/.test(c)) return fail("repeated-failing-command", `listed devices again`, { calls: brief(s.calls) })
      const uuids = [...c.matchAll(/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/gi)].map((m) => m[0].toUpperCase())
      const bogus = uuids.find((u) => !LISTED_UDIDS.has(u))
      if (bogus) return fail("hallucinated-udid", `UDID not in the listing: ${bogus}`, { calls: brief(s.calls) })
      if (/\bbooted\b/.test(c)) return fail("wrong-target", `used the 'booted' alias — that is the Pro`, { calls: brief(s.calls) })
      const target = /xcrun simctl boot\s+(A1B2C3D4-0000-4000-8000-000000000016|"iPhone 16"|'iPhone 16')(?=\s|$|;|&)/.test(c)
      if (!target) return fail("wrong-target", `did not boot the iPhone 16: ${JSON.stringify(c.slice(0, 120))}`, { calls: brief(s.calls) })
      if (/simctl launch/.test(c) && !(/launch\s+(A1B2C3D4-0000-4000-8000-000000000016|"iPhone 16"|'iPhone 16')\s+com\.mesh\.notes/.test(c)))
        return fail("wrong-target", `launch targets the wrong device or bundle`, { calls: brief(s.calls) })
      return pass(JSON.stringify(c), { calls: brief(s.calls) })
    },
  },
  {
    id: "ios-test-digest-read",
    title: "Reads the file named in the test digest",
    capability: "ios simulator",
    useCase: "iOS simulator",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          sys(MESH_CODE_SYSTEM),
          user("Run the unit tests for the Notes scheme and fix the failing test."),
          assistantCall("call_x1", "run_command", { command: "xcodebuild test -scheme Notes -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -200" }),
          toolResult("call_x1", XCODE_DIGEST),
        ],
        tools: TOOLS,
      })
      const s = structural(status, body, raw, MESH_NAMES)
      if ("out" in s) return s.out
      const g = meshGate(s.calls)
      if (g) return g
      const first = s.calls[0]
      const path = "NotesTests/LoginTests.swift"
      if (first.name === "str_replace" || first.name === "write_file") {
        const p = asStr(first.args.path)
        return p.endsWith(path)
          ? fail("edit-before-read", `edited ${p} without reading it`, { calls: brief(s.calls) })
          : fail("hallucinated-path", `edited ${p}, which the digest never named`, { calls: brief(s.calls) })
      }
      if (first.name === "read_file") {
        const p = asStr(first.args.path)
        if (p === `/Users/arya/proj/${path}` || p === path) return pass(`read_file(${p})`, { calls: brief(s.calls) })
        return fail("hallucinated-path", `read ${p}, which the digest never named`, { calls: brief(s.calls) })
      }
      if (first.name === "run_command") {
        const c = cmd(first)
        if (/xcodebuild/.test(c)) return fail("repeated-failing-command", `re-ran xcodebuild`, { calls: brief(s.calls) })
        if (/^(sed -n|cat|head|grep|rg)\b/.test(c.trim()) && /NotesTests\/LoginTests\.swift/.test(c)) return pass(JSON.stringify(c), { calls: brief(s.calls) })
        return fail("hallucinated-path", `command does not look at the named file: ${JSON.stringify(c.slice(0, 100))}`, { calls: brief(s.calls) })
      }
      return fail("other", `first call ${first.name}`, { calls: brief(s.calls) })
    },
  },
  {
    id: "macos-activate-before-type",
    title: "Activates Notes before typing",
    capability: "macos control",
    useCase: "macOS",
    async run(ctx) {
      const { status, body, raw } = await chat(ctx, {
        messages: [
          sys("You control a Mac through the given tools. Typing goes to the frontmost app. Take the next action now."),
          user("Make a new note in Notes containing the text: buy milk"),
          assistantCall("call_a1", "apps_list", {}),
          toolResult("call_a1", APPS_LIST),
        ],
        tools: MACOS_TOOLS,
      })
      const s = structural(status, body, raw, MACOS_NAMES)
      if ("out" in s) return s.out
      const calls = s.calls
      const actIdx = calls.findIndex((c) => c.name === "app_activate")
      const typeIdx = calls.findIndex((c) => c.name === "input_type")
      if (typeIdx >= 0 && (actIdx < 0 || typeIdx < actIdx)) return fail("typed-into-wrong-app", `typed before activating Notes — keystrokes would land in Safari`, { calls: brief(calls) })
      if (calls[0].name !== "app_activate") return fail("other", `first call ${calls[0].name}`, { calls: brief(calls) })
      if (!/^notes(\.app)?$/i.test(asStr(calls[0].args.name))) return fail("wrong-target", `activated ${JSON.stringify(asStr(calls[0].args.name))}`, { calls: brief(calls) })
      for (const c of calls) {
        if (c.name === "input_type") {
          const t = asStr(c.args.text)
          if (/cmd|command|⌘/i.test(t)) return fail("shortcut-as-text", `typed a shortcut as literal text: ${JSON.stringify(t)}`, { calls: brief(calls) })
          if (t !== "buy milk") return fail("wrong-value", `typed ${JSON.stringify(t)}`, { calls: brief(calls) })
        }
        if (c.name === "input_key") {
          if (!Array.isArray(c.args.modifiers ?? [])) return fail("malformed-arguments", `modifiers is not an array: ${JSON.stringify(c.args.modifiers)}`, { calls: brief(calls) })
          const k = asStr(c.args.key)
          const mods: string[] = (c.args.modifiers ?? []).map((m: unknown) => asStr(m).toLowerCase())
          const ok = (/^n$/i.test(k) && mods.includes("cmd")) || /^(enter|return)$/i.test(k)
          if (!ok) return fail("wrong-value", `unexpected key ${JSON.stringify(k)} mods=${JSON.stringify(mods)}`, { calls: brief(calls) })
        }
      }
      return pass(`${calls.map((c) => c.name).join(" → ")}`, { calls: brief(calls) })
    },
  },
]

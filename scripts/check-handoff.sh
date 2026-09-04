#!/bin/sh
# handoff.ts self-check: HANDOFF.md carries the last assistant message, the recent turns
# and the tool activity; each target CLI gets the right launch line (OMP imports a Claude
# transcript directly); the resumable list reads Claude, Codex and cursor-agent conversation
# stores for a directory with the exact command that reopens each; the hand-off itself
# respawns the pane that runs the agent (never the shell pane beside it) with the new
# CLI's absolute path, resuming that CLI's own recent conversation in the directory when
# it has one; falls back to interrupt, interrupt, launch line, Enter on panes it cannot
# respawn; and refuses unknown or uninstalled agents before touching anything.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-handoff: SKIP (bun not installed)"; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Fixture conversation stores, one per CLI, for cwd /work/app
mkdir -p "$TMP/claude/-work-app" "$TMP/codex/2026/09/04" "$TMP/cursor/work-app/agent-transcripts/chat-1"
printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Build a habit tracker with streaks"}]},"timestamp":"2026-09-04T10:00:00Z"}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it."}]},"timestamp":"2026-09-04T10:00:05Z"}' >"$TMP/claude/-work-app/aaaa-1111.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<system-reminder>ignored</system-reminder>"}]}}' \
  '{"type":"user","message":{"role":"user","content":"Fix the crash on launch"}}' >"$TMP/claude/-work-app/bbbb-2222.jsonl"
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"subagent noise"}]}}' >"$TMP/claude/-work-app/agent-zzzz.jsonl"
printf '%s\n' '{"type":"session_meta","payload":{"id":"codex-thread-9","cwd":"/work/app"}}' \
  '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Write the README"}]}}' >"$TMP/codex/2026/09/04/rollout-x.jsonl"
printf '%s\n' '{"type":"session_meta","payload":{"id":"codex-other","cwd":"/elsewhere"}}' >"$TMP/codex/2026/09/04/rollout-y.jsonl"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"text","text":"Add dark mode"}]}}' >"$TMP/cursor/work-app/agent-transcripts/chat-1/chat-1.jsonl"
# A Claude conversation for the hand-off's own working directory (slug: "/" and "." → "-"),
# fresh enough to be resumed by a hand-off TO claude.
WSLUG="$(printf '%s' "$TMP/work" | sed 's#[/.]#-#g')"
mkdir -p "$TMP/claude/$WSLUG" "$TMP/work"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"Keep going on the widgets"}}' >"$TMP/claude/$WSLUG/cccc-3333.jsonl"
cat >"$TMP/check.ts" <<'EOF'
const { handoffMarkdown, launchCommand, listResumable, handoff, handleHandoff, pickPane, resumeFor, HANDOFF_TARGETS } = await import(`${process.env.MESH_ROOT}/install/payload/meshd/handoff.ts`);
let failed = 0;
const expect = (name: string, ok: boolean, detail = "") => { if (!ok) { failed++; console.log("FAIL " + name + (detail ? "  " + detail : "")); } };

// 1. the markdown
const page = { name: "s", source: "claude", cursor: "", messages: [
  { id: "1", ts: "", role: "user", text: "Build a habit tracker" },
  { id: "2", ts: "", role: "thinking", text: "private" },
  { id: "3", ts: "", role: "tool", text: "Bash", tool: { name: "Bash", input: "xcodegen generate" }, status: "ok" },
  { id: "4", ts: "", role: "result", text: "ok" },
  { id: "5", ts: "", role: "assistant", text: "Built it. Tests 7/7." },
]};
const md = handoffMarkdown("s", page as any, new Date("2026-09-04T00:00:00Z"));
expect("title names the session", md.startsWith("# Hand-off from session `s`"));
expect("where it stopped = last assistant", md.includes("## Where it stopped\n\nBuilt it. Tests 7/7."));
expect("turns present", md.includes("**User:** Build a habit tracker") && md.includes("**Agent:** Built it. Tests 7/7."));
expect("thinking excluded", !md.includes("private"));
expect("tool activity", md.includes("- Bash: xcodegen generate (ok)"));
expect("empty page says so", handoffMarkdown("s", { ...page, messages: [] } as any).includes("(no assistant message yet)"));

// 2. launch lines
expect("claude gets the instruction as an argument", launchCommand("claude", "claude").cmd.startsWith("claude 'Read HANDOFF.md") && !launchCommand("claude", "claude").tellAfter);
expect("codex likewise", launchCommand("codex", "claude").cmd.startsWith("codex 'Read HANDOFF.md"));
expect("cursor-agent likewise", launchCommand("cursor-agent", "codex").cmd.startsWith("cursor-agent 'Read HANDOFF.md"));
const omp = launchCommand("omp", "claude", "/x/it's.jsonl");
expect("omp imports the claude transcript, quoted", omp.cmd === "omp --from-claude '/x/it'\\''s.jsonl'" && omp.tellAfter, omp.cmd);
expect("omp without a transcript starts bare", launchCommand("omp", "codex").cmd === "omp");
expect("agy/hermes are told afterwards", launchCommand("agy", "claude").tellAfter && launchCommand("hermes", "claude").tellAfter);
expect("six targets", HANDOFF_TARGETS.length === 6);
expect("absolute bin used when given", launchCommand("claude", "claude", undefined, undefined, "/opt/bin/claude").cmd.startsWith("/opt/bin/claude 'Read HANDOFF.md"));
expect("claude resumes its own conversation", launchCommand("claude", "claude", undefined, "abc-1", "/opt/bin/claude").cmd === "/opt/bin/claude --resume 'abc-1' 'Read HANDOFF.md in this folder and continue the task from where it stopped.'", launchCommand("claude", "claude", undefined, "abc-1", "/opt/bin/claude").cmd);
expect("cursor-agent resumes its own chat", launchCommand("cursor-agent", "claude", undefined, "chat-1").cmd.startsWith("cursor-agent --resume 'chat-1' 'Read HANDOFF.md"));
const cr = launchCommand("codex", "claude", undefined, "thread-9");
expect("codex resume is told afterwards", cr.cmd === "codex resume 'thread-9'" && cr.tellAfter, cr.cmd);
expect("pickPane: active agent pane first", pickPane([{ id: "%1", active: false, agent: "claude" }, { id: "%2", active: true, agent: "codex" }])?.id === "%2");
expect("pickPane: agent pane beats active shell", pickPane([{ id: "%1", active: false, agent: "claude" }, { id: "%2", active: true }])?.id === "%1");
expect("pickPane: active shell when no agent", pickPane([{ id: "%1", active: false }, { id: "%2", active: true }])?.id === "%2");
expect("pickPane: the conversation's own agent wins", pickPane([{ id: "%1", active: true, agent: "claude" }, { id: "%2", active: false, agent: "cursor-agent" }], "cursor")?.id === "%2");

// 3. resumable
const items = await listResumable("/work/app");
const kinds = items.map((i: any) => i.kind).sort();
expect("three kinds found", JSON.stringify(kinds) === JSON.stringify(["claude", "claude", "codex", "cursor"]), JSON.stringify(items));
const c1 = items.find((i: any) => i.id === "aaaa-1111");
expect("claude title from first user text", c1?.title === "Build a habit tracker with streaks", c1?.title);
expect("claude resume command", c1?.cmd === "claude --resume aaaa-1111");
expect("system-reminder skipped for title", items.find((i: any) => i.id === "bbbb-2222")?.title === "Fix the crash on launch");
expect("subagent transcripts skipped", !items.some((i: any) => i.id.startsWith("agent-")));
expect("codex only for this cwd", items.filter((i: any) => i.kind === "codex").length === 1 && items.find((i: any) => i.kind === "codex").cmd === "codex resume codex-thread-9");
expect("cursor resume command", items.find((i: any) => i.kind === "cursor")?.cmd === "cursor-agent --resume chat-1");
expect("other dirs empty", (await listResumable("/nowhere")).length === 0);
expect("resumeFor picks the newest claude conversation", ["aaaa-1111", "bbbb-2222"].includes((await resumeFor("claude", "/work/app"))?.id ?? ""), JSON.stringify(await resumeFor("claude", "/work/app")));
expect("resumeFor maps cursor-agent to cursor chats", (await resumeFor("cursor-agent", "/work/app"))?.id === "chat-1");
expect("resumeFor ignores stale conversations", (await resumeFor("codex", "/work/app", Date.now() + 2 * 86_400_000)) === undefined);
expect("resumeFor: omp has nothing to resume", (await resumeFor("omp", "/work/app")) === undefined);

// 4. the hand-off sequence with fake deps
const calls: string[] = [];
const deps = {
  cwdOf: async (s: string) => (s === "sess" ? process.env.WORK_DIR! : null),
  transcriptHint: (_: string) => "/x/t.jsonl",
  chat: async (_: string) => page,
  send: async (_s: string, text?: string, key?: string) => { calls.push(key ? `key:${key}` : `text:${text}`); return { ok: true }; },
  which: (bin: string) => (bin === "codex" || bin === "claude" ? "/usr/local/bin/" + bin : null),
};
expect("unknown agent refused", !(await handoff("sess", "vim", deps as any)).ok);
expect("uninstalled agent refused before touching the pane", !(await handoff("sess", "hermes", deps as any)).ok && calls.length === 0);
expect("unknown cwd refused", !(await handoff("nope", "codex", deps as any)).ok);
const ok = await handoff("sess", "codex", deps as any);
expect("hand-off ok", ok.ok === true, JSON.stringify(ok));
expect("HANDOFF.md written in cwd", (await Bun.file(`${process.env.WORK_DIR}/HANDOFF.md`).text()).includes("## Where it stopped"));
expect("no-pane path: ctrl-c, ctrl-c, launch line, enter", JSON.stringify(calls) === JSON.stringify(["key:ctrl-c", "key:ctrl-c", "text:/usr/local/bin/codex 'Read HANDOFF.md in this folder and continue the task from where it stopped.'", "key:enter"]), JSON.stringify(calls));

// 5. the respawn path: the agent pane is replaced, the shell pane beside it untouched,
// no keystrokes, and Claude's own recent conversation in the directory is resumed.
const respawns: string[] = [];
calls.length = 0;
const deps2 = { ...deps,
  cwdOf: async (s: string) => (s === "sess" ? process.env.WORK_DIR! : null),
  panes: async (_: string) => [{ id: "%3", active: true }, { id: "%1", active: false, agent: "cursor-agent" }],
  respawn: async (pane: string, cwd: string, cmd: string) => { respawns.push(`${pane}|${cwd}|${cmd}`); return { ok: true }; },
};
const r2 = await handoff("sess", "claude", deps2 as any);
expect("respawn hand-off ok", r2.ok === true && r2.pane === "%1", JSON.stringify(r2));
expect("respawn targets the agent pane with cwd and absolute bin", respawns.length === 1 && respawns[0].startsWith(`%1|${process.env.WORK_DIR}|/usr/local/bin/claude --resume 'cccc-3333' 'Read HANDOFF.md`), JSON.stringify(respawns));
expect("respawn path sends no keystrokes", calls.length === 0, JSON.stringify(calls));
expect("result names the resumed conversation", r2.resumed === "cccc-3333", r2.resumed);
const r3 = await handoff("sess", "codex", { ...deps2, panes: async () => [] } as any);
expect("no panes listed falls back to keystrokes", r3.ok && calls.length === 4, JSON.stringify(calls));
const r4 = await handoff("sess", "codex", { ...deps2, respawn: async () => ({ ok: false, error: "pane gone" }) } as any);
expect("respawn failure is reported, not typed around", !r4.ok && r4.error === "pane gone", JSON.stringify(r4));
// HTTP surface
const bad = await handleHandoff(new Request("http://x/resumable?cwd=relative"), new URL("http://x/resumable?cwd=relative"), deps as any);
expect("relative cwd is 400", bad?.status === 400);
const list = await handleHandoff(new Request("http://x/resumable?cwd=/work/app"), new URL("http://x/resumable?cwd=/work/app"), deps as any);
const body = await list!.json();
expect("GET /resumable lists items and installed targets", list!.status === 200 && body.items.length === 4 && JSON.stringify(body.targets) === JSON.stringify(["claude", "codex"]), JSON.stringify(body.targets));
const miss = await handleHandoff(new Request("http://x/agents/nope/resumable"), new URL("http://x/agents/nope/resumable"), deps as any);
expect("unknown session resumable is 404", miss?.status === 404);

if (failed) { console.log("check-handoff: " + failed + " failure(s)"); process.exit(1); }
console.log("check-handoff: OK (markdown, launch lines, resumable stores, respawn on the agent pane + resume, keystroke fallback, HTTP)");
EOF
mkdir -p "$TMP/work"
MESH_ROOT="$ROOT" WORK_DIR="$TMP/work" MESH_CLAUDE_PROJECTS="$TMP/claude" MESH_CODEX_SESSIONS="$TMP/codex" MESH_CURSOR_PROJECTS="$TMP/cursor" bun "$TMP/check.ts"

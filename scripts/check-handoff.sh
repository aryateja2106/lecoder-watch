#!/bin/sh
# handoff.ts self-check: HANDOFF.md carries the last assistant message, the recent turns
# and the tool activity; each target CLI gets the right launch line (OMP imports a Claude
# transcript directly); the resumable list reads Claude, Codex and cursor-agent conversation
# stores for a directory with the exact command that reopens each; and the hand-off itself
# sends interrupt, interrupt, the launch line, Enter — in that order — through the same
# send route the phone uses, refusing unknown or uninstalled agents before touching the pane.
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
cat >"$TMP/check.ts" <<'EOF'
const { handoffMarkdown, launchCommand, listResumable, handoff, handleHandoff, HANDOFF_TARGETS } = await import(`${process.env.MESH_ROOT}/install/payload/meshd/handoff.ts`);
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
expect("sequence: ctrl-c, ctrl-c, launch line, enter", JSON.stringify(calls) === JSON.stringify(["key:ctrl-c", "key:ctrl-c", "text:codex 'Read HANDOFF.md in this folder and continue the task from where it stopped.'", "key:enter"]), JSON.stringify(calls));
// HTTP surface
const bad = await handleHandoff(new Request("http://x/resumable?cwd=relative"), new URL("http://x/resumable?cwd=relative"), deps as any);
expect("relative cwd is 400", bad?.status === 400);
const list = await handleHandoff(new Request("http://x/resumable?cwd=/work/app"), new URL("http://x/resumable?cwd=/work/app"), deps as any);
const body = await list!.json();
expect("GET /resumable lists items and installed targets", list!.status === 200 && body.items.length === 4 && JSON.stringify(body.targets) === JSON.stringify(["claude", "codex"]), JSON.stringify(body.targets));
const miss = await handleHandoff(new Request("http://x/agents/nope/resumable"), new URL("http://x/agents/nope/resumable"), deps as any);
expect("unknown session resumable is 404", miss?.status === 404);

if (failed) { console.log("check-handoff: " + failed + " failure(s)"); process.exit(1); }
console.log("check-handoff: OK (markdown, launch lines, resumable stores, interrupt→launch sequence, HTTP)");
EOF
mkdir -p "$TMP/work"
MESH_ROOT="$ROOT" WORK_DIR="$TMP/work" MESH_CLAUDE_PROJECTS="$TMP/claude" MESH_CODEX_SESSIONS="$TMP/codex" MESH_CURSOR_PROJECTS="$TMP/cursor" bun "$TMP/check.ts"

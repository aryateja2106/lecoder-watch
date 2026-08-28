#!/bin/sh
# check-herdr-sessions.sh — the herdr lane, against a stub `herdr` binary. Never the
# live one: the machine running this has a real herdr with the author's real agents in
# it, and a check that types into those is worse than no check.
#
# The two regressions this pins are the ones actually measured against the live daemon
# on 2026-08-28, both in the cmux lane that herdr rows used to arrive through:
#
#   GET  /agents/cmux:no-such-ref/output -> 200 {"lines":[]}   (a dead pane reads as a quiet one)
#   POST /agents/cmux:no-such-ref/send   -> 200 {"ok":true}    (a keystroke into nothing reports success)
#
# Together those are the whole bug report: "showed nothing and accepted no input". A
# lane that cannot tell gone from quiet will reproduce it, so peek MUST answer null and
# send MUST answer ok:false when the pane does not resolve.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-herdr-sessions: SKIP (no bun)"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# The stub. Answers the real CLI's envelopes: {id,result} on success and
# {id,error:{code,message}} on stdout with exit 1 on failure — the shape that makes a
# failed read indistinguishable from a successful one if you only look at stdout.
# Every invocation is appended to argv.log so the test can assert what was actually run.
cat > "$TMP/herdr" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$ARGV_LOG"
# A marker file, not an env var: the daemon spawns this through /bin/sh and the test
# needs to flip "herdr is not running" partway through a single bun process.
[ -f "$HERDR_STUB_DOWN" ] && { echo "herdr: server not running" >&2; exit 1; }
case "$1 $2" in
"pane list")
  cat <<'J'
{"id":"cli:pane:list","result":{"type":"pane_list","panes":[
{"pane_id":"w5:p1","workspace_id":"w5","tab_id":"w5:t1","cwd":"/Users/a/lecoder","foreground_cwd":"/Users/a/lecoder","focused":true,"agent_status":"working"},
{"pane_id":"w9:p2","workspace_id":"w9","tab_id":"w9:t1","label":"bun-core","cwd":"/w/bun-core","foreground_cwd":"/w/bun-core","focused":false,"agent_status":"unknown"},
{"workspace_id":"wZ","focused":false}
]}}
J
  ;;
"workspace list")
  cat <<'J'
{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[
{"workspace_id":"w5","label":"lecoder","number":1},
{"workspace_id":"w9","label":"bun-core","number":3,"worktree":{"repo_name":"lecoder"}}
]}}
J
  ;;
"pane process-info")
  case "$4" in
  w5:p1) echo '{"id":"x","result":{"type":"pane_process_info","process_info":{"pane_id":"w5:p1","shell_pid":100,"foreground_process_group_id":101,"foreground_processes":[{"pid":101,"name":"claude","cmdline":"claude --resume"}]}}}' ;;
  *)     echo '{"id":"x","result":{"type":"pane_process_info","process_info":{"pane_id":"w9:p2","shell_pid":200,"foreground_processes":[{"pid":200,"name":"bash","cmdline":"-bash"}]}}}' ;;
  esac
  ;;
"pane read")
  case "$3" in
  gone:p9) echo '{"error":{"code":"pane_not_found","message":"pane gone:p9 not found"},"id":"cli:pane:read"}'; exit 1 ;;
  liar:p9) echo '{"error":{"code":"pane_not_found","message":"pane liar:p9 not found"},"id":"cli:pane:read"}'; exit 0 ;;
  blank:p1) : ;;
  *) printf 'first\nsecond\nthird\n' ;;
  esac
  ;;
"pane send-text"|"pane send-keys")
  # On STDERR with an empty stdout, which is where the real CLI puts it for send-keys
  # even though `pane read` puts the identical envelope on stdout. Measured 2026-08-28.
  case "$3" in
  gone:p9) echo '{"error":{"code":"pane_not_found","message":"pane gone:p9 not found"},"id":"cli:request"}' >&2; exit 1 ;;
  esac
  ;;
"pane get")
  case "$3" in
  gone:p9) echo '{"error":{"code":"pane_not_found","message":"pane gone:p9 not found"},"id":"cli:pane:get"}'; exit 1 ;;
  *) echo '{"id":"x","result":{"type":"pane_info","pane":{"pane_id":"w9:p2","label":"bun-core","focused":false,"foreground_cwd":"/w/bun-core"}}}' ;;
  esac
  ;;
esac
exit 0
STUB
chmod +x "$TMP/herdr"

cp "$ROOT/install/payload/meshd/herdr.ts" "$TMP/herdr.ts"

cat > "$TMP/t.ts" <<'TS'
import {
  herdrSessions, herdrOutput, herdrSend, herdrPanes, herdrPaneCount,
  isHerdrAgent, herdrPaneRef, herdrTitle, parsePaneList, parseWorkspaceList,
  parseProcessInfo, parseEnvelope, runError,
} from "./herdr.ts";

const log = process.env.ARGV_LOG!;
let bad = 0;
const say = (m: string) => { console.log(`FAIL: ${m}`); bad = 1; };
const argv = () => Bun.file(log).text();
const reset = async () => { await Bun.write(log, ""); };
// %CPU/mem come from the daemon's ps snapshot, which this lane never reads itself.
const usage = (pids: number[]) => ({ memMB: pids.length * 10, cpuPct: pids.length });

// ---- names ----
if (!isHerdrAgent("herdr:w9:p2")) say("herdr:<pane> must be recognised as a herdr name");
if (isHerdrAgent("cmux:abc")) say("a cmux name must not be claimed by the herdr lane");
if (herdrPaneRef("herdr:w9:p2") !== "w9:p2") say(`pane ref must survive the prefix strip, got ${herdrPaneRef("herdr:w9:p2")}`);

// ---- envelope ----
if (parseEnvelope('{"id":"x","error":{"code":"pane_not_found","message":"pane gone"}}').error !== "pane gone")
  say("an error envelope must yield its message");
if (parseEnvelope('{"id":"x","result":{"ok":1}}').error) say("a success envelope must not read as an error");
if (!parseEnvelope("herdr: command not found").error) say("non-JSON output must read as an error, not as silence");
if (!parseEnvelope("").error) say("empty output must read as an error");

// ---- enumeration ----
await reset();
const rows = await herdrSessions(usage);
if (rows.length !== 2) say(`two well-formed panes expected (the third has no pane_id), got ${rows.length}`);
if (rows[0]?.name !== "herdr:w5:p1") say(`row name must be herdr:<pane_id>, got ${rows[0]?.name}`);
// The honest label: a pane id means nothing on a wrist, the workspace name does.
if (rows[0]?.title !== "lecoder") say(`an unlabelled pane takes its workspace label, got "${rows[0]?.title}"`);
if (rows[1]?.title !== "bun-core") say(`a pane label equal to its workspace must not be doubled up, got "${rows[1]?.title}"`);
if (rows[0]?.agentType !== "Claude") say(`agent type comes from the foreground process, got "${rows[0]?.agentType}"`);
if (rows[1]?.agentType !== "shell") say(`a plain login shell is "shell", got "${rows[1]?.agentType}"`);
if (rows[0]?.attached !== true) say("the focused pane must report attached");
if (rows[1]?.attached !== false) say("an unfocused pane must not report attached");
if (rows[0]?.memMB !== 20) say(`memory must come from the daemon's ps snapshot over both pids, got ${rows[0]?.memMB}`);
if (!(await argv()).includes("pane process-info --pane w5:p1")) say("per-pane process info must actually be asked for");
if (await herdrPaneCount() !== 2) say("the /stats count must agree with the row count");
if ((await argv()).split("\n").filter((l) => l.startsWith("pane process-info")).length !== 2)
  say("the count path must not spend a process-info call per pane — /stats is polled far more often than it is read");

// ---- a machine with no herdr ----
const downMarker = process.env.HERDR_STUB_DOWN!;
await Bun.write(downMarker, "");
if ((await herdrSessions(usage)).length !== 0) say("a machine without herdr must yield no rows, not an error");
if (await herdrPaneCount() !== 0) say("the count must be 0 when herdr is not running");
if (await herdrOutput("herdr:w9:p2", 10, false) !== null) say("peek against a dead herdr must be null, not empty output");
if ((await herdrSend("herdr:w9:p2", "x\n")).ok) say("sending to a machine with no herdr must not report success");
await Bun.file(downMarker).delete();

// ---- peek: gone must not read as quiet ----
const out = await herdrOutput("herdr:w9:p2", 2, false);
if (!out || out.lines.join(",") !== "second,third") say(`peek must return the tail, got ${JSON.stringify(out?.lines)}`);
if (await herdrOutput("herdr:gone:p9", 10, false) !== null)
  say("a pane that does not resolve MUST peek as null — 200 with an empty screen is the dead-terminal bug");
if (await herdrOutput("herdr:liar:p9", 10, false) !== null)
  say("an error envelope on stdout with exit 0 must still be null, and must never be rendered as terminal output");
const blank = await herdrOutput("herdr:blank:p1", 10, false);
if (blank === null) say("a pane that resolves with an empty screen is NOT gone — it must stay peekable");
if (blank && blank.lines.join("") !== "") say("a genuinely blank screen has no lines");

await reset();
await herdrOutput("herdr:w9:p2", 5, true);
if (!(await argv()).includes("recent-unwrapped"))
  say("join=1 must ask for recent-unwrapped — 80 columns soft-wrapped onto a watch is the thing join exists to undo");

// ---- send: a refused keystroke must say so ----
await reset();
const typed = await herdrSend("herdr:w9:p2", "ls -la");
if (!typed.ok) say(`plain text must send, got ${typed.error}`);
if ((await argv()).includes("send-keys")) say("text with no newline must NOT be submitted — that types a command nobody ran");

await reset();
const submitted = await herdrSend("herdr:w9:p2", "ls -la\n");
if (!submitted.ok) say(`a submitted line must send, got ${submitted.error}`);
const lines = (await argv()).trim().split("\n");
if (lines.length !== 2 || !lines[0].includes("send-text") || !lines[1].includes("send-keys w9:p2 enter"))
  say(`a trailing newline is a real Enter press, not a literal byte: got ${JSON.stringify(lines)}`);
if (lines[0].includes("\\n") || lines[0].endsWith("\n")) say("the newline must be stripped from the text half");

const refused = await herdrSend("herdr:gone:p9", "hello\n");
if (refused.ok) say("sending into a pane that does not exist MUST NOT report ok — this is the silent half of the bug report");
// The stub puts this on stderr with an empty stdout, exactly as the real CLI does for
// send-keys. Reading stdout alone reported "herdr returned nothing" over it.
if (refused.error !== "pane gone:p9 not found") say(`the refusal must carry herdr's own words, got "${refused.error}"`);
if (runError({ out: "", err: '{"error":{"message":"on stderr"}}' }) !== "on stderr")
  say("an envelope on stderr must be read — send-keys puts it there and leaves stdout empty");
if (runError({ out: '{"error":{"message":"on stdout"}}', err: "" }) !== "on stdout")
  say("an envelope on stdout must still be read — pane read puts it there");

const key = await herdrSend("herdr:w9:p2", undefined, "enter");
if (!key.ok) say(`a mapped key must send, got ${key.error}`);
const badKey = await herdrSend("herdr:w9:p2", undefined, "page-up");
if (badKey.ok) say("an unmapped key must be refused by name rather than sent and hoped for");
if (!badKey.error?.includes("page-up")) say(`the refusal must name the key, got "${badKey.error}"`);
const nothing = await herdrSend("herdr:w9:p2");
if (nothing.ok) say("a send with neither text nor key is a caller bug, not a success");

// ---- panes ----
const p = await herdrPanes("herdr:w9:p2");
if (p?.panes.length !== 1) say("a herdr session names exactly one pane");
if (p?.panes[0]?.currentPath !== "/w/bun-core") say(`the pane's cwd must survive, got ${p?.panes[0]?.currentPath}`);
if (await herdrPanes("herdr:gone:p9") !== null) say("panes for a vanished pane must be null so the route can 404");

// ---- parsers, directly ----
if (parsePaneList("not json").length !== 0) say("an unparseable pane list is empty, never a throw");
if (parseWorkspaceList("not json").size !== 0) say("an unparseable workspace list is empty, never a throw");
if (parseProcessInfo("not json").pids.length !== 0) say("unparseable process info yields no pids");
const t = herdrTitle({ paneId: "wQ:p1", workspaceId: "wQ", focused: false }, new Map());
if (t !== "wQ:p1") say(`with nothing else known the pane id is the last resort, got "${t}"`);

if (bad) process.exit(1);
console.log("check-herdr-sessions: OK (enumerated with honest labels; gone peeks null, not blank; refused input says why)");
TS

ARGV_LOG="$TMP/argv.log" HERDR_STUB_DOWN="$TMP/down" HERDR_BIN="$TMP/herdr" \
  sh -c ': > "$ARGV_LOG"; cd "'"$TMP"'" && bun run "'"$TMP"'/t.ts"'

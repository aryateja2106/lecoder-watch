// Running a command and actually knowing what happened.
//
// This is the hardest primitive in the harness and the easiest to get subtly wrong, so
// what follows is the mechanism that was MEASURED against a real daemon and a real
// multiplexer. Three plausible designs were tried and rejected, each for a reason worth
// keeping written down:
//
//   1. Scrape the pane. `GET /agents/:n/output` returns the VISIBLE pane only: `seq 1
//      500` came back as 22 lines. `join=1` is capture-pane -J, which joins soft-wrapped
//      lines rather than fetching scrollback, and `lines=400` still returned 24. The
//      route exposes no scrollback at all, so a build's compiler error is simply gone.
//
//   2. Pipe to tee for a live pane, and read `$?`. Two separate bugs. A pipeline runs in
//      a SUBSHELL, so `cd`, `export`, `source` and venv activation are silently lost —
//      `cd /etc` then `pwd` printed /tmp — which destroys the whole point of a
//      persistent session. And `$?` after a pipe is tee's status, always 0, so every
//      failing command looks successful. (PIPESTATUS[0] fixes only the second bug.)
//
//   3. Keep tee via process substitution, `{ cmd ; } > >(tee LOG) 2>&1`. This does keep
//      cd working and the log arrives complete. But tee writes to the pane
//      ASYNCHRONOUSLY, so on a large run the completion marker prints first and is then
//      buried under the remaining output as it floods in. Measured: `seq 1 200000`
//      never reported completion at all. An unrecoverable hang.
//
// What is used instead: redirect straight to a log (no pipe, so no subshell and `$?` is
// the command's own), bound a tail file so a huge log is readable in one 64KB /fs/read,
// and print a marker that also carries the log's byte size so truncation is known
// exactly rather than guessed. The marker is ASSEMBLED BY printf at runtime, so the
// echoed command line never contains the assembled string — a literal marker would match
// the echo and report completion instantly with a bogus exit code.
//
// The cost of this choice, stated plainly: the pane no longer streams the command's
// output live, so a long build is less watchable from the wrist than it would be with
// tee. Correct exit codes and a working `cd` are not negotiable; live echo is. The pane
// still shows the command and, on completion, a bounded tail.

import type { Meshd } from "./meshd";

export type ExecResult = {
  command: string;
  exitCode: number | null;
  output: string;
  /** the log was larger than the tail we brought back */
  truncated: boolean;
  /** total bytes the command actually produced, even when we only carried the tail */
  totalBytes: number | null;
  timedOut: boolean;
  durationMs: number;
  logPath: string;
};

export type ExecOptions = {
  timeoutMs?: number;
  /** bytes of log tail to bring back; must stay under the 64KB /fs/read ceiling */
  tailBytes?: number;
  pollMs?: number;
  /** send ctrl-c on timeout so the session is not left wedged */
  interruptOnTimeout?: boolean;
};

const DEFAULT_TAIL_BYTES = 60000;
const LOG_DIR = "/tmp/mesh-code";

let counter = 0;
function nextId(): string {
  counter += 1;
  return `${process.pid}x${counter}`;
}

/** The measured shell fragment, kept in exactly one place. */
export function wrapCommand(
  command: string,
  id: string,
  tailBytes: number,
): { wrapped: string; logPath: string } {
  const logPath = `${LOG_DIR}/${id}.log`;
  return {
    logPath,
    wrapped:
      `mkdir -p ${LOG_DIR}; ` +
      // No pipe: the command runs in THIS shell, so cd/export/source persist and $? is
      // the command's own status.
      `{ ${command} ; } > ${logPath} 2>&1; __mc_ec=$?; ` +
      `tail -c ${tailBytes} ${logPath} > ${logPath}.tail 2>/dev/null; ` +
      `__mc_sz=$(wc -c < ${logPath} 2>/dev/null | tr -d ' '); ` +
      `printf "MESH%s_%s_%s_%s\\n" DONE ${id} "$__mc_ec" "$__mc_sz"`,
  };
}

export type Marker = { exitCode: number; totalBytes: number | null };

export function findMarker(lines: string[], id: string): Marker | null {
  const prefix = `MESHDONE_${id}_`;
  for (const line of lines) {
    const s = line.trim();
    if (!s.startsWith(prefix)) continue;
    const rest = s.slice(prefix.length);
    const m = /^(\d+)_(\d*)$/.exec(rest);
    if (!m) continue;
    return { exitCode: Number(m[1]), totalBytes: m[2] === "" ? null : Number(m[2]) };
  }
  return null;
}

export async function execInSession(
  mesh: Meshd,
  session: string,
  command: string,
  opts: ExecOptions = {},
): Promise<ExecResult> {
  const timeoutMs = opts.timeoutMs ?? 10 * 60 * 1000;
  const tailBytes = opts.tailBytes ?? DEFAULT_TAIL_BYTES;
  const pollMs = opts.pollMs ?? 500;
  const started = Date.now();

  // A newline would run a half-typed command. Multi-line work belongs in a script file
  // the agent writes first — a small model emits these often enough to matter.
  const oneLine = command.replace(/\r/g, "").trim();
  if (oneLine.includes("\n")) {
    return {
      command,
      exitCode: null,
      output: "refused: command contains a newline. Write a script to a file and run that file instead.",
      truncated: false,
      totalBytes: null,
      timedOut: false,
      durationMs: 0,
      logPath: "",
    };
  }

  const id = nextId();
  const { wrapped, logPath } = wrapCommand(oneLine, id, tailBytes);

  await mesh.sendText(session, wrapped);
  await mesh.sendKey(session, "enter");

  let marker: Marker | null = null;
  let timedOut = false;
  while (true) {
    if (Date.now() - started > timeoutMs) {
      timedOut = true;
      if (opts.interruptOnTimeout !== false) await mesh.sendKey(session, "ctrl-c").catch(() => {});
      break;
    }
    const lines = await mesh.output(session, 40).catch(() => [] as string[]);
    marker = findMarker(lines, id);
    if (marker) break;
    await new Promise((r) => setTimeout(r, pollMs));
  }

  const tail = await mesh.readFile(`${logPath}.tail`).catch(() => ({ text: "", truncated: false }));
  const totalBytes = marker?.totalBytes ?? null;
  const truncated =
    tail.truncated || (totalBytes !== null && totalBytes > Buffer.byteLength(tail.text, "utf8"));

  return {
    command: oneLine,
    exitCode: marker ? marker.exitCode : null,
    output: tail.text,
    truncated,
    totalBytes,
    timedOut,
    durationMs: Date.now() - started,
    logPath,
  };
}

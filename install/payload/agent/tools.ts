// The tool registry.
//
// Sized for the brain that will actually drive it: Qwen 3.6 activates ~3B parameters per
// token. Small models degrade sharply as the tool surface grows — more tools, deeper
// nesting and free-form arguments all raise the rate of malformed and wrong calls. So
// this set is deliberately six flat tools with shallow, mostly-string arguments, and
// every failure is returned to the model as a CORRECTIVE RESULT rather than an
// exception: a bad call should teach the next turn, not end the run.
//
// Commands run through meshd's persistent session so state survives between calls and
// the work stays watchable from the phone and the watch. File edits use the local
// filesystem directly: meshd exposes /fs, /fs/read, /fs/mkdir and /fs/move but no write
// route, and its read truncates at 64KB keeping the head. mesh-code therefore edits the
// machine it runs on, and runs commands through that machine's daemon.

import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import type { Meshd } from "./meshd";
import { execInSession, type ExecResult } from "./exec";
import { compressIfRecognized } from "./mobile";
import { decideCommand, type ApprovalMode } from "./risk";
import type { ToolSchema } from "./model";

export const MAX_TOOL_RESULT_CHARS = 12000;
const MAX_READ_CHARS = 20000;
const MAX_DIR_ENTRIES = 200;

export type ToolContext = {
  mesh: Meshd;
  session: string;
  cwd: string;
  /** default "ask": safe commands run, destructive ones are refused (AGENTS.md principle 4) */
  approve?: ApprovalMode;
  /** set by the finish tool so the loop knows the model considers the task done */
  finished?: { summary: string };
  /** set by the escalate tool; the router treats this as a blocking signal */
  escalationRequest?: { reason: string; question: string; exitCriterion: string };
  onCommand?: (r: ExecResult) => void;
};

export type ToolResult = { ok: boolean; content: string };

/** Keep the tail: compiler errors, stack traces and test failures live at the end. */
export function clamp(text: string, limit = MAX_TOOL_RESULT_CHARS): string {
  if (text.length <= limit) return text;
  const kept = text.slice(text.length - limit);
  const dropped = text.length - limit;
  return `[${dropped} earlier characters omitted — showing the last ${limit}]\n${kept}`;
}

function resolvePath(ctx: ToolContext, p: string): string {
  return resolve(ctx.cwd, p);
}

/**
 * Coerce an argument back to a string.
 *
 * The Qwen tool-call parser opportunistically types any value whose first character is
 * in `{[-0123456789tfn` and which parses as JSON, so `run_command(command="true")`
 * arrives as the BOOLEAN true and a path like `2024` arrives as a NUMBER. Type-checking
 * these with `typeof x === "string"` silently rejects perfectly good calls, which the
 * model then has no way to understand. Coerce, never reject on type alone.
 */
function asString(v: unknown): string {
  if (typeof v === "string") return v;
  if (v === null || v === undefined) return "";
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  return JSON.stringify(v);
}

/**
 * For arguments that are FILE CONTENT, a non-string is never safe to coerce.
 *
 * Qwen's parser opportunistically parses any value that looks like JSON, so writing a
 * .json file hands us an object rather than the author's text. Re-serializing it would
 * silently rewrite their formatting, key order and spacing -- data loss disguised as a
 * successful write, in exactly the repos a mobile developer keeps configs in. Refuse and
 * tell the model how to fix it.
 */
function asContent(v: unknown, field: string): { text: string } | { error: string } {
  if (typeof v === "string") return { text: v };
  if (v === null || v === undefined) return { error: `error: ${field} is required.` };
  if (typeof v === "number" || typeof v === "boolean") return { text: String(v) };
  return {
    error:
      `error: ${field} arrived as structured data, not text, so it was NOT written -- ` +
      `re-serializing it would have changed the file's formatting. Send ${field} as a plain string.`,
  };
}

export const TOOLS: ToolSchema[] = [
  {
    type: "function",
    function: {
      name: "run_command",
      description:
        "Run one shell command in the persistent session and return its output and exit code. State persists: a cd in one call applies to the next. Must be a single line; write a script file for anything longer.",
      parameters: {
        type: "object",
        properties: {
          command: { type: "string", description: "The shell command to run." },
          timeout_seconds: { type: "integer", description: "Optional. Default 600." },
        },
        required: ["command"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "read_file",
      description: "Read a text file. Returns the file with line numbers.",
      parameters: {
        type: "object",
        properties: { path: { type: "string", description: "File path." } },
        required: ["path"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "write_file",
      description:
        "Write a complete file, creating parent directories and overwriting any existing content. Use this for new files and for rewrites.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string" },
          content: { type: "string", description: "The ENTIRE new file content." },
        },
        required: ["path", "content"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "str_replace",
      description:
        "Replace one exact block of text in a file. The find text must appear EXACTLY ONCE; if it appears zero or many times the edit is refused and nothing changes.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string" },
          find: { type: "string", description: "Exact text to replace, including indentation." },
          replace: { type: "string", description: "Replacement text." },
        },
        required: ["path", "find", "replace"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_dir",
      description: "List the entries of a directory.",
      parameters: {
        type: "object",
        properties: { path: { type: "string" } },
        required: ["path"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "escalate",
      description:
        "Ask for a bigger model's help when this task is beyond you. Use it when you have tried and are genuinely stuck, not as a first move. The run pauses for the user to decide.",
      parameters: {
        type: "object",
        properties: {
          reason: { type: "string", description: "Why you cannot do this yourself." },
          question: { type: "string", description: "The specific question a bigger model should answer." },
          exit_criterion: { type: "string", description: "How you will know the answer worked." },
        },
        required: ["reason", "question"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "finish",
      description:
        "Call this when the task is complete, or when you are blocked and cannot continue. This ends the run.",
      parameters: {
        type: "object",
        properties: {
          summary: { type: "string", description: "What you did, or why you are blocked." },
        },
        required: ["summary"],
      },
    },
  },
];

export const TOOL_NAMES = new Set(TOOLS.map((t) => t.function.name));

export async function runTool(
  ctx: ToolContext,
  name: string,
  args: Record<string, any>,
): Promise<ToolResult> {
  switch (name) {
    case "run_command": {
      const command = asString(args.command).trim();
      if (!command) return { ok: false, content: "error: command is required and was empty." };
      // Nothing reaches a shell unreviewed unless the user opted in. The refusal is a
      // corrective tool result rather than a thrown error, so the model can pick a safer
      // route instead of the run dying.
      const gate = decideCommand(command, ctx.approve ?? "ask");
      if (!gate.allow) return { ok: false, content: gate.explanation };
      const timeoutMs = Math.max(1, Number(args.timeout_seconds ?? 600)) * 1000;
      const r = await execInSession(ctx.mesh, ctx.session, command, { timeoutMs });
      ctx.onCommand?.(r);
      const head = r.timedOut
        ? `command timed out after ${Math.round(r.durationMs / 1000)}s and was interrupted`
        : `exit code ${r.exitCode}`;
      const note = r.truncated && r.totalBytes !== null ? ` (output was ${r.totalBytes} bytes; tail shown)` : "";
      // A raw test log or UI dump is minutes of prefill and half the context window, so
      // recognised artifacts are digested before the model ever sees them.
      const compressed = compressIfRecognized(r.output);
      const body =
        r.output.trim() === ""
          ? "(no output)"
          : compressed
            ? `[${compressed.note}]\n\n${clamp(compressed.text)}`
            : clamp(r.output);
      return { ok: r.exitCode === 0, content: `${head}${note}\n\n${body}` };
    }

    case "read_file": {
      const p = resolvePath(ctx, asString(args.path));
      if (!existsSync(p)) return { ok: false, content: `error: no such file: ${p}` };
      const st = statSync(p);
      if (st.isDirectory()) return { ok: false, content: `error: ${p} is a directory. Use list_dir.` };
      let text: string;
      try {
        text = readFileSync(p, "utf8");
      } catch (e) {
        return { ok: false, content: `error: cannot read ${p}: ${e instanceof Error ? e.message : e}` };
      }
      const numbered = text
        .split("\n")
        .map((l, i) => `${String(i + 1).padStart(5)}  ${l}`)
        .join("\n");
      return { ok: true, content: clamp(numbered, MAX_READ_CHARS) };
    }

    case "write_file": {
      const p = resolvePath(ctx, asString(args.path));
      const got = asContent(args.content, "content");
      if ("error" in got) return { ok: false, content: got.error };
      const content = got.text;
      try {
        mkdirSync(dirname(p), { recursive: true });
        writeFileSync(p, content, "utf8");
      } catch (e) {
        return { ok: false, content: `error: cannot write ${p}: ${e instanceof Error ? e.message : e}` };
      }
      return { ok: true, content: `wrote ${p} (${content.length} characters, ${content.split("\n").length} lines)` };
    }

    case "str_replace": {
      const p = resolvePath(ctx, asString(args.path));
      const gotFind = asContent(args.find, "find");
      if ("error" in gotFind) return { ok: false, content: gotFind.error };
      const gotReplace = asContent(args.replace, "replace");
      if ("error" in gotReplace) return { ok: false, content: gotReplace.error };
      const find = gotFind.text;
      const replace = gotReplace.text;
      if (!existsSync(p)) return { ok: false, content: `error: no such file: ${p}` };
      if (find === "") return { ok: false, content: "error: find is required and was empty." };
      const text = readFileSync(p, "utf8");
      const parts = text.split(find);
      const hits = parts.length - 1;
      // Refusing on 0 or >1 is what keeps a small model from silently corrupting a file.
      if (hits === 0)
        return {
          ok: false,
          content: `error: that exact text does not appear in ${p}. Nothing changed. Read the file again and copy the text exactly, including indentation.`,
        };
      if (hits > 1)
        return {
          ok: false,
          content: `error: that text appears ${hits} times in ${p}. Nothing changed. Include more surrounding lines so it matches exactly once.`,
        };
      writeFileSync(p, parts.join(replace), "utf8");
      return { ok: true, content: `replaced 1 occurrence in ${p}` };
    }

    case "list_dir": {
      const p = resolvePath(ctx, asString(args.path) || ".");
      if (!existsSync(p)) return { ok: false, content: `error: no such directory: ${p}` };
      let entries: string[];
      try {
        entries = readdirSync(p);
      } catch (e) {
        return { ok: false, content: `error: cannot list ${p}: ${e instanceof Error ? e.message : e}` };
      }
      const shown = entries.slice(0, MAX_DIR_ENTRIES).map((name) => {
        let suffix = "";
        try {
          suffix = statSync(resolve(p, name)).isDirectory() ? "/" : "";
        } catch {
          suffix = "";
        }
        return name + suffix;
      });
      const more = entries.length > shown.length ? `\n... and ${entries.length - shown.length} more` : "";
      return { ok: true, content: `${p}:\n${shown.join("\n")}${more}` };
    }

    case "escalate": {
      ctx.escalationRequest = {
        reason: asString(args.reason),
        question: asString(args.question),
        exitCriterion: asString(args.exit_criterion),
      };
      // Not a refusal: the run continues locally until the router and the user's consent
      // mode decide otherwise, so a model that escalates too eagerly does not stall.
      return {
        ok: true,
        content:
          "noted: your request for help was recorded. Keep working on what you can in the meantime.",
      };
    }

    case "finish": {
      ctx.finished = { summary: asString(args.summary) };
      return { ok: true, content: "run ended." };
    }

    default:
      return {
        ok: false,
        content: `error: no tool named ${JSON.stringify(name)}. Available tools: ${[...TOOL_NAMES].join(", ")}.`,
      };
  }
}

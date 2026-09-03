// The agent loop.
//
// Everything here exists because the brain is small. A ~3B-active model will emit
// malformed tool calls, invent tool names, repeat a failing command forever, answer in
// prose when it should act, and forget the task. A loop written for a frontier model
// treats each of those as an exception; this one treats them as the normal weather and
// turns each into a corrective tool result, because a correction the model can read is
// worth more than a stack trace the user has to read.
//
// The history is append-only and sent complete every turn. That is not laziness: the
// server keeps exactly ONE cached conversation prefix, so an append-only history is what
// makes turn twenty as cheap as turn two. Anything that rewrites earlier messages —
// summarising in place, dropping a middle tool result — throws that cache away.
//
// Stronger, and specific to this server: on the Qwen dialect the only cache path that
// can hit is raw token-prefix matching, because the structural tool-result path throws
// for every dialect except Gemma (Tokenizer.swift:883). Two consequences shape this file.
// The assistant message is echoed back BYTE-IDENTICALLY — same tool_call ids, same
// arguments string, never re-serialized — or the prefix diverges. And a new USER message
// mid-run is not free: the ChatML template scans back to the last user message that is
// not wholly a tool response, so appending one re-prefills the entire history. Mid-run
// guidance is therefore appended to a tool result the loop is already about to send.

import { Model, ModelError, type Message, type Turn } from "./model";
import { TOOLS, TOOL_NAMES, runTool, clamp, type ToolContext } from "./tools";
import { saveRun, type RunState } from "./session";
import { decide, type ConsentMode, type Ledger, type Verdict } from "./escalate";

export type LoopOptions = {
  maxTurns: number;
  /** consecutive identical failing commands before the loop calls it stuck */
  repeatLimit: number;
  /** default "off": the router runs and records, but nothing leaves the machine */
  consent?: ConsentMode;
  /** the server's context window, used to measure context pressure */
  maxContext?: number;
  onEvent?: (e: LoopEvent) => void;
};

export type LoopEvent =
  | { kind: "turn"; n: number; turn: Turn }
  | { kind: "text"; text: string }
  | { kind: "tool"; name: string; args: any; ok: boolean; summary: string }
  | { kind: "correction"; reason: string }
  | { kind: "stuck"; reason: string }
  | { kind: "escalation"; verdict: Verdict }
  | { kind: "done"; status: RunState["status"]; summary: string };

export function systemPrompt(cwd: string, session: string): string {
  // Short, concrete, and imperative. Long system prompts measurably hurt small models:
  // the instructions compete with the task for attention.
  return [
    "You are a coding agent working on a real machine. You act by calling tools; you never pretend to have run something.",
    "",
    `Working directory: ${cwd}`,
    `Terminal session: ${session} (state persists between commands — a cd applies to the next command)`,
    "",
    "Rules:",
    "1. Take ONE action at a time and read its result before the next.",
    "2. Look before you edit: read a file before changing it.",
    "3. Prove your work by running it. A build that compiles is not a test that passes.",
    "4. If a command fails twice the same way, change your approach instead of repeating it.",
    "5. When the task is done, or you are truly blocked, call finish with a short summary.",
    "6. Never invent file contents, command output, or test results.",
  ].join("\n");
}

function summarise(content: string): string {
  const firstLine = content.split("\n").find((l) => l.trim() !== "") ?? "";
  return firstLine.length > 120 ? `${firstLine.slice(0, 117)}...` : firstLine;
}

export async function runLoop(
  model: Model,
  ctx: ToolContext,
  state: RunState,
  opts: LoopOptions,
): Promise<RunState> {
  const emit = (e: LoopEvent) => opts.onEvent?.(e);
  let lastFailure = "";
  let repeats = 0;
  let consecutiveToolFailures = 0;
  let lastPromptTokens = 0;
  // Carries the endpoint's HTTP status into the router. Without it the "a local 429 is
  // busy, not stuck" rule could never fire, because nothing ever set the field.
  let lastHttpStatus: number | null = null;

  while (state.turns < opts.maxTurns) {
    state.turns += 1;

    let turn: Turn;
    lastHttpStatus = null;
    try {
      turn = await model.chat(state.messages, TOOLS);
    } catch (err) {
      if (err instanceof ModelError) lastHttpStatus = err.status;
      // A tool call the server's own parser rejects fails the whole REQUEST — the
      // harness never receives the offending call, so there is nothing to correct.
      // Retrying is only useful if it can produce different output, and at temperature
      // 0 it cannot, so the single retry deliberately raises temperature to break
      // determinism. One retry, then the run fails honestly.
      emit({ kind: "correction", reason: `generation failed (${err instanceof Error ? err.message : err}); retrying once` });
      try {
        turn = await model.chat(state.messages, TOOLS, 0.4);
      } catch (err2) {
        if (err2 instanceof ModelError) lastHttpStatus = err2.status;
        state.status = "failed";
        state.summary = err2 instanceof Error ? err2.message : String(err2);
        state.updatedISO = new Date().toISOString();
        saveRun(state);
        emit({ kind: "done", status: "failed", summary: state.summary });
        return state;
      }
    }

    emit({ kind: "turn", n: state.turns, turn });
    if (turn.usage) {
      lastPromptTokens = turn.usage.prompt;
      state.tokens.prompt += turn.usage.prompt;
      state.tokens.completion += turn.usage.completion;
      state.tokens.cached += turn.usage.cached;
    }
    state.brain = { model: turn.model, endpoint: turn.endpoint, source: model.cfg.source };
    state.messages.push(turn.message);

    const text = typeof turn.message.content === "string" ? turn.message.content.trim() : "";
    if (text) emit({ kind: "text", text });

    // No tool calls: the model answered in prose. That is either a finished task it
    // forgot to declare, or drift. One nudge, then it counts as being stuck — nudging
    // forever is how a small model burns an afternoon.
    if (turn.calls.length === 0) {
      if (lastFailure === "no-tool-call") {
        state.status = "finished";
        state.summary = text || "model stopped calling tools";
        state.updatedISO = new Date().toISOString();
        saveRun(state);
        emit({ kind: "done", status: "finished", summary: state.summary });
        return state;
      }
      lastFailure = "no-tool-call";
      // The one place a user message is unavoidable — there is no tool result to append
      // to when the model answered in prose. It costs a full re-prefill on this server,
      // so it happens at most once per run: the next prose answer ends the run instead.
      state.messages.push({
        role: "user",
        content:
          "You did not call a tool. If the task is complete, call finish. Otherwise call the next tool you need.",
      });
      emit({ kind: "correction", reason: "no tool call" });
      state.updatedISO = new Date().toISOString();
      saveRun(state);
      continue;
    }

    for (const call of turn.calls) {
      // Malformed arguments and invented tool names are routine, not exceptional.
      if (call.parseError || call.args === null) {
        const content = `error: your arguments were not valid JSON (${call.parseError}). Call ${call.name} again with a single valid JSON object.`;
        state.messages.push({ role: "tool", tool_call_id: call.id, content });
        emit({ kind: "correction", reason: `malformed arguments for ${call.name}` });
        continue;
      }
      if (!TOOL_NAMES.has(call.name)) {
        const content = `error: no tool named ${JSON.stringify(call.name)}. Available: ${[...TOOL_NAMES].join(", ")}.`;
        state.messages.push({ role: "tool", tool_call_id: call.id, content });
        emit({ kind: "correction", reason: `unknown tool ${call.name}` });
        continue;
      }

      const result = await runTool(ctx, call.name, call.args);
      state.messages.push({
        role: "tool",
        tool_call_id: call.id,
        content: clamp(result.content),
      });
      emit({
        kind: "tool",
        name: call.name,
        args: call.args,
        ok: result.ok,
        summary: summarise(result.content),
      });
      consecutiveToolFailures = result.ok ? 0 : consecutiveToolFailures + 1;

      // Repeating the same failing command is the classic small-model death spiral.
      if (!result.ok && call.name === "run_command") {
        const signature = `${call.name}:${JSON.stringify(call.args.command ?? "")}`;
        if (signature === lastFailure) {
          repeats += 1;
          if (repeats >= opts.repeatLimit) {
            const reason = `the same command failed ${repeats + 1} times: ${call.args.command}`;
            // Appended to the tool result rather than sent as a user message: a user
            // message here would re-prefill the whole history on every stuck run.
            const last = state.messages[state.messages.length - 1];
            if (last && last.role === "tool") {
              last.content = `${last.content}\n\n[harness] You have now run that failing command ${repeats + 1} times. Stop repeating it: either try a different approach, or call finish and explain what is blocking you.`;
            }
            emit({ kind: "stuck", reason });
            repeats = 0;
          }
        } else {
          lastFailure = signature;
          repeats = 0;
        }
      } else if (result.ok) {
        lastFailure = "";
        repeats = 0;
      }

      if (ctx.finished) {
        state.status = "finished";
        state.summary = ctx.finished.summary;
        state.updatedISO = new Date().toISOString();
        saveRun(state);
        emit({ kind: "done", status: "finished", summary: state.summary });
        return state;
      }
    }

    // Is this still worth doing locally? The router is a pure function over facts the
    // protocol already gave us; in the default "off" mode it only records what it would
    // have done, because escalation sends the user's code off their machine.
    const ledger: Ledger = {
      turns: state.turns,
      maxTurns: opts.maxTurns,
      maxContext: opts.maxContext ?? 16384,
      promptTokens: lastPromptTokens,
      cachedTokens: state.tokens.cached,
      consecutiveToolFailures,
      repeatedFailingCommand: repeats + 1,
      modelRequest: ctx.escalationRequest ?? null,
      lastHttpStatus,
    };
    const verdict = decide(ledger, opts.consent ?? "off");
    // Consume the request. Left set, it scores every subsequent turn as blocking, so one
    // call to escalate would make escalation permanent and self-fulfilling.
    ctx.escalationRequest = undefined;
    if (verdict.escalate) {
      emit({ kind: "escalation", verdict });
      state.escalation = { at: state.turns, reason: verdict.reason, action: verdict.action };
      if (verdict.action === "ask-user" || verdict.action === "escalate") {
        state.status = "escalate";
        state.summary = verdict.reason;
        state.updatedISO = new Date().toISOString();
        saveRun(state);
        emit({ kind: "done", status: "escalate", summary: verdict.reason ?? "escalation requested" });
        return state;
      }
    }

    state.updatedISO = new Date().toISOString();
    saveRun(state);
  }

  state.status = "interrupted";
  state.summary = `reached the ${opts.maxTurns}-turn limit without finishing`;
  state.updatedISO = new Date().toISOString();
  saveRun(state);
  emit({ kind: "done", status: "interrupted", summary: state.summary });
  return state;
}

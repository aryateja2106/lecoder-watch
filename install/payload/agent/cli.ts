#!/usr/bin/env bun
// mesh-code — a local coding agent that works through your own machine.
//
// The brain is whichever OpenAI-compatible endpoint is running locally: our own
// inference, or an LM Studio you already use. Commands run inside a persistent meshd
// session, so a task stays watchable and steerable from the phone and the watch while it
// runs, and survives the CLI being closed.
//
//   mesh-code brain                      which local model is available, and what it can do
//   mesh-code run "<task>" [--cwd DIR]   work a task to completion
//   mesh-code runs                       recent runs
//   mesh-code show <id>                  a run's transcript
//
// Human output by default; --json for scripts. Dependency-free, like the rest of the
// payload.

import { Meshd, configFromEnv, MeshdError } from "./meshd";
import { Model, ModelError, resolveEndpoint } from "./model";
import { TOOLS, type ToolContext } from "./tools";
import { runLoop, systemPrompt, type LoopEvent } from "./loop";
import { listRuns, loadRun, newRunId, saveRun, type RunState } from "./session";

const VERSION = "0.1.0";

function parseArgs(argv: string[]) {
  const flags: Record<string, string | boolean> = {};
  const positional: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) flags[key] = true;
      else {
        flags[key] = next;
        i++;
      }
    } else positional.push(a);
  }
  return { flags, positional };
}

function usage(): string {
  return `mesh-code ${VERSION} — a local coding agent

  mesh-code brain                    show the local model server and what it can do
  mesh-code run "<task>"             work a task to completion
  mesh-code runs                     list recent runs
  mesh-code show <id>                show a run

Options
  --endpoint URL     use this OpenAI-compatible endpoint instead of asking meshd
  --model NAME       model id to request
  --cwd DIR          working directory for the task (default: current directory)
  --session NAME     meshd session to work in (default: derived from the run id)
  --max-turns N      stop after N turns (default 40)
  --consent MODE     off (default, records only) | ask | auto — escalation to a bigger model
  --approve MODE     ask (default: destructive commands refused) | auto | never
  --daemon URL       meshd base URL (default http://127.0.0.1:8899)
  --token TOKEN      meshd bearer token (default $MESHD_TOKEN)
  --probe            with 'brain', measure capabilities instead of reading cached ones
  --json             machine-readable output
`;
}

const GREY = "\x1b[90m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";
const RED = "\x1b[31m";
const GREEN = "\x1b[32m";

async function main() {
  const { flags, positional } = parseArgs(Bun.argv.slice(2));
  const command = positional[0];
  const asJson = Boolean(flags.json);

  if (!command || flags.help || command === "help") {
    console.log(usage());
    return;
  }

  const mesh = new Meshd(
    configFromEnv({
      base: typeof flags.daemon === "string" ? flags.daemon : undefined,
      token: typeof flags.token === "string" ? flags.token : undefined,
    }),
  );

  if (command === "brain") {
    const caps = await mesh.capabilities().catch(() => [] as string[]);
    if (!caps.includes("brain")) {
      console.log(
        `${RED}this daemon has no brain capability${RESET}\n` +
          `It is older than the /brain route. Upgrade it, or pass --endpoint to talk to a model directly.`,
      );
      process.exitCode = 1;
      return;
    }
    const body = await mesh.brain(flags.probe ? "?probe=1" : "");
    if (asJson) {
      console.log(JSON.stringify(body, null, 2));
      return;
    }
    for (const e of body.endpoints ?? []) {
      const mark = e.reachable ? `${GREEN}up${RESET}  ` : `${GREY}down${RESET}`;
      const images = e.capabilities?.images ?? "unknown";
      console.log(
        `  ${mark} ${String(e.source).padEnd(10)} ${String(e.model ?? "-").padEnd(24)} ${GREY}images: ${images}${RESET}  ${e.endpoint}`,
      );
    }
    if (!body.brain) console.log(`\n  ${GREY}no local model server is running${RESET}`);
    if (!flags.probe) console.log(`\n  ${GREY}capabilities are cached; --probe measures them${RESET}`);
    return;
  }

  if (command === "runs") {
    const runs = listRuns().slice(0, 20);
    if (asJson) {
      console.log(JSON.stringify(runs.map((r) => ({ ...r, messages: undefined })), null, 2));
      return;
    }
    if (!runs.length) {
      console.log("  no runs yet");
      return;
    }
    for (const r of runs) {
      console.log(
        `  ${r.id.padEnd(30)} ${String(r.status).padEnd(12)} ${String(r.turns).padStart(3)} turns  ${GREY}${r.task.slice(0, 50)}${RESET}`,
      );
    }
    return;
  }

  if (command === "show") {
    const id = positional[1];
    if (!id) {
      console.log("usage: mesh-code show <id>");
      process.exitCode = 1;
      return;
    }
    const run = loadRun(id);
    if (!run) {
      console.log(`no run named ${id}`);
      process.exitCode = 1;
      return;
    }
    if (asJson) {
      console.log(JSON.stringify(run, null, 2));
      return;
    }
    console.log(`${BOLD}${run.task}${RESET}`);
    console.log(
      `${GREY}${run.status} · ${run.turns} turns · ${run.brain ? run.brain.model : "?"} · cached ${run.tokens.cached} of ${run.tokens.prompt} prompt tokens${RESET}\n`,
    );
    for (const m of run.messages) {
      if (m.role === "assistant" && typeof m.content === "string" && m.content.trim())
        console.log(`  ${m.content.trim().slice(0, 400)}`);
      if (m.role === "assistant" && (m as any).tool_calls)
        for (const c of (m as any).tool_calls)
          console.log(`  ${GREY}→ ${c.function.name} ${String(c.function.arguments).slice(0, 120)}${RESET}`);
      if (m.role === "tool")
        console.log(`  ${GREY}  ${String(m.content).split("\n")[0].slice(0, 160)}${RESET}`);
    }
    if (run.summary) console.log(`\n${BOLD}${run.summary}${RESET}`);
    return;
  }

  if (command !== "run") {
    console.log(usage());
    process.exitCode = 1;
    return;
  }

  const task = positional.slice(1).join(" ").trim();
  if (!task) {
    console.log('usage: mesh-code run "<task>"');
    process.exitCode = 1;
    return;
  }

  const cwd = typeof flags.cwd === "string" ? flags.cwd : process.cwd();
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const id = newRunId(`${stamp}-${task.slice(0, 24).replace(/\s+/g, "-").toLowerCase()}`);
  const session = typeof flags.session === "string" ? flags.session : `code-${stamp.slice(11)}`;

  let model: Model;
  try {
    model = new Model(
      await resolveEndpoint(mesh, {
        endpoint: typeof flags.endpoint === "string" ? flags.endpoint : undefined,
        model: typeof flags.model === "string" ? flags.model : undefined,
      }),
    );
  } catch (err) {
    console.log(`${RED}${err instanceof Error ? err.message : String(err)}${RESET}`);
    process.exitCode = 1;
    return;
  }

  // Say which brain is answering, every run. Implying local while a hosted API does the
  // work is the one thing the spec forbids outright.
  console.log(`${BOLD}${task}${RESET}`);
  console.log(`${GREY}brain: ${model.describe()}${RESET}`);
  console.log(`${GREY}session: ${session} · cwd: ${cwd} · run: ${id}${RESET}\n`);

  try {
    await mesh.newSession({ name: session, cwd, cmd: "bash" });
  } catch (err) {
    if (err instanceof MeshdError && err.status === null) {
      console.log(`${RED}${err.message}${RESET}`);
      console.log(`${GREY}mesh-code runs commands through meshd. Start the daemon and try again.${RESET}`);
      process.exitCode = 1;
      return;
    }
    // An existing session of the same name is fine — that is how a run resumes.
  }
  await new Promise((r) => setTimeout(r, 800));

  const state: RunState = {
    id,
    task,
    cwd,
    session,
    status: "running",
    turns: 0,
    createdISO: new Date().toISOString(),
    updatedISO: new Date().toISOString(),
    brain: null,
    summary: null,
    messages: [
      { role: "system", content: systemPrompt(cwd, session) },
      { role: "user", content: task },
    ],
    commands: [],
    tokens: { prompt: 0, completion: 0, cached: 0 },
  };
  saveRun(state);

  const ctx: ToolContext = {
    mesh,
    session,
    cwd,
    approve: (typeof flags.approve === "string" ? flags.approve : "ask") as any,
    onCommand: (r) =>
      state.commands.push({
        command: r.command,
        exitCode: r.exitCode,
        ms: r.durationMs,
        truncated: r.truncated,
      }),
  };

  const onEvent = (e: LoopEvent) => {
    if (asJson) {
      console.log(JSON.stringify(e));
      return;
    }
    switch (e.kind) {
      case "text":
        console.log(`  ${e.text.slice(0, 500)}`);
        break;
      case "tool": {
        const mark = e.ok ? `${GREEN}ok${RESET}` : `${RED}!!${RESET}`;
        const detail =
          e.name === "run_command"
            ? String(e.args.command ?? "")
            : String(e.args.path ?? JSON.stringify(e.args).slice(0, 60));
        console.log(`  ${mark} ${BOLD}${e.name}${RESET} ${GREY}${detail.slice(0, 90)}${RESET}`);
        console.log(`     ${GREY}${e.summary}${RESET}`);
        break;
      }
      case "correction":
        console.log(`  ${GREY}· corrected: ${e.reason}${RESET}`);
        break;
      case "stuck":
        console.log(`  ${RED}· stuck: ${e.reason}${RESET}`);
        break;
      case "escalation":
        console.log(
          `  ${BOLD}· escalation ${e.verdict.action}${RESET}: ${GREY}${e.verdict.reason}${RESET}`,
        );
        break;
      case "done":
        console.log(`\n${BOLD}${e.status}${RESET}: ${e.summary}`);
        break;
    }
  };

  const final = await runLoop(model, ctx, state, {
    maxTurns: Number(flags["max-turns"] ?? 40),
    repeatLimit: 2,
    consent: (typeof flags.consent === "string" ? flags.consent : "off") as any,
    onEvent,
  });

  if (!asJson) {
    const cached = final.tokens.cached;
    const prompt = final.tokens.prompt;
    console.log(
      `${GREY}${final.turns} turns · ${final.commands.length} commands · ` +
        `${cached} of ${prompt} prompt tokens served from cache · run ${final.id}${RESET}`,
    );
  }
  process.exitCode = final.status === "finished" ? 0 : 1;
}

main().catch((err) => {
  console.error(err instanceof ModelError || err instanceof MeshdError ? err.message : err);
  process.exit(1);
});

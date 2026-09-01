// When to stop asking the small model and ask a bigger one.
//
// This is a PURE FUNCTION over a ledger of protocol facts. No I/O, no model opinion, no
// network — which is the only way its thresholds can be argued about with evidence rather
// than taste, and the only way they can be tested on a machine with no Mac, no model and
// no GPU.
//
// Every signal is something the protocol already told us: token counts from `usage`, HTTP
// status, tool exit codes, repeated command hashes, elapsed turns. The model's own opinion
// enters through exactly ONE channel — the `escalate` tool — because a tool call has a
// parser behind it and prose does not.
//
// LOCAL-FIRST IS A PROMISE, SO THE DEFAULT IS "off". AGENTS.md principle 2 says nothing of
// the user's leaves their machines except APNs and the one measured telemetry heartbeat.
// Escalation breaks that by definition, so it ships in shadow mode: the router runs and
// records what it WOULD have done, and nothing leaves the box until the user turns it on.

export type ConsentMode = "off" | "ask" | "auto";

export type Ledger = {
  /** turns taken so far */
  turns: number;
  maxTurns: number;
  /** the server's configured context window */
  maxContext: number;
  /** prompt_tokens from the most recent turn */
  promptTokens: number;
  /** cached_tokens from the most recent turn */
  cachedTokens: number;
  /** tool calls that returned ok:false, consecutively */
  consecutiveToolFailures: number;
  /** highest number of times one identical failing command has been repeated */
  repeatedFailingCommand: number;
  /** the model called the escalate tool */
  modelRequest: { reason: string; question: string; exitCriterion: string } | null;
  /** last HTTP status from the model endpoint, if it errored */
  lastHttpStatus: number | null;
};

export type Signal = { name: string; detail: string; weight: "blocking" | "strong" | "weak" };

export type Verdict = {
  escalate: boolean;
  signals: Signal[];
  reason: string | null;
  /** what the harness should actually do, given the consent mode */
  action: "continue" | "record-only" | "ask-user" | "escalate";
};

export const DEFAULTS = {
  /** fraction of the context window at which a local run is effectively over */
  contextHard: 0.9,
  contextSoft: 0.75,
  /** consecutive failed tool calls that mean the model is not converging */
  toolFailures: 4,
  /** identical failing command repeated this many times */
  commandRepeats: 3,
  /** fraction of the turn budget spent without finishing */
  turnBudget: 0.8,
};

export function decide(
  ledger: Ledger,
  mode: ConsentMode = "off",
  t = DEFAULTS,
): Verdict {
  const signals: Signal[] = [];

  // A local queue-full is BUSY, not STUCK. Conflating the two would escalate a healthy
  // machine every time two sessions overlapped.
  if (ledger.lastHttpStatus === 429) {
    return {
      escalate: false,
      signals: [{ name: "local-busy", detail: "queue full (429): back off and retry", weight: "weak" }],
      reason: null,
      action: "continue",
    };
  }

  if (ledger.modelRequest) {
    signals.push({
      name: "model-asked",
      detail: ledger.modelRequest.reason.slice(0, 120),
      weight: "blocking",
    });
  }

  if (ledger.maxContext > 0) {
    const used = ledger.promptTokens / ledger.maxContext;
    if (used >= t.contextHard) {
      signals.push({
        name: "context-exhausted",
        detail: `${ledger.promptTokens} of ${ledger.maxContext} tokens (${Math.round(used * 100)}%)`,
        weight: "blocking",
      });
    } else if (used >= t.contextSoft) {
      signals.push({
        name: "context-pressure",
        detail: `${Math.round(used * 100)}% of the context window`,
        weight: "weak",
      });
    }
  }

  if (ledger.consecutiveToolFailures >= t.toolFailures) {
    signals.push({
      name: "not-converging",
      detail: `${ledger.consecutiveToolFailures} tool calls failed in a row`,
      weight: "strong",
    });
  }

  if (ledger.repeatedFailingCommand >= t.commandRepeats) {
    signals.push({
      name: "looping",
      detail: `the same failing command ran ${ledger.repeatedFailingCommand} times`,
      weight: "strong",
    });
  }

  if (ledger.maxTurns > 0 && ledger.turns / ledger.maxTurns >= t.turnBudget) {
    signals.push({
      name: "turn-budget",
      detail: `${ledger.turns} of ${ledger.maxTurns} turns spent`,
      weight: "weak",
    });
  }

  // One blocking signal is enough; otherwise it takes two independent strong ones, so a
  // single bad patch of luck does not send the user's code off the machine.
  const blocking = signals.filter((s) => s.weight === "blocking").length;
  const strong = signals.filter((s) => s.weight === "strong").length;
  const escalate = blocking >= 1 || strong >= 2;

  const reason = escalate
    ? signals
        .filter((s) => s.weight !== "weak")
        .map((s) => `${s.name}: ${s.detail}`)
        .join("; ")
    : null;

  let action: Verdict["action"] = "continue";
  if (escalate) action = mode === "off" ? "record-only" : mode === "ask" ? "ask-user" : "escalate";

  return { escalate, signals, reason, action };
}

/**
 * What would leave the machine. Built deterministically and shown to the user BEFORE
 * anything is sent, because "we redact secrets" is a heuristic and must never be
 * described as a security boundary.
 */
export function handoffBrief(
  task: string,
  ledger: Ledger,
  recentToolResults: string[],
): { text: string; bytes: number } {
  const lines = [
    "# Escalation brief",
    "",
    `Task: ${task}`,
    `Progress: ${ledger.turns} turns, ${ledger.consecutiveToolFailures} consecutive tool failures`,
    ledger.modelRequest ? `The local model asked for help: ${ledger.modelRequest.reason}` : "",
    ledger.modelRequest ? `Its question: ${ledger.modelRequest.question}` : "",
    ledger.modelRequest ? `Done when: ${ledger.modelRequest.exitCriterion}` : "",
    "",
    "## Recent tool results",
    ...recentToolResults.slice(-4).map((r) => `- ${r.split("\n")[0].slice(0, 200)}`),
  ].filter(Boolean);
  const text = lines.join("\n");
  return { text, bytes: Buffer.byteLength(text, "utf8") };
}

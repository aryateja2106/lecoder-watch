// Evaluation model: typesafe-ai/jev
// Gateway question types: choice, score, and boolean.
// The check does not call liveGatewayCall.

import { filter, textCarriesSecret } from "./filter.ts";

export type DispatchRoute = "hold-for-review" | "allow-local-tool";

export type EvaluateResult = {
  choice?: string;
  surface?: string;
  score?: number;
  boolean?: boolean;
  confidence?: number;
};

const LOW_CONFIDENCE_BELOW = 0.6;
const HIGH_UNIT_SCORE = 0.75;
const HIGH_RUNG = 3;
const RISK_RUNGS = 3;

const EVALUATE_URL = "https://ai-gateway.vercel.sh/v1/evaluate";

const QUESTIONS = {
  surface: {
    type: "choice",
    instructions: "Where should this turn be shown? Text wins unless the work is a picture the user can see.",
    criteria: {
      "terminal-text": "The work is text the user can read.",
      "wait-for-human": "A person needs to answer before anything else happens.",
      "needs-graphical-screen": "The work is a picture. Pixels stay on the machine.",
    },
  },
  dispatch: {
    type: "choice",
    instructions: "Should this step wait for review or run a local tool?",
    criteria: {
      "hold-for-review": "A person confirms before anything reaches a shell.",
      "allow-local-tool": "A single local tool call is enough.",
    },
  },
  risk: {
    type: "score",
    instructions: "How far does this step go, from reading a note up to running a command?",
    criteria: ["Read a note", "Look something up", "Change a file", "Run a command"],
  },
  localModelFit: {
    type: "boolean",
    instructions: "Is this a single scoped step a local model can attempt?",
    criteria: {
      true: "One scoped step a local model can attempt.",
      false: "Needs more than one step, or a tool a local model should not run.",
    },
  },
};

function riskIsHigh(score: number): boolean {
  if (score <= 1) return score >= HIGH_UNIT_SCORE;
  return score >= HIGH_RUNG;
}

function resolveEvaluation(evaluation: EvaluateResult): EvaluateResult {
  const record = evaluation as Record<string, unknown>;
  if (
    isRecord(record.answers) ||
    isRecord(record.surface) ||
    isRecord(record.dispatch) ||
    isRecord(record.risk) ||
    isRecord(record.localModelFit)
  ) {
    return evaluationFromPayload(evaluation);
  }
  return evaluation;
}

function textMovesSecret(value: string): boolean {
  if (/\bmesh\s+token\b/i.test(value)) return true;
  return /\b(?:upload|send|post|forward|exfiltrate)\b[^.!?\n]{0,80}\b(?:token|password|secret|credential)\b/i.test(
    value,
  );
}

function movesMachineSecret(value: unknown): boolean {
  if (typeof value === "string") return textMovesSecret(value) || textCarriesSecret(value);
  if (Array.isArray(value)) return value.some((item) => movesMachineSecret(item));
  if (isRecord(value)) return Object.values(value).some((item) => movesMachineSecret(item));
  return false;
}

export function route(state: unknown, evaluation: EvaluateResult): DispatchRoute {
  if (state === null || typeof state !== "object") return "hold-for-review";
  // Filtering can remove the secret and still leave the ask. That ask must
  // not become an allowed tool call.
  if (movesMachineSecret(state)) return "hold-for-review";
  const decision = resolveEvaluation(evaluation);
  const score = decision.score;
  const confidence = decision.confidence;
  if (typeof score !== "number" || !Number.isFinite(score) || riskIsHigh(score)) return "hold-for-review";
  if (typeof confidence !== "number" || !Number.isFinite(confidence) || confidence < LOW_CONFIDENCE_BELOW) {
    return "hold-for-review";
  }
  if (decision.surface === "wait-for-human" || decision.surface === "needs-graphical-screen") {
    return "hold-for-review";
  }
  if (decision.boolean !== true) return "hold-for-review";
  if (decision.surface !== "terminal-text") return "hold-for-review";
  if (decision.choice === "allow-local-tool") return "allow-local-tool";
  return "hold-for-review";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function answersOf(payload: unknown): Record<string, unknown> | undefined {
  if (!isRecord(payload)) return undefined;
  if (isRecord(payload.answers)) return payload.answers;
  if (
    isRecord(payload.dispatch) ||
    isRecord(payload.risk) ||
    isRecord(payload.surface) ||
    isRecord(payload.localModelFit)
  ) {
    return payload;
  }
  return undefined;
}

function unitRisk(score: unknown): number | undefined {
  if (typeof score !== "number" || !Number.isFinite(score)) return undefined;
  return score / RISK_RUNGS;
}

function lowestConfidence(payload: unknown, dispatchProbability: number | undefined): number | undefined {
  const values: number[] = [];
  if (isRecord(payload) && isRecord(payload.providerMetadata)) {
    const typesafe = payload.providerMetadata.typesafe;
    if (isRecord(typesafe) && isRecord(typesafe.confidence)) {
      const confidence = typesafe.confidence;
      for (const key of ["surface", "dispatch", "risk", "localModelFit"]) {
        if (typeof confidence[key] === "number") values.push(confidence[key]);
      }
    }
  }
  if (values.length === 0 && typeof dispatchProbability === "number") values.push(dispatchProbability);
  if (values.length === 0) return undefined;
  return Math.min(...values);
}

function evaluationFromPayload(payload: unknown): EvaluateResult {
  const answers = answersOf(payload);
  if (!answers) return {};
  const surfaceAnswer = isRecord(answers.surface) ? answers.surface : undefined;
  const dispatch = isRecord(answers.dispatch) ? answers.dispatch : undefined;
  const risk = isRecord(answers.risk) ? answers.risk : undefined;
  const fit = isRecord(answers.localModelFit) ? answers.localModelFit : undefined;
  const surface = surfaceAnswer && typeof surfaceAnswer.choice === "string" ? surfaceAnswer.choice : undefined;
  const choice = dispatch && typeof dispatch.choice === "string" ? dispatch.choice : undefined;
  let dispatchProbability: number | undefined;
  if (dispatch && choice && isRecord(dispatch.probabilities)) {
    const selected = dispatch.probabilities[choice];
    if (typeof selected === "number") dispatchProbability = selected;
  }
  const probability = fit && typeof fit.probability === "number" ? fit.probability : undefined;
  return {
    surface,
    choice,
    score: unitRisk(risk?.score),
    boolean: typeof probability === "number" && Number.isFinite(probability) ? probability >= 0.5 : undefined,
    confidence: lowestConfidence(payload, dispatchProbability),
  };
}

export async function liveGatewayCall(state: Record<string, unknown>): Promise<"skipped" | DispatchRoute> {
  const key = process.env.AI_GATEWAY_API_KEY;
  if (typeof key !== "string" || key.length === 0) return "skipped";

  const filtered = filter(state);
  const response = await fetch(EVALUATE_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "typesafe-ai/jev",
      state: filtered,
      questions: QUESTIONS,
      providerOptions: {
        gateway: { zeroDataRetention: true },
      },
    }),
  });
  if (!response.ok) throw new Error("gateway evaluate failed: " + response.status);

  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    throw new Error("gateway evaluate failed: unreadable response");
  }
  return route(filtered, evaluationFromPayload(payload));
}

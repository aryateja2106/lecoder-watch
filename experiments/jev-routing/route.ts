// Evaluation model: typesafe-ai/jev
// Gateway question types: choice, score, and boolean.

export type DispatchRoute = "hold-for-review" | "allow-local-tool";

export type EvaluateResult = {
  choice?: string;
  score?: number;
  boolean?: boolean;
  confidence?: number;
};

const LOW_CONFIDENCE_BELOW = 0.6;
const HIGH_UNIT_SCORE = 0.75;
const HIGH_RUNG = 3;

function riskIsHigh(score: number): boolean {
  if (score <= 1) return score >= HIGH_UNIT_SCORE;
  return score >= HIGH_RUNG;
}

export function route(state: unknown, evaluation: EvaluateResult): DispatchRoute {
  if (state === null || typeof state !== "object") return "hold-for-review";
  const score = evaluation.score;
  const confidence = evaluation.confidence;
  void evaluation.boolean;
  if (typeof score !== "number" || !Number.isFinite(score) || riskIsHigh(score)) return "hold-for-review";
  if (typeof confidence !== "number" || !Number.isFinite(confidence) || confidence < LOW_CONFIDENCE_BELOW) {
    return "hold-for-review";
  }
  if (evaluation.choice === "allow-local-tool") return "allow-local-tool";
  return "hold-for-review";
}

// This fixture never calls the network. The check does not call this function.
export function liveGatewayCall(): "skipped" {
  const key = process.env.AI_GATEWAY_API_KEY;
  if (typeof key !== "string" || key.length === 0) return "skipped";
  return "skipped";
}

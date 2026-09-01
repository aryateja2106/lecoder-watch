// The brain: a client for any OpenAI-compatible endpoint, local or hosted.
//
// Two engines are supported on purpose, because there are two audiences — an LM Studio
// the user already runs, and our own supervised inference. Both speak Chat Completions,
// so this file treats them identically and the harness never cares which is answering,
// except to SAY which one did (a shipped release gate: the client must show which model
// answered, and we must never imply local when the work went to a hosted API).
//
// Constraints this is written around, all verified against the real server:
//   * It serves ONE generation at a time and queues the rest. Callers must serialize.
//   * It keeps exactly ONE cached conversation prefix. Sending the complete history each
//     turn is what makes a long agent run cheap; interleaving two conversations against
//     one server forfeits the cache for both.
//   * There is NO structured-output/JSON-schema mode and no tool_choice beyond
//     auto|none, so tool calls come back as OpenAI tool_calls and nothing may assume
//     the model can be forced into a shape.

import type { Meshd } from "./meshd";

export type ToolSchema = {
  type: "function";
  function: { name: string; description: string; parameters: Record<string, unknown> };
};

export type Message =
  | { role: "system" | "user"; content: string }
  | { role: "assistant"; content: string | null; tool_calls?: RawToolCall[] }
  | { role: "tool"; tool_call_id: string; content: string };

export type RawToolCall = {
  id: string;
  type: "function";
  function: { name: string; arguments: string };
};

export type ParsedCall = {
  id: string;
  name: string;
  args: Record<string, any> | null;
  rawArgs: string;
  parseError: string | null;
};

export type Turn = {
  message: Message;
  calls: ParsedCall[];
  finishReason: string | null;
  usage: { prompt: number; completion: number; cached: number } | null;
  model: string;
  endpoint: string;
  ms: number;
};

export type ModelConfig = {
  endpoint: string;
  model: string;
  apiKey?: string;
  source: string;
  timeoutMs: number;
  temperature: number;
  maxTokens: number;
};

export class ModelError extends Error {}

/**
 * Resolve which brain to use. Prefers the daemon's own view (GET /brain) so the CLI and
 * the phone agree on what is running, and falls back to probing directly when the daemon
 * is older than the brain capability — clients gate on the capability string, never on a
 * version number.
 */
export async function resolveEndpoint(
  mesh: Meshd | null,
  explicit?: { endpoint?: string; model?: string; apiKey?: string },
): Promise<ModelConfig> {
  const base: ModelConfig = {
    endpoint: "",
    model: "",
    apiKey: explicit?.apiKey ?? process.env.MESH_MODEL_API_KEY,
    source: "explicit",
    timeoutMs: Number(process.env.MESH_MODEL_TIMEOUT_MS ?? 300000),
    temperature: 0,
    maxTokens: 2048,
  };

  if (explicit?.endpoint) {
    base.endpoint = explicit.endpoint.replace(/\/$/, "");
    base.model = explicit.model ?? (await firstModel(base)) ?? "local-model";
    return base;
  }

  if (mesh) {
    const caps = await mesh.capabilities().catch(() => [] as string[]);
    if (caps.includes("brain")) {
      const b = await mesh.brain().catch(() => null);
      const chosen = b?.brain;
      if (chosen?.reachable) {
        base.endpoint = String(chosen.endpoint).replace(/\/$/, "");
        base.model = explicit?.model ?? String(chosen.model ?? "local-model");
        base.source = String(chosen.source ?? "meshd");
        return base;
      }
      throw new ModelError(
        "no local model server is reachable on this machine. Start one, or pass --endpoint.",
      );
    }
  }

  // Last resort: the two conventional loopback ports.
  for (const [source, endpoint] of [
    ["mference", "http://127.0.0.1:8080/v1"],
    ["lmstudio", "http://127.0.0.1:1234/v1"],
  ]) {
    const probe = { ...base, endpoint };
    const m = await firstModel(probe);
    if (m) return { ...probe, model: explicit?.model ?? m, source };
  }
  throw new ModelError(
    "no local model server found on :8080 or :1234, and this daemon has no brain capability. Pass --endpoint.",
  );
}

async function firstModel(cfg: ModelConfig): Promise<string | null> {
  try {
    const res = await fetch(`${cfg.endpoint}/models`, { signal: AbortSignal.timeout(3000) });
    if (!res.ok) return null;
    const body: any = await res.json();
    return body?.data?.[0]?.id ?? null;
  } catch {
    return null;
  }
}

function parseCalls(raw: unknown): ParsedCall[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((c: any, i: number) => {
    const rawArgs = typeof c?.function?.arguments === "string" ? c.function.arguments : "";
    let args: Record<string, any> | null = null;
    let parseError: string | null = null;
    try {
      const v = rawArgs.trim() === "" ? {} : JSON.parse(rawArgs);
      if (v && typeof v === "object" && !Array.isArray(v)) args = v;
      else parseError = "arguments were not a JSON object";
    } catch (e) {
      // A small model emits malformed JSON often enough that this must be a routine,
      // recoverable event: the harness turns it into a corrective tool result rather
      // than crashing the run.
      parseError = e instanceof Error ? e.message : String(e);
    }
    return {
      id: String(c?.id ?? `call_${i}`),
      name: String(c?.function?.name ?? ""),
      args,
      rawArgs,
      parseError,
    };
  });
}

export class Model {
  constructor(readonly cfg: ModelConfig) {}

  describe(): string {
    return `${this.cfg.model} via ${this.cfg.source} (${this.cfg.endpoint})`;
  }

  /** One turn. History must be complete and append-only, or the server's prefix cache misses. */
  async chat(messages: Message[], tools: ToolSchema[]): Promise<Turn> {
    const started = Date.now();
    const headers: Record<string, string> = { "content-type": "application/json" };
    if (this.cfg.apiKey) headers.authorization = `Bearer ${this.cfg.apiKey}`;

    const body: Record<string, unknown> = {
      model: this.cfg.model,
      messages,
      temperature: this.cfg.temperature,
      max_tokens: this.cfg.maxTokens,
    };
    if (tools.length) body.tools = tools;

    let res: Response;
    try {
      res = await fetch(`${this.cfg.endpoint}/chat/completions`, {
        method: "POST",
        headers,
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(this.cfg.timeoutMs),
      });
    } catch (err) {
      throw new ModelError(
        `${this.cfg.endpoint} did not answer: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    const text = await res.text();
    if (!res.ok) throw new ModelError(`model returned HTTP ${res.status}: ${text.slice(0, 300)}`);

    let payload: any;
    try {
      payload = JSON.parse(text);
    } catch {
      throw new ModelError(`model returned non-JSON: ${text.slice(0, 200)}`);
    }

    const choice = payload?.choices?.[0];
    const rawCalls = choice?.message?.tool_calls;
    const usage = payload?.usage
      ? {
          prompt: Number(payload.usage.prompt_tokens ?? 0),
          completion: Number(payload.usage.completion_tokens ?? 0),
          cached: Number(payload.usage.prompt_tokens_details?.cached_tokens ?? 0),
        }
      : null;

    return {
      message: {
        role: "assistant",
        content: choice?.message?.content ?? null,
        ...(Array.isArray(rawCalls) && rawCalls.length ? { tool_calls: rawCalls } : {}),
      } as Message,
      calls: parseCalls(rawCalls),
      finishReason: choice?.finish_reason ?? null,
      usage,
      model: String(payload?.model ?? this.cfg.model),
      endpoint: this.cfg.endpoint,
      ms: Date.now() - started,
    };
  }
}

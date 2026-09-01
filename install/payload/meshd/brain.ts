// The local brain for meshd — which model server is running on this machine, which
// model it has loaded, and what it can actually do.
//
//   GET /brain                -> { ok, endpoints: [...], brain }   fast, no generation
//   GET /brain?probe=1        -> same, but capabilities are measured rather than cached
//   GET /brain?need=images    -> brain is the endpoint that accepts images, or null
//
// Two engines are supported on purpose, because there are two audiences: a local
// server the user already runs (LM Studio) and our own supervised inference. Both
// speak OpenAI Chat Completions, so this module treats them identically and never
// starts, stops or reconfigures either — meshd fronts them, it does not own them.
//
// A model server that is not running is a STATE, not a fault: every response here is
// 200 with reachable:false. A 500 would make "no local brain installed" indis-
// tinguishable from "the daemon is broken", and the clients poll this route.
//
// Capability probing costs a generation, so it is opt-in (?probe=1) and cached. The
// one capability worth measuring today is images: our own engine strips vision
// towers at repack and cannot accept them at any size, while LM Studio can if the
// user loaded a vision model. Guessing from the engine name would be wrong the day
// either changes, so it is measured and cached instead.

const DEFAULT_CANDIDATES: Array<{ source: string; endpoint: string }> = [
  { source: "mference", endpoint: "http://127.0.0.1:8080/v1" },
  { source: "lmstudio", endpoint: "http://127.0.0.1:1234/v1" },
];

// A reachability check must not stall the wrist. A local server that cannot answer
// GET /v1/models in this long is not one an agent loop should be waiting on either.
const REACH_TIMEOUT_MS = 1200;
const PROBE_TIMEOUT_MS = 20000;
const CAPABILITY_TTL_MS = 10 * 60 * 1000;

// 1x1 PNG. The content is irrelevant: this asks whether the endpoint accepts an
// image part at all, which is the line between a text-only engine and a vision one.
const TINY_PNG =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

type Tri = "yes" | "no" | "unknown";

type Capabilities = { images: Tri };

type EndpointStatus = {
  source: string;
  endpoint: string;
  reachable: boolean;
  model: string | null;
  models?: string[];
  capabilities: Capabilities;
  ms: number;
  error?: string;
};

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

function candidates(): Array<{ source: string; endpoint: string }> {
  // An explicit override replaces the list rather than extending it, so a user who
  // points us somewhere specific does not also get probed on two other ports.
  const override = process.env.MESHD_BRAIN_URL;
  if (override) return [{ source: "custom", endpoint: override.replace(/\/$/, "") }];
  return DEFAULT_CANDIDATES;
}

const capabilityCache = new Map<string, { at: number; caps: Capabilities }>();

function cacheKey(endpoint: string, model: string | null): string {
  return `${endpoint}::${model ?? ""}`;
}

async function reach(source: string, endpoint: string): Promise<EndpointStatus> {
  const started = Date.now();
  const base: EndpointStatus = {
    source,
    endpoint,
    reachable: false,
    model: null,
    capabilities: { images: "unknown" },
    ms: 0,
  };
  try {
    const res = await fetch(`${endpoint}/models`, { signal: AbortSignal.timeout(REACH_TIMEOUT_MS) });
    base.ms = Date.now() - started;
    if (!res.ok) return { ...base, error: `HTTP ${res.status}` };
    const body = (await res.json().catch(() => null)) as any;
    const models: string[] = Array.isArray(body?.data)
      ? body.data.map((m: any) => String(m?.id ?? "")).filter(Boolean)
      : [];
    return { ...base, reachable: true, model: models[0] ?? null, models };
  } catch (err) {
    base.ms = Date.now() - started;
    // Connection refused is the ordinary case — the user simply is not running one.
    return { ...base, error: err instanceof Error ? err.message : String(err) };
  }
}

/** Ask the endpoint to look at an image. 400/415/422 is a text-only engine answering honestly. */
async function probeImages(endpoint: string, model: string | null): Promise<Tri> {
  try {
    const res = await fetch(`${endpoint}/chat/completions`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        model: model ?? "local-model",
        max_tokens: 1,
        temperature: 0,
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: "ok?" },
              { type: "image_url", image_url: { url: TINY_PNG } },
            ],
          },
        ],
      }),
      signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
    });
    if (res.status === 400 || res.status === 415 || res.status === 422) return "no";
    if (res.ok) return "yes";
    return "unknown";
  } catch {
    return "unknown";
  }
}

async function withCapabilities(status: EndpointStatus, forceProbe: boolean): Promise<EndpointStatus> {
  if (!status.reachable) return status;
  const key = cacheKey(status.endpoint, status.model);
  const hit = capabilityCache.get(key);
  if (hit && !forceProbe && Date.now() - hit.at < CAPABILITY_TTL_MS) {
    return { ...status, capabilities: hit.caps };
  }
  if (!forceProbe) return status; // unknown until someone pays for a probe
  const caps: Capabilities = { images: await probeImages(status.endpoint, status.model) };
  capabilityCache.set(key, { at: Date.now(), caps });
  return { ...status, capabilities: caps };
}

export async function handleBrain(req: Request, url: URL): Promise<Response | null> {
  if (url.pathname !== "/brain" || req.method !== "GET") return null;

  const need = url.searchParams.get("need");
  // Asking for a capability implies measuring it; otherwise the answer would be a
  // guess dressed as a routing decision.
  const forceProbe = url.searchParams.get("probe") === "1" || need === "images";

  const found = await Promise.all(candidates().map((c) => reach(c.source, c.endpoint)));
  const endpoints = await Promise.all(found.map((s) => withCapabilities(s, forceProbe)));

  const reachable = endpoints.filter((e) => e.reachable);

  if (need === "images") {
    const capable = reachable.find((e) => e.capabilities.images === "yes") ?? null;
    return json({
      ok: true,
      need,
      brain: capable,
      endpoints,
      reason: capable
        ? null
        : reachable.length
          ? "no reachable local model accepts images; load a vision model in LM Studio"
          : "no local model server is running",
    });
  }

  return json({ ok: true, brain: reachable[0] ?? null, endpoints });
}

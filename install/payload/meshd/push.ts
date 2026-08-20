// APNs push — meshd notifies the phone directly (no cloud relay, local-first).
// Key: ~/.mesh/apns/AuthKey_<KEYID>.p8 (create at developer.apple.com → Keys, APNs enabled).
// Registered device tokens live in ~/.mesh/push-tokens.json; the iOS app POSTs its
// token to /push/register on every host it knows. Delivery uses system curl --http2
// (APNs is HTTP/2-only; curl is everywhere meshd runs). JWT is ES256 via crypto.subtle.
import os from "node:os";
import { readFile, writeFile, mkdir, readdir } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const MESH_DIR = join(homedir(), ".mesh");
const APNS_DIR = join(MESH_DIR, "apns");
const TOKENS_PATH = join(MESH_DIR, "push-tokens.json");
const TEAM_ID = process.env.MESHD_APPLE_TEAM ?? "B5B87F7AXF";
const TOPIC = process.env.MESHD_APNS_TOPIC ?? "com.lecoder.meshwatch";

type DeviceToken = { token: string; env: "dev" | "prod"; addedISO: string };

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  return Buffer.from(bytes).toString("base64url");
}

// ---------- key + JWT ----------
let keyCache: { keyId: string; key: CryptoKey } | null = null;
let jwtCache: { jwt: string; iat: number } | null = null;

async function loadKey(): Promise<{ keyId: string; key: CryptoKey } | null> {
  if (keyCache) return keyCache;
  const files = await readdir(APNS_DIR).catch(() => [] as string[]);
  const p8 = files.find((f) => /^AuthKey_[A-Z0-9]+\.p8$/.test(f));
  if (!p8) return null;
  const keyId = p8.slice("AuthKey_".length, -".p8".length);
  const pem = await readFile(join(APNS_DIR, p8), "utf8");
  const der = Buffer.from(pem.replace(/-----[^-]+-----|\s/g, ""), "base64");
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  keyCache = { keyId, key };
  return keyCache;
}

async function jwt(): Promise<string | null> {
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache && now - jwtCache.iat < 50 * 60) return jwtCache.jwt; // APNs wants 20–60 min old max
  const k = await loadKey();
  if (!k) return null;
  const unsigned = `${b64url(JSON.stringify({ alg: "ES256", kid: k.keyId }))}.${b64url(JSON.stringify({ iss: TEAM_ID, iat: now }))}`;
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, k.key, new TextEncoder().encode(unsigned),
  );
  const token = `${unsigned}.${b64url(new Uint8Array(sig))}`;
  jwtCache = { jwt: token, iat: now };
  return token;
}

// ---------- token store ----------
async function readTokens(): Promise<DeviceToken[]> {
  const raw = await readFile(TOKENS_PATH, "utf8").catch(() => "[]");
  try { return JSON.parse(raw) as DeviceToken[]; } catch { return []; }
}
async function writeTokens(tokens: DeviceToken[]) {
  await mkdir(MESH_DIR, { recursive: true });
  await writeFile(TOKENS_PATH, JSON.stringify(tokens, null, 2));
}

// ---------- delivery ----------
async function sendOne(dev: DeviceToken, payload: any): Promise<{ ok: boolean; status: number; reason?: string }> {
  const bearer = await jwt();
  if (!bearer) return { ok: false, status: 0, reason: "no APNs key installed" };
  const host = dev.env === "prod" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const proc = Bun.spawn([
    "curl", "-s", "--http2", "-m", "10",
    "-o", "/dev/stdout", "-w", "\n%{http_code}",
    "-H", `authorization: bearer ${bearer}`,
    "-H", `apns-topic: ${TOPIC}`,
    "-H", "apns-push-type: alert",
    "-H", "apns-priority: 10",
    "-d", "@-",
    `https://${host}/3/device/${dev.token}`,
  ], { stdin: new TextEncoder().encode(JSON.stringify(payload)), stdout: "pipe", stderr: "ignore" });
  const out = await new Response(proc.stdout).text();
  await proc.exited;
  const lines = out.trim().split("\n");
  const status = Number(lines.at(-1)) || 0;
  let reason: string | undefined;
  try { reason = JSON.parse(lines.slice(0, -1).join("\n") || "{}").reason; } catch {}
  return { ok: status === 200, status, reason };
}

/// An alert you can act on is one where there is a live session to answer and the agent
/// is actually stopped waiting — that is `mesh-hook`'s "warning" (Claude's Notification
/// hook) or an outright error. A finished-turn "info" is worth a glance, not a prompt
/// with buttons that would type Enter into a session nobody is waiting on.
export function isActionable(level?: string, session?: string): boolean {
  return Boolean(session) && (level === "warning" || level === "error");
}

/// The APNs body. Pure and exported so its shape can be asserted — it is a contract
/// with two Swift apps (see `Shared/AgentNotifications.swift`) and a typo in it fails
/// silently: the alert still arrives, just with no buttons and nowhere to send them.
export function buildPayload(
  title: string, body?: string, opts?: { level?: string; session?: string; host?: string },
) {
  const actionable = isActionable(opts?.level, opts?.session);
  return {
    aps: {
      alert: { title: title.slice(0, 120), body: body?.slice(0, 500) },
      sound: "default",
      // Time-sensitive pierces a Focus, which is the whole point of an agent that is
      // blocked: an alert seen tomorrow morning is an agent idle all night.
      "interruption-level": actionable ? "time-sensitive" : "active",
      // Matches the category the apps register; without it the buttons never appear.
      ...(actionable ? { category: "AGENT_ATTENTION" } : {}),
      // Everything from one session collapses into one thread on the wrist.
      ...(opts?.session ? { "thread-id": opts.session } : {}),
    },
    // The action handler needs to know which machine to answer, and the phone may hold
    // several that each have a session by that name.
    host: opts?.host ?? os.hostname().replace(/\.local$/i, ""),
    session: opts?.session,
    level: opts?.level,
  };
}

export async function pushAlert(
  title: string, body?: string, opts?: { level?: string; session?: string; host?: string },
) {
  const tokens = await readTokens();
  if (!tokens.length) return { ok: false, sent: 0, reason: "no registered devices" };
  const payload = buildPayload(title, body, opts);
  let sent = 0;
  const keep: DeviceToken[] = [];
  for (const dev of tokens) {
    const r = await sendOne(dev, payload);
    if (r.ok) sent++;
    // 410 Gone / BadDeviceToken = token is dead, drop it; keep on transient failures.
    if (r.status === 410 || r.reason === "BadDeviceToken") continue;
    keep.push(dev);
  }
  if (keep.length !== tokens.length) await writeTokens(keep);
  return { ok: sent > 0, sent, of: tokens.length };
}

// ---------- routes (mirrors handleInput contract: null = not ours) ----------
export async function handlePush(req: Request, url: URL): Promise<Response | null> {
  const json = (data: any, status = 200) =>
    new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });

  if (url.pathname === "/push" && req.method === "GET") {
    const k = await loadKey().catch(() => null);
    const tokens = await readTokens();
    return json({ ok: true, configured: Boolean(k), keyId: k?.keyId ?? null, topic: TOPIC, devices: tokens.length });
  }
  if (url.pathname === "/push/register" && req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    const token = String(body.token ?? "").toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(token)) return json({ error: "bad token" }, 400);
    const env: "dev" | "prod" = body.env === "prod" ? "prod" : "dev";
    const tokens = (await readTokens()).filter((t) => t.token !== token);
    tokens.push({ token, env, addedISO: new Date().toISOString() });
    await writeTokens(tokens);
    return json({ ok: true, devices: tokens.length });
  }
  if (url.pathname === "/push/test" && req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    return json(await pushAlert(
      String(body.title ?? "MeshWatch test"),
      body.body ? String(body.body) : undefined,
      { level: body.level ? String(body.level) : undefined, session: body.session ? String(body.session) : undefined },
    ));
  }
  return null;
}

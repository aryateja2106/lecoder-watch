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
  await mkdir(MESH_DIR, { recursive: true, mode: 0o700 });
  await writeFile(TOKENS_PATH, JSON.stringify(tokens, null, 2), { mode: 0o600 });
}

// ---------- one banner per session ----------
/// APNs replaces a notification whose collapse id it has already delivered, so a later
/// "Claude stopped" overwrites the "Claude needs attention" banner instead of stacking
/// under it. The phone reuses the identical string as its local notification
/// identifier, which is what lets one sweep clear pushed and local alerts together —
/// the Swift half is `meshNotificationId` in `Shared/AlertGating.swift` and the two
/// must produce the same bytes.
///
/// Host-level alerts get no collapse id on purpose: with no session there is nothing to
/// supersede, and one id per host would make "disk full" eat "build failed".
export const COLLAPSE_ID_MAX_BYTES = 64;

/// Names are user-chosen; reduce them to characters that are safe in an HTTP header
/// value and one byte wide, which also makes the length clamp plain arithmetic.
function idSafe(value: string): string {
  return value.replace(/[^A-Za-z0-9._-]/g, "_");
}

/// FNV-1a/32. Not security, just a short stable fingerprint that is six lines in both
/// languages and needs no crypto import on either side.
function idHash(value: string): string {
  let hash = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(value)) {
    hash = Math.imul(hash ^ byte, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

export function collapseId(host?: string, session?: string): string | null {
  if (!host || !session) return null;
  const raw = `mesh-${idSafe(host)}-${idSafe(session)}`;
  if (raw.length <= COLLAPSE_ID_MAX_BYTES) return raw;
  // Oversized is not "uncollapsed", it is rejected: APNs 400s the whole push and the
  // alert is lost. Keep a readable head, pin uniqueness with a hash of the whole thing.
  return `${raw.slice(0, COLLAPSE_ID_MAX_BYTES - 9)}-${idHash(raw)}`;
}

// ---------- delivery ----------
async function sendOne(dev: DeviceToken, payload: any, collapse?: string | null): Promise<{ ok: boolean; status: number; reason?: string }> {
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
    ...(collapse ? ["-H", `apns-collapse-id: ${collapse}`] : []),
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

/// What /push (GET) and /doctor both report — exported so doctor.ts never grows
/// its own idea of "configured".
export async function pushStatus() {
  const k = await loadKey().catch(() => null);
  return { configured: Boolean(k), keyId: k?.keyId ?? null, topic: TOPIC, devices: (await readTokens()).length };
}

/// One buzz per question. The same blocked prompt re-fires from hooks and pollers
/// while an agent sits waiting; the first alert is signal, the fifth is why people
/// turn notifications off. Keyed on what a person would call "the same alert".
/// In-process memory only — a daemon restart may repeat one alert, which is fine.
const recentAlerts = new Map<string, number>();
export const DEDUPE_WINDOW_MS = 10 * 60 * 1000;

export function alertKey(title: string, body?: string, opts?: { session?: string; host?: string }): string {
  return [opts?.host ?? "", opts?.session ?? "", title, body ?? ""].join("\u0000");
}

export function shouldSend(key: string, nowMs: number, windowMs = DEDUPE_WINDOW_MS): boolean {
  const last = recentAlerts.get(key);
  if (last !== undefined && nowMs - last < windowMs) return false;
  recentAlerts.set(key, nowMs);
  if (recentAlerts.size > 512) {
    for (const [k, t] of recentAlerts) if (nowMs - t >= windowMs) recentAlerts.delete(k);
  }
  return true;
}

/// An alert you can act on is one where there is a live session to answer and the agent
/// is actually stopped waiting. A finished-turn event is worth a glance, not a prompt
/// with buttons that would type Enter into a session nobody is waiting on.
///
/// More than one vocabulary reaches /events: `mesh-hook` grades warning/error/info,
/// while `mesh-event` and older producers write "needs-input" and "finished" straight
/// through. Must stay in step with `cardStateForLevel` in `Shared/Models.swift`.
export const BLOCKED_LEVELS = ["warning", "needs-input", "needs_input", "needsinput", "error", "failed", "failure"];

/// `replyable` is the event's own word on whether /agents/<session>/send can reach
/// its sender (mesh-hook sets it false outside any multiplexer). Only an explicit
/// false withholds the buttons: events from producers that never say remain exactly
/// as actionable as they were before the field existed.
export function isActionable(level?: string, session?: string, replyable?: boolean): boolean {
  if (replyable === false) return false;
  return Boolean(session) && BLOCKED_LEVELS.includes(String(level ?? "").toLowerCase());
}

/// The APNs body. Pure and exported so its shape can be asserted — it is a contract
/// with two Swift apps (see `Shared/AgentNotifications.swift`) and a typo in it fails
/// silently: the alert still arrives, just with no buttons and nowhere to send them.
export function buildPayload(
  title: string, body?: string, opts?: { level?: string; session?: string; host?: string; replyable?: boolean },
) {
  const actionable = isActionable(opts?.level, opts?.session, opts?.replyable);
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
    // Present only when the event said either way, so old payload shapes are
    // byte-identical and clients can distinguish "no" from "never said".
    ...(typeof opts?.replyable === "boolean" ? { replyable: opts.replyable } : {}),
  };
}

/// A refusal that is explained by having asked the wrong APNs gateway.
export function isWrongEnvironment(result: { status: number; reason?: string }): boolean {
  return result.reason === "BadDeviceToken" || result.status === 400;
}

export async function pushAlert(
  title: string, body?: string, opts?: { level?: string; session?: string; host?: string; replyable?: boolean; force?: boolean },
) {
  const tokens = await readTokens();
  if (!tokens.length) return { ok: false, sent: 0, reason: "no registered devices" };
  if (!opts?.force && !shouldSend(alertKey(title, body, opts), Date.now())) {
    return { ok: true, sent: 0, deduped: true };
  }
  const payload = buildPayload(title, body, opts);
  // Off the payload, not the options: the phone routes buttons by the host in the
  // payload, so the banner it clears has to be keyed by that same name.
  const collapse = collapseId(payload.host, payload.session);
  let sent = 0;
  let changed = false;
  const keep: DeviceToken[] = [];
  for (const dev of tokens) {
    let r = await sendOne(dev, payload, collapse);
    // BadDeviceToken usually means the token is dead — but it says exactly the same
    // thing when the token is alive and we simply asked the wrong gateway. A build
    // that moves from sideloaded to TestFlight flips environments, so try the other
    // side once before writing the device off, and remember the answer.
    if (!r.ok && isWrongEnvironment(r)) {
      const flipped: DeviceToken = { ...dev, env: dev.env === "prod" ? "dev" : "prod" };
      const retry = await sendOne(flipped, payload, collapse);
      if (retry.ok) {
        sent++;
        keep.push(flipped);
        changed = true;
        continue;
      }
      r = retry;
    }
    if (r.ok) sent++;
    if (r.status === 410 || r.reason === "BadDeviceToken" || r.reason === "Unregistered") {
      changed = true;   // genuinely gone, on both gateways
      continue;
    }
    keep.push(dev);     // transient: keep it and try again next time
  }
  if (changed) await writeTokens(keep);
  return { ok: sent > 0, sent, of: tokens.length };
}

// ---------- routes (mirrors handleInput contract: null = not ours) ----------
export async function handlePush(req: Request, url: URL): Promise<Response | null> {
  const json = (data: any, status = 200) =>
    new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });

  if (url.pathname === "/push" && req.method === "GET") {
    return json({ ok: true, ...(await pushStatus()) });
  }
  if (url.pathname === "/push/register" && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as any;
    const token = String(body.token ?? "").toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(token)) return json({ error: "bad token" }, 400);
    const env: "dev" | "prod" = body.env === "prod" ? "prod" : "dev";
    const tokens = (await readTokens()).filter((t) => t.token !== token);
    tokens.push({ token, env, addedISO: new Date().toISOString() });
    await writeTokens(tokens);
    return json({ ok: true, devices: tokens.length });
  }
  if (url.pathname === "/push/test" && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as any;
    return json(await pushAlert(
      String(body.title ?? "MeshWatch test"),
      body.body ? String(body.body) : undefined,
      // force: a person testing their setup must never have the test swallowed.
      { level: body.level ? String(body.level) : undefined, session: body.session ? String(body.session) : undefined, force: true },
    ));
  }
  return null;
}

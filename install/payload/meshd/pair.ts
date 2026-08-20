// pair.ts — bring a phone onto the mesh without typing a 64-character token.
//
//   GET  /pair/new    (loopback only)  -> mints a short code, prints via `mesh pair`
//   POST /pair/claim  { code }         -> { host, port, token, fleet: [...] }
//
// /pair/claim is the ONE unauthenticated route, so server.ts must call handlePair
// BEFORE its auth check. That is safe because a claim only succeeds inside the ten
// minutes after a human ran `mesh pair` on the machine itself:
//
//   * one pending code at a time, single use, 10 min TTL;
//   * no pending code -> every claim is refused and does not even count as an attempt,
//     so there is nothing to grind against for all but ten minutes of the daemon's life;
//   * 5 wrong guesses inside that window burn the code entirely.
//
// The alphabet drops 0/O/1/I/L, so a code read aloud or off a screen is unambiguous:
// 8 chars from 31 symbols is ~8.5e11 codes against a 5-guess budget.
//
// Pairing one machine adopts the whole fleet: ~/.mesh/hosts.json already holds every
// host this user set up, with its token. Loopback addresses in there are rewritten to
// the address the phone actually reached us on — "127.0.0.1" is true for the daemon
// and useless for the phone.
import os from "node:os";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const CODE_LEN = 8;
const TTL_MS = 10 * 60_000;
const MAX_ATTEMPTS = 5;
const HOSTS_PATH = join(homedir(), ".mesh", "hosts.json");

type Pending = { code: string; expires: number; attempts: number };
let pending: Pending | null = null;

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

function isLoopback(server: any, req: Request): boolean {
  const a = server?.requestIP?.(req)?.address ?? "";
  return a === "127.0.0.1" || a === "::1" || a === "::ffff:127.0.0.1";
}

/** 8 unambiguous characters. Shown grouped ("K7M4-QP2X"); compared ungrouped. */
export function mintCode(): string {
  const bytes = new Uint8Array(CODE_LEN);
  crypto.getRandomValues(bytes);
  // Rejection-free modulo is fine here: 256 % 31 skews the first 7 symbols by ~0.4%,
  // far below what 5 guesses could ever exploit.
  return Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join("");
}

/** Strip grouping and case so "k7m4-qp2x", "K7M4 QP2X" and "K7M4QP2X" all match. */
export function normalizeCode(input: unknown): string {
  return String(input ?? "").toUpperCase().replace(/[^0-9A-Z]/g, "");
}

export function pretty(code: string): string {
  return `${code.slice(0, 4)}-${code.slice(4)}`;
}

/** Constant-time-ish compare — the codes are equal length, so a plain loop suffices. */
function sameCode(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function loopbackish(ip: string): boolean {
  return ip === "127.0.0.1" || ip === "::1" || ip === "localhost" || ip.startsWith("127.");
}

/**
 * Every host this machine knows, as the phone should store them.
 * `reachedAt` is the address the phone used to get here, which is the only address we
 * know for certain works from where the phone is standing.
 */
async function fleet(reachedAt: string, selfPort: number, selfToken: string): Promise<any[]> {
  const selfName = os.hostname().replace(/\.local$/i, "");
  const out = [{ host: selfName, ip: reachedAt, port: selfPort, token: selfToken }];
  const seen = new Set([reachedAt]);
  try {
    const cfg = JSON.parse(await readFile(HOSTS_PATH, "utf8"));
    for (const [name, h] of Object.entries<any>(cfg?.hosts ?? {})) {
      const ip = loopbackish(String(h?.ip ?? "")) ? reachedAt : String(h?.ip ?? "");
      if (!ip || !h?.token || seen.has(ip)) continue;
      seen.add(ip);
      out.push({ host: name, ip, port: Number(h.port) || 8899, token: String(h.token) });
    }
  } catch { /* no hosts.json — the self entry alone is a complete answer */ }
  return out;
}

/** Mirrors handleInput's contract: null = not our route. */
export async function handlePair(
  req: Request, url: URL, server: any, opts: { port: number; token: string },
): Promise<Response | null> {
  if (url.pathname === "/pair/new" && req.method === "GET") {
    if (!isLoopback(server, req)) return json({ error: "pairing codes are minted on the machine itself" }, 403);
    const code = mintCode();
    pending = { code, expires: Date.now() + TTL_MS, attempts: 0 };
    return json({
      ok: true, code, pretty: pretty(code),
      expiresISO: new Date(pending.expires).toISOString(),
      ttlSec: Math.round(TTL_MS / 1000),
      host: os.hostname().replace(/\.local$/i, ""),
      port: opts.port,
    });
  }

  if (url.pathname === "/pair/claim" && req.method === "POST") {
    // One refusal for every failure mode: a distinct "no code pending" would tell an
    // attacker exactly when to start guessing.
    const refuse = () => json({ error: "invalid or expired code" }, 403);
    if (!pending || Date.now() > pending.expires) { pending = null; return refuse(); }
    const body = await req.json().catch(() => ({}));
    const given = normalizeCode((body as any)?.code);
    if (!sameCode(given, pending.code)) {
      if (++pending.attempts >= MAX_ATTEMPTS) pending = null;
      return refuse();
    }
    pending = null;                                   // single use
    const reachedAt = url.hostname;
    return json({
      ok: true,
      host: os.hostname().replace(/\.local$/i, ""),
      port: opts.port,
      token: opts.token,
      platform: process.platform,
      fleet: await fleet(reachedAt, opts.port, opts.token),
    });
  }

  return null;
}

// --- self-check: bun install/payload/meshd/pair.ts --check ---
if (import.meta.main && process.argv.includes("--check")) {
  const assert = (ok: boolean, msg: string) => { if (!ok) { console.error(`FAIL: ${msg}`); process.exit(1); } };
  const code = mintCode();
  assert(code.length === CODE_LEN, "code length");
  assert([...code].every((c) => ALPHABET.includes(c)), "code alphabet excludes 0/O/1/I/L");
  assert(normalizeCode(pretty(code).toLowerCase()) === code, "pretty -> normalize round-trips");
  assert(normalizeCode(" k7m4 qp2x ") === "K7M4QP2X", "spaces and case tolerated");
  assert(new Set(Array.from({ length: 200 }, mintCode)).size === 200, "codes are not repeating");
  assert(!sameCode("ABCD", "ABCE") && sameCode("ABCD", "ABCD"), "compare");
  assert(loopbackish("127.0.0.1") && loopbackish("127.1.2.3") && !loopbackish("100.94.221.115"), "loopback detection");
  console.log("check-mesh-pair: OK");
}

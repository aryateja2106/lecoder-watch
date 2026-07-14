// Auth gate for meshd — this daemon executes shell commands, so the gate is the
// only thing between a request and RCE. Rules:
//  - Fail CLOSED: an empty configured token rejects everything (never open).
//  - Header-only: the token is read from `Authorization: Bearer <token>` only,
//    never from a `?token=` query param (that leaks the secret into proxy/tunnel
//    logs and browser history).
//  - Constant-time compare, so a wrong token can't be recovered via timing.
import { timingSafeEqual } from "node:crypto";

const BEARER = "Bearer ";

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a, "utf8");
  const bb = Buffer.from(b, "utf8");
  // Length is not secret; bail before timingSafeEqual (which throws on mismatch).
  if (ab.length !== bb.length) return false;
  return timingSafeEqual(ab, bb);
}

/** True only if `authHeader` carries the exact configured bearer token. */
export function isAuthorized(configuredToken: string, authHeader: string): boolean {
  if (!configuredToken) return false; // fail closed
  if (!authHeader.startsWith(BEARER)) return false;
  const presented = authHeader.slice(BEARER.length);
  if (!presented) return false;
  return safeEqual(presented, configuredToken);
}

// loopback-trust.ts — when meshd may skip the bearer token for a loopback peer.
//
// The exemption is judged from the socket peer address (server.requestIP), never from
// client-controlled headers. Two operator footguns still bypass that:
//
//   1. A reverse proxy on the same host that terminates TLS and forwards to
//      127.0.0.1:8899 — meshd sees loopback even though the client is remote.
//   2. Spoofable forward headers on a direct connection — we refuse the exemption
//      whenever X-Forwarded-For / X-Real-IP / Forwarded are present.
//
// Set MESHD_TRUST_LOOPBACK=0 to disable the exemption entirely (every route needs
// Bearer, including /desktop and `mesh pair` mint on loopback).

const FORWARD_HEADERS = ["x-forwarded-for", "x-real-ip", "forwarded"];

export function hasSpoofableForwardHeaders(req: Request): boolean {
  for (const h of FORWARD_HEADERS) {
    if (req.headers.get(h)) return true;
  }
  return false;
}

/** Default on. MESHD_TRUST_LOOPBACK=0|false|no|off disables loopback bearer exemption. */
export function loopbackTrustEnabled(): boolean {
  const v = (process.env.MESHD_TRUST_LOOPBACK ?? "1").trim().toLowerCase();
  return v !== "0" && v !== "false" && v !== "no" && v !== "off";
}

export function isSocketLoopback(server: any, req: Request): boolean {
  const address = server?.requestIP?.(req)?.address ?? "";
  return address === "127.0.0.1" || address === "::1" || address === "::ffff:127.0.0.1";
}

/** True when authed() may skip the bearer token for this request. */
export function loopbackExempt(server: any, req: Request): boolean {
  if (!loopbackTrustEnabled()) return false;
  if (hasSpoofableForwardHeaders(req)) return false;
  return isSocketLoopback(server, req);
}

// Self-check: `bun loopback-trust.ts --check`
if (import.meta.main && process.argv.includes("--check")) {
  const assert = (cond: boolean, msg: string) => {
    if (!cond) { console.error(`check-mesh-loopback-trust: FAIL ${msg}`); process.exit(1); }
  };

  const mk = (headers: Record<string, string> = {}) =>
    new Request("http://127.0.0.1/", { headers });
  const srv = { requestIP: () => ({ address: "127.0.0.1" }) };

  assert(loopbackTrustEnabled(), "trust defaults on");
  assert(loopbackExempt(srv, mk()), "plain loopback exempt");
  assert(!loopbackExempt(srv, mk({ "x-forwarded-for": "203.0.113.1" })), "X-Forwarded-For blocks exemption");
  assert(!loopbackExempt(srv, mk({ "x-real-ip": "203.0.113.1" })), "X-Real-IP blocks exemption");
  assert(!loopbackExempt(srv, mk({ forwarded: 'for="203.0.113.1"' })), "Forwarded blocks exemption");
  assert(!loopbackExempt({ requestIP: () => ({ address: "10.0.0.5" }) }, mk()), "non-loopback peer not exempt");

  const orig = process.env.MESHD_TRUST_LOOPBACK;
  process.env.MESHD_TRUST_LOOPBACK = "0";
  assert(!loopbackTrustEnabled(), "MESHD_TRUST_LOOPBACK=0 disables trust");
  assert(!loopbackExempt(srv, mk()), "kill-switch blocks exemption");
  if (orig === undefined) delete process.env.MESHD_TRUST_LOOPBACK;
  else process.env.MESHD_TRUST_LOOPBACK = orig;

  console.log("check-mesh-loopback-trust: ok");
}

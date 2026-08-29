#!/bin/sh
# auth.ts self-check: this gate is the only thing between a request and RCE, so it
# fails closed. The historical bug this pins down: an empty MESHD_TOKEN used to mean
# "everything from anywhere is authorized" on a daemon bound to 0.0.0.0.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-auth: SKIP (bun not installed)"; exit 0; }
cd "$ROOT/install/payload/meshd"

bun -e '
import { isAuthorized } from "./auth.ts";

// Fail CLOSED: no configured token means nothing off-box is authorized — not
// everything. (Loopback exemption lives in server.ts, judged by socket address.)
if (isAuthorized("", "")) throw new Error("empty token + empty header must be rejected");
if (isAuthorized("", "Bearer ")) throw new Error("empty token must reject any header");
if (isAuthorized("", "Bearer anything")) throw new Error("empty token must not be a wildcard");

// The exact bearer, and only the exact bearer.
if (!isAuthorized("s3cret", "Bearer s3cret")) throw new Error("the correct token must pass");
if (isAuthorized("s3cret", "Bearer s3cre")) throw new Error("prefix must fail");
if (isAuthorized("s3cret", "Bearer s3cretX")) throw new Error("suffix must fail");
if (isAuthorized("s3cret", "s3cret")) throw new Error("bare token without Bearer must fail");
if (isAuthorized("s3cret", "bearer s3cret")) throw new Error("scheme is case-sensitive by contract");
if (isAuthorized("s3cret", "Bearer ")) throw new Error("empty presented token must fail");
console.log("check-mesh-auth: OK");
'

# Wiring: the gate is only worth anything if server.ts actually calls it. Reverting
# authed() to the old `!TOKEN || header === ...` shape must turn this red.
grep -q 'isAuthorized(TOKEN' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route auth through auth.ts isAuthorized"
  exit 1
}
if grep -q '!TOKEN ||' "$ROOT/install/payload/meshd/server.ts"; then
  echo "FAIL: server.ts still contains a fail-open token branch"
  exit 1
fi
echo "check-mesh-auth: server.ts wired"

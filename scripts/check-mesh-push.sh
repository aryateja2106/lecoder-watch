#!/bin/sh
# push.ts self-check: key discovery + PEM/pkcs8 import, register validation,
# token store round-trip, and that a send attempt with a key present doesn't throw.
# Runs against a throwaway HOME so it never touches ~/.mesh.
# ponytail: real APNs delivery is only provable on-device; this catches everything local.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.mesh/apns"
openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null \
  | openssl pkcs8 -topk8 -nocrypt -out "$TMP/.mesh/apns/AuthKey_CHECKKEY99.p8"

cd "$ROOT/install/payload/meshd"
HOME="$TMP" bun -e '
import { handlePush } from "./push.ts";
const u = (p) => new URL("http://x" + p);
const call = async (path, body) => {
  const req = body
    ? new Request("http://x" + path, { method: "POST", body: JSON.stringify(body) })
    : new Request("http://x" + path);
  return (await handlePush(req, u(path))).json();
};
const status = await call("/push");
if (!status.configured || status.keyId !== "CHECKKEY99") throw new Error("key load failed: " + JSON.stringify(status));
const bad = await call("/push/register", { token: "not-a-token" });
if (!bad.error) throw new Error("bad token accepted");
const good = await call("/push/register", { token: "ab".repeat(32) });
if (good.devices !== 1) throw new Error("register failed");
const again = await call("/push/register", { token: "ab".repeat(32) });
if (again.devices !== 1) throw new Error("dedupe failed");
// send path must not throw even if APNs is unreachable (fire-and-forget contract)
await call("/push/test", { title: "self-check" });
console.log("check-mesh-push: OK");
'

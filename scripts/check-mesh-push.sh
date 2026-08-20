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

// Payload contract with the two Swift apps.
const { buildPayload, isActionable } = await import("./push.ts");
const eq = (got, want, what) => { if (JSON.stringify(got) !== JSON.stringify(want)) throw new Error(`${what}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`); };

// A blocked agent: buttons, a routable target, and loud enough to pierce a Focus.
const blocked = buildPayload("Claude needs attention", "Allow edit?", { level: "warning", session: "api", host: "studio" });
eq(blocked.aps.category, "AGENT_ATTENTION", "category");
eq(blocked.aps["interruption-level"], "time-sensitive", "interruption level");
eq(blocked.aps["thread-id"], "api", "thread id");
eq(blocked.host, "studio", "host");
eq(blocked.session, "api", "session");

// A finished turn is news, not a prompt: no buttons that would type Enter into a
// session nobody is waiting on.
const done = buildPayload("Claude stopped", undefined, { level: "info", session: "api", host: "studio" });
if ("category" in done.aps) throw new Error("an info event must not offer agent buttons");
eq(done.aps["interruption-level"], "active", "info interruption level");

// No session means nothing to answer, whatever the level says.
if ("category" in buildPayload("Disk full", undefined, { level: "error" }).aps) throw new Error("no session must mean no buttons");
if (isActionable("warning", undefined)) throw new Error("isActionable requires a session");
if (!isActionable("error", "api")) throw new Error("errors with a session are actionable");

// Host defaults to this machine rather than going missing, or the buttons have
// nowhere to send.
if (!buildPayload("x", undefined, { level: "warning", session: "s" }).host) throw new Error("host must never be empty");

// APNs rejects oversized payloads; the two free-text fields are the only risk.
const huge = buildPayload("t".repeat(500), "b".repeat(5000), { level: "warning", session: "s", host: "h" });
if (huge.aps.alert.title.length > 120 || huge.aps.alert.body.length > 500) throw new Error("alert text not clamped");

// A BadDeviceToken is indistinguishable from "you asked the wrong gateway", and a
// build moving from sideloaded to TestFlight flips environments. Dropping the device
// on the first refusal is how push dies silently and permanently.
const { isWrongEnvironment } = await import("./push.ts");
if (!isWrongEnvironment({ status: 400, reason: "BadDeviceToken" })) throw new Error("BadDeviceToken must trigger the retry");
if (!isWrongEnvironment({ status: 400 })) throw new Error("a bare 400 must trigger the retry");
if (isWrongEnvironment({ status: 410, reason: "Unregistered" })) throw new Error("410 Unregistered is a real removal, not an environment mismatch");
if (isWrongEnvironment({ status: 200 })) throw new Error("success is not a mismatch");

// The two languages grade the same events; if they drift, the wrist shows buttons the
// push never carries, or carries buttons the wrist will not draw.
const { BLOCKED_LEVELS } = await import("./push.ts");
const swift = (await Bun.file(new URL("../../../Shared/Models.swift", import.meta.url).pathname).text())
  .match(/case ([^:]+): return \.waiting[\s\S]*?case ([^:]+):\s+return \.error/);
if (!swift) throw new Error("cardStateForLevel is not where the check expects it");
for (const level of BLOCKED_LEVELS) {
  if (!`${swift[1]} ${swift[2]}`.includes(`"${level}"`)) {
    throw new Error(`meshd treats "${level}" as blocked but cardStateForLevel does not`);
  }
}

console.log("check-mesh-push: OK");
'

# The category string is duplicated across two languages; if it drifts, the buttons
# silently stop appearing and nothing else fails.
CAT_TS="$(grep -c 'category: "AGENT_ATTENTION"' "$ROOT/install/payload/meshd/push.ts")"
CAT_SWIFT="$(grep -c 'attentionCategory = "AGENT_ATTENTION"' "$ROOT/Shared/AgentNotifications.swift")"
[ "$CAT_TS" -ge 1 ] && [ "$CAT_SWIFT" -ge 1 ] || {
  echo "FAIL: AGENT_ATTENTION category is out of sync between push.ts and AgentNotifications.swift"
  exit 1
}
echo "check-mesh-push: category matches Swift"

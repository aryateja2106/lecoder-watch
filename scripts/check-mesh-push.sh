#!/bin/sh
# push.ts self-check: key discovery + PEM/pkcs8 import, register validation,
# token store round-trip, and that a send attempt with a key present doesn't throw.
# Runs against a throwaway HOME so it never touches ~/.mesh.
# ponytail: real APNs delivery is only provable on-device; this catches everything local.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-push: SKIP (bun not installed)"; exit 0; }
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

// One buzz per question: the identical alert re-firing inside the window is
// suppressed; a NEW question, another session, or the window elapsing all send.
const { alertKey, shouldSend, DEDUPE_WINDOW_MS, pushAlert } = await import("./push.ts");
const k = alertKey("Claude needs attention", "Allow edit?", { session: "api", host: "studio" });
if (!shouldSend(k, 1000)) throw new Error("the first alert must send");
if (shouldSend(k, 1000 + 5 * 60_000)) throw new Error("the identical alert 5 min later must be suppressed");
if (!shouldSend(k, 1000 + 5 * 60_000 + DEDUPE_WINDOW_MS)) throw new Error("after the window it must send again");
if (!shouldSend(alertKey("Claude needs attention", "Overwrite main.py?", { session: "api", host: "studio" }), 2000))
  throw new Error("a NEW question must never be suppressed");
if (alertKey("t", "b", { session: "s1", host: "h" }) === alertKey("t", "b", { session: "s2", host: "h" }))
  throw new Error("different sessions must not collide");
// Wiring: pushAlert itself dedupes (first call attempts delivery, second returns deduped),
// and /push/test forces through so a person testing setup never has the test swallowed.
await pushAlert("dup-check", "same body", { session: "dup" });
const second = await pushAlert("dup-check", "same body", { session: "dup" });
if (!second.deduped) throw new Error("pushAlert must suppress the identical alert");
const test2 = await call("/push/test", { title: "dup-check2", body: "same" });
const test3 = await call("/push/test", { title: "dup-check2", body: "same" });
if (test3.deduped) throw new Error("/push/test must never be deduped");

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

// One banner per session, newest wins. The collapse id is also the identifier the
// phone schedules local alerts under and sweeps when the wait is over, so these
// literals are pinned identically in scripts/check-alert-gating.swift. A drift and the
// phone silently stops clearing pushed banners — the exact complaint this answers.
const { collapseId, COLLAPSE_ID_MAX_BYTES } = await import("./push.ts");
eq(collapseId("studio", "api"), "mesh-studio-api", "collapse id");
eq(collapseId("Aryas-MacBook-Pro", "deploy-api"), "mesh-Aryas-MacBook-Pro-deploy-api", "collapse id");
eq(collapseId("my host", "weird/session name"), "mesh-my_host-weird_session_name", "header-safe collapse id");
// Oversized is not "uncollapsed", it is a 400 and a lost alert.
const longA = collapseId("a".repeat(40), "b".repeat(40));
const longB = collapseId("a".repeat(40), "b".repeat(41));
if (longA.length > COLLAPSE_ID_MAX_BYTES || longB.length > COLLAPSE_ID_MAX_BYTES) throw new Error("collapse id not clamped");
if (longA === longB) throw new Error("clamping must not collapse two different sessions into one banner");
eq(longA, "mesh-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbb-5a32c2e2", "hashed collapse id");
// No session means nothing to supersede; one id per host would make "disk full" eat
// "build failed", and the phone would sweep a host alert it can never match.
if (collapseId("studio", undefined) !== null) throw new Error("a host-level alert must not collapse");
if (collapseId(undefined, "api") !== null) throw new Error("a collapse id needs both halves");

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

# The header itself. The id can be perfect and still collapse nothing if the send stops
# carrying it, and no assertion above reaches into the curl invocation.
grep -q 'apns-collapse-id' "$ROOT/install/payload/meshd/push.ts" || {
  echo "FAIL: pushes no longer carry apns-collapse-id, so every alert stacks again"
  exit 1
}
# And the Swift half of the same identifier. Greps rather than a run: this check is the
# one that runs on Linux CI, where there is no swiftc.
grep -q '"\\(meshNotificationPrefix)\\(meshIdSafe(host))-\\(meshIdSafe(session))"' "$ROOT/Shared/AlertGating.swift" || {
  echo "FAIL: meshNotificationId no longer builds mesh-<host>-<session>; the phone will not clear pushed banners"
  exit 1
}
echo "check-mesh-push: collapse id matches Swift"

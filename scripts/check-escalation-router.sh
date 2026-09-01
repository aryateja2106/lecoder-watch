#!/bin/sh
# Self-check for the escalation router in install/payload/agent/escalate.ts.
#
# The router decides when the user's code leaves their machine, so its thresholds are
# asserted here rather than trusted. It is a pure function, so this runs anywhere — no
# Mac, no model, no network.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/driver.ts" <<'TS'
import { decide, handoffBrief, DEFAULTS, type Ledger } from "AGENT/escalate";

let failed = 0;
const check = (name: string, cond: boolean, detail = "") => {
  if (!cond) { console.log(`  FAIL ${name} ${detail}`); failed++; }
  else console.log(`  ok   ${name} ${detail}`);
};

const base: Ledger = {
  turns: 3, maxTurns: 40, maxContext: 16384, promptTokens: 2000, cachedTokens: 1800,
  consecutiveToolFailures: 0, repeatedFailingCommand: 0, modelRequest: null, lastHttpStatus: null,
};

// A healthy run must never escalate.
check("healthy run stays local", decide(base).escalate === false);

// Local busy is not local stuck.
const busy = decide({ ...base, lastHttpStatus: 429, consecutiveToolFailures: 9, repeatedFailingCommand: 9 });
check("queue-full never escalates", busy.escalate === false && busy.action === "continue",
  busy.signals[0]?.name ?? "");

// Context exhaustion is blocking on its own.
const full = decide({ ...base, promptTokens: Math.round(16384 * 0.95) });
check("context exhaustion escalates", full.escalate === true);
check("  and names the signal", full.signals.some(s => s.name === "context-exhausted"));

// Context PRESSURE alone is only a weak signal and must not escalate by itself.
const pressure = decide({ ...base, promptTokens: Math.round(16384 * 0.80) });
check("context pressure alone does not escalate", pressure.escalate === false);

// One strong signal is not enough; two are.
const oneStrong = decide({ ...base, consecutiveToolFailures: DEFAULTS.toolFailures });
check("one strong signal is not enough", oneStrong.escalate === false);
const twoStrong = decide({ ...base, consecutiveToolFailures: DEFAULTS.toolFailures, repeatedFailingCommand: DEFAULTS.commandRepeats });
check("two strong signals escalate", twoStrong.escalate === true);

// The model asking is blocking on its own.
const asked = decide({ ...base, modelRequest: { reason: "needs a refactor across 12 files", question: "how?", exitCriterion: "tests pass" } });
check("model request escalates", asked.escalate === true);

// Consent gating: the default must not send anything anywhere.
check("default mode only records", asked.action === "record-only", asked.action);
check("ask mode asks the user", decide({ ...base, modelRequest: asked.signals ? { reason: "r", question: "q", exitCriterion: "e" } : null }, "ask").action === "ask-user");
check("auto mode escalates", decide({ ...base, modelRequest: { reason: "r", question: "q", exitCriterion: "e" } }, "auto").action === "escalate");

// Turn budget alone is weak.
check("turn budget alone does not escalate", decide({ ...base, turns: 36 }).escalate === false);

// The brief is deterministic and shows the user what would leave.
const b1 = handoffBrief("fix login", { ...base, modelRequest: { reason: "stuck", question: "q", exitCriterion: "e" } }, ["exit code 1", "exit code 1"]);
const b2 = handoffBrief("fix login", { ...base, modelRequest: { reason: "stuck", question: "q", exitCriterion: "e" } }, ["exit code 1", "exit code 1"]);
check("brief is deterministic", b1.text === b2.text);
check("brief states the task", b1.text.includes("fix login"));
check("brief reports its size", b1.bytes === Buffer.byteLength(b1.text, "utf8"));

if (failed) { console.log(`\n${failed} assertion(s) failed`); process.exit(1); }
console.log("check-escalation-router: all assertions passed");
TS

sed -i "s#AGENT#$ROOT/install/payload/agent#" "$TMP/driver.ts"
bun run "$TMP/driver.ts"

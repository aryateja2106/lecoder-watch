#!/bin/sh
# scripts/check-harness-picker.sh — verify agent CLI lists and usage.

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# (a) Check AGENT_CLIS and HANDOFF_TARGETS
cd "$ROOT/install/payload/meshd"
bun -e '
import { AGENT_CLIS } from "./doctor.ts";
import { HANDOFF_TARGETS } from "./handoff.ts";

const cliSet = new Set(AGENT_CLIS);
if (cliSet.size !== AGENT_CLIS.length) {
    console.error("AGENT_CLIS has duplicates");
    process.exit(1);
}
for (const target of HANDOFF_TARGETS) {
    if (!cliSet.has(target)) {
        console.error("HANDOFF_TARGETS contains " + target + " which is not in AGENT_CLIS");
        process.exit(1);
    }
}
'

cd "$ROOT"

# (b) check server.ts
if grep -q "const AGENT_BINS = \[" install/payload/meshd/server.ts; then
    echo "server.ts still defines AGENT_BINS"
    exit 1
fi
if ! grep -q "AGENT_CLIS" install/payload/meshd/server.ts; then
    echo "server.ts does not import AGENT_CLIS"
    exit 1
fi

# (c) check swift views
if ! grep -q "launchable" iOS/TerminalView.swift; then
    echo "iOS/TerminalView.swift missing launchable"
    exit 1
fi
if ! grep -q "launchable" Watch/WatchViews.swift; then
    echo "Watch/WatchViews.swift missing launchable"
    exit 1
fi

echo "check-harness-picker: OK"

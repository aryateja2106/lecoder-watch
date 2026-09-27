#!/bin/sh
# Structural check: the relay receiver delegate, failure-reason wiring, and honest ack guards.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail=0
msg() { echo "  $1"; }

# 1. PhoneConnectivity must have the fire-and-forget delegate (no replyHandler).
if grep -q 'didReceiveMessage message: \[String: Any\])' "$ROOT/iOS/PhoneConnectivity.swift"; then
    msg "✓ PhoneConnectivity has didReceiveMessage without replyHandler"
else
    msg "✗ PhoneConnectivity missing didReceiveMessage without replyHandler"
    fail=1
fi

# 2. WatchLink acknowledge must reference RelayReply.failureReason.
if grep -q 'RelayReply.failureReason' "$ROOT/Watch/WatchLink.swift"; then
    msg "✓ WatchLink.acknowledge checks RelayReply.failureReason"
else
    msg "✗ WatchLink.acknowledge does not check RelayReply.failureReason"
    fail=1
fi

# 3. MeshStore handle() must use RelayReply.encodeFailure at least 8 times
#    (one per acting-path guard + catch, covering the 9 acting commands and the
#    read-path machine guards).
count=$(grep -c 'RelayReply.encodeFailure' "$ROOT/iOS/MeshStore.swift" || true)
if [ "$count" -ge 8 ]; then
    msg "✓ MeshStore has $count RelayReply.encodeFailure calls (≥ 8)"
else
    msg "✗ MeshStore has only $count RelayReply.encodeFailure calls (need ≥ 8)"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "check-relay-receiver: OK"
else
    echo "check-relay-receiver: FAIL"
    exit 1
fi

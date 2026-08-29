#!/bin/sh
# wol.ts self-check: packet shape and MAC parsing, with no UDP leaving the machine.
# A magic packet is write-only — the target is asleep and cannot answer — so the byte
# layout is the only thing that can ever be verified, and a malformed one fails silently
# forever. Hence: 102 bytes, 6x0xff, then exactly 16 repetitions, checked here.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-wol: SKIP (bun not installed)"; exit 0; }
cd "$ROOT/install/payload/meshd"

bun -e '
import { magicPacket, primaryMac } from "./wol.ts";

const hex = (u) => Array.from(u, (b) => b.toString(16).padStart(2, "0")).join(":");

const p = magicPacket("aa:bb:cc:dd:ee:ff");
if (p.length !== 102) throw new Error(`packet is ${p.length} bytes, want 102`);
for (let i = 0; i < 6; i++) if (p[i] !== 0xff) throw new Error(`byte ${i} is ${p[i]}, want 0xff`);
const mac = [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff];
let reps = 0;
for (let off = 6; off < 102; off += 6) {
  for (let j = 0; j < 6; j++) {
    if (p[off + j] !== mac[j]) throw new Error(`repetition at offset ${off} differs: ${hex(p.slice(off, off + 6))}`);
  }
  reps++;
}
if (reps !== 16) throw new Error(`${reps} MAC repetitions, want 16`);

// Dash form and mixed case are the same address, so they must be the same packet.
const dashed = magicPacket("AA-BB-CC-DD-EE-FF");
if (hex(dashed) !== hex(p)) throw new Error("dash form must produce the same packet as colon form");

// Garbage must throw, not quietly broadcast a packet nothing will ever answer.
for (const bad of ["nope", "", "aa:bb:cc:dd:ee", "aa:bb:cc:dd:ee:ff:00", "aa:bb:cc:dd:ee:gg", "aabbccddeeff", null]) {
  let threw = false;
  try { magicPacket(bad); } catch { threw = true; }
  if (!threw) throw new Error(`invalid MAC accepted: ${JSON.stringify(bad)}`);
}

// This machine may legitimately have no wakeable NIC (container, tailscale-only box),
// but if it reports one it must be an address a magic packet can actually target.
// 02:00:00:00:00:00 is the specific lie macOS tells unentitled processes: accepting it
// would have the phone cache a MAC that wakes nothing, forever, with no error anywhere.
const mine = primaryMac();
if (mine !== null) {
  if (!/^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/.test(mine)) throw new Error(`primaryMac() returned ${JSON.stringify(mine)}`);
  if (mine === "00:00:00:00:00:00") throw new Error("primaryMac() returned the all-zero MAC");
  if (mine === "02:00:00:00:00:00") throw new Error("primaryMac() returned macOS'"'"'s redacted placeholder MAC");
  magicPacket(mine);  // whatever it found must itself be packable
}
console.log(`check-wol: OK (primaryMac -> ${mine ?? "null"})`);
'

# Wiring: the module is dead weight unless server.ts routes to it, advertises it, and
# publishes the MAC that makes zero-configuration waking possible.
grep -q 'path === "/wake"' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: server.ts does not route POST /wake"
  exit 1
}
grep -q '"wake"' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: capabilities do not advertise wake"
  exit 1
}
grep -q 'mac: primaryMac()' "$ROOT/install/payload/meshd/server.ts" || {
  echo "FAIL: /health does not publish this machine's MAC"
  exit 1
}
echo "check-wol: server.ts wired"

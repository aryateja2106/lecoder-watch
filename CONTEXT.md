# CONTEXT — MeshWatch

Read this first. Then `PROGRESS.md` (slice log), then `docs/mac-remote-control.md`
(the control surface), then `git log`.

## What this is

Control any machine you own from an Apple Watch and iPhone, over your own Tailscale
mesh. Local-first: no cloud relay anywhere in the path. The watch is the product; the
phone is the config surface and the relay of last resort.

## The shape of it

```
Watch ──URLSession──▶ meshd ──▶ mesh-input (CGEvent/AXUIElement) ──▶ macOS
  └── off-tailnet ──WCSession──▶ iPhone ──HTTP──┘
                                   meshd ──APNs (direct, ES256)──▶ iPhone/Watch
```

- **`meshd`** — one per machine, bun + TypeScript, bearer auth over Tailscale. Owns
  stats, agent sessions (rmux/tmux/cmux), input injection, screen capture, apps,
  displays, clipboard, volume, power, push, KB.
- **`mesh-input`** — Swift binary, macOS only. NDJSON on stdin → real HID events. Needs
  Accessibility.
- **iOS app** — polls every machine, relays snapshots to the watch, owns the machine
  list and tokens.
- **Watch app** — talks to meshd directly when it can, else via the phone.

## Where things live

| Path | What |
|---|---|
| `install/payload/meshd/` | **Canonical** meshd. `server.ts`, `input.ts` (Mac control), `push.ts` (APNs), `kb.ts`, `desktop.html` |
| `install/payload/bin/` | `mesh-input.swift`, `mesh` CLI, hooks |
| `install/install.sh` | The one-curl installer. Detects OS/arch/multiplexer |
| `Shared/` | `Models.swift` (wire types + pure helpers), `MeshClient.swift` |
| `iOS/`, `Watch/` | The two apps |
| `scripts/check-all.sh` | **The test suite.** Run this, not individual checks |
| `docs/mac-remote-control.md` | The whole control surface, API and gotchas |
| `~/.mesh/` | Deployed runtime: `meshd/`, `bin/`, `token`, `hosts.json`, `apns/` |

## Three meshd lineages have drifted — do not `cp` one over another

1. `meshd/` at the repo root — **stale**, predates cmux. Ignore it.
2. `install/payload/meshd/` — **canonical**, what ships.
3. `~/.mesh/meshd/` — deployed; carries another agent's `auth.ts` hardening and cmux
   caching that are not in the payload.

New meshd features go in their **own module** plus a two-line patch to `server.ts`
(an import and one route line), so the same patch applies to any lineage. `input.ts`
and `push.ts` both follow this.

## Things that cost hours to rediscover

- **Accessibility trust is per-binary and per-process-launch.** A helper run from a
  terminal inherits the terminal's grant and prints `trusted:true` while the launchd
  daemon is deaf. Only `curl .../input` against `:8899` tells the truth. Recompiling
  the helper voids the grant.
- **Swift strips `assert` under `-O`.** An optimised build of an assert-based check
  passes with a broken implementation. Always `sh scripts/check-all.sh` (`-Onone`).
- **Absolute cursor jumps must not carry a mouse delta.** The WindowServer re-derives
  position from it through pointer acceleration.
- **Tailscale silently degrades to a DERP relay** (~0.5s per round trip). Timeouts and
  request fan-out must survive that; a missed poll must not blank a machine.
- **A wildcard App ID cannot carry `aps-environment`.** Push needs an explicit App ID;
  a `clean build` with `-allowProvisioningUpdates` makes Xcode create one.
- **The watch has no Tailscale.** It reaches the mesh through the phone, and iOS
  suspends the phone app within seconds — so the watch must *ask* (sendMessage
  relaunches it), not wait to be told.
- **Build gate**: `xcodegen generate`, then both schemes for generic simulator
  destinations, then `scripts/check-all.sh`. Never commit red.

## Devices

Physical iPhone 15 Pro (iOS 27) and Apple Watch Series 9 (watchOS 27) are paired to
this Mac for development and can be installed to directly with `devicectl`. **Xcode 27
beta is required** (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`);
Xcode 26.6 only has the iOS 26.5 SDK and cannot deploy to these.

## Secrets

Never printed, never committed. Machine tokens live in `~/.mesh/token` and
`~/.mesh/hosts.json`; the APNs key in `~/.mesh/apns/AuthKey_<KID>.p8` (mode 600).
The iOS app stores its machine list in `mesh.machines.v1` in its UserDefaults.

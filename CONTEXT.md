# CONTEXT — MeshWatch

## Names (canonical, decided 2026-08-28)

- **MeshWatch** — the product and app. The only name that appears as an app name
  anywhere: App Store, TestFlight, home screen, landing page, README.
- **LeSearch AI** — the company/brand that publishes MeshWatch. Appears as
  "by LeSearch AI" in lockups, never as part of the app name itself.
- **"LeSearch Mesh"** — retired. Wherever it still appears, it is a rename not yet
  applied, not a second product.
- **meshd / mesh** — the daemon and CLI keep their lowercase technical names; they are
  components, not brands.

Read this first. Then `CHANGELOG.md` (what shipped, in a user's words), `PROGRESS.md`
(slice log), `docs/mac-remote-control.md` (the control surface), then `git log`.

## What this is

Control any machine you own from an Apple Watch and iPhone, over your own Tailscale
mesh. Local-first: no cloud relay anywhere in the path. The watch is the product; the
phone is the config surface and the relay of last resort.

Two loops, in priority order:

1. **Reach your machines from anywhere** — pointer, keyboard, screen, files, shell.
2. **Run agents 24/7 and answer them when they get stuck** — the notification, the
   live card and the complication all exist to make "an agent is waiting on you"
   reach your wrist and be answerable in one tap.

Loop 2 is the differentiator, and every surface derives from one shared function:
`sessionsNeedingAttention(from:)` in `Shared/Models.swift`. If you are adding a place
that shows "what needs me", read from that rather than inventing a second answer.

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
| `install/payload/meshd/` | **Canonical** meshd. `server.ts`, `auth.ts` (fail-closed bearer, constant-time), `doctor.ts` (GET /doctor, POST /doctor/fix), `input.ts` (Mac control), `push.ts` (APNs, one-buzz dedupe), `kb.ts`, `desktop.html` |
| `install/payload/bin/` | `mesh-input.swift`, `mesh` CLI, hooks |
| `install/install.sh` | The one-curl installer. Detects OS/arch/multiplexer |
| `Shared/` | `Models.swift` (wire types + pure helpers incl. pairing, attention, live-card selection), `MeshClient.swift`, `AgentNotifications.swift` (the notification-action contract), `SessionCard.swift` (SwiftUI status vocabulary), `SessionActivity.swift`, `WatchGlance.swift` (complication data + App Group) |
| `iOS/`, `Watch/` | The two apps |
| `MeshWatchWidgets/` | iOS widget extension — the Live Activity (Lock Screen, Dynamic Island, watch Smart Stack) |
| `WatchWidgets/` | watchOS widget extension — the face complication |
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
  the helper voids the grant. **TCC grants only prompt the process that needs them** —
  use `mesh doctor --fix` to trigger them from the daemon itself, not from a test script.
  Screencapture fails silently without a grant (no error, just a wallpaper image) — that
  is why `doctor.ts` exercises the real path instead of querying intentions.
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
- **A deleted App ID cannot be reused.** Apple answers "not available", which reads
  like a name clash. `…watchkitapp.complication` was burned this way; the target uses
  `…watchkitapp.glance`.
- **Anything shown in two places must come from one function.** The attention list,
  the live card and the complication are three renderings of
  `sessionsNeedingAttention`; the notification category string is grepped across
  Swift and TypeScript by `check-mesh-push.sh` for the same reason.
- **Browser attacks on loopback and DNS rebinding.** A page from another origin can
  attack `http://127.0.0.1:8899/` by sending a cross-site fetch with a spoofed Host
  header (DNS rebinding). `server.ts` rejects any request with an Origin header or a
  cross-site Sec-Fetch-Site before the loopback exemption, and validates the Host
  header against known Tailscale and local addresses — that gate runs before the auth
  check, so neither the token nor the IP exemption can bypass it.

## Devices

Physical iPhone 15 Pro (iOS 27) and Apple Watch Series 9 (watchOS 27) are paired to
this Mac for development and can be installed to directly with `devicectl`. **Xcode 27
beta is required** (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`);
Xcode 26.6 only has the iOS 26.5 SDK and cannot deploy to these.

## Onboarding (how anyone but you gets in)

1. `curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh`
2. `mesh pair` on that machine — prints an address and an 8-character code, 10 minutes,
   one use.
3. Phone → Machines → Pair. The daemon hands back its real token **and every host in
   its `hosts.json`**, so a fleet takes one code. The watch inherits over WatchConnectivity.

`/pair/claim` is the only route that answers without a token; see `meshd/pair.ts` for
why that is safe. No machines ship compiled into the app.

## Secrets

Never printed, never committed. Machine tokens live in `~/.mesh/token` and
`~/.mesh/hosts.json`; the APNs key in `~/.mesh/apns/AuthKey_<KID>.p8` (mode 600).
The iOS app stores its machine list in `mesh.machines.v1` in its UserDefaults.

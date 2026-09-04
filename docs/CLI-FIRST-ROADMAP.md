# CLI-first roadmap — mesh as the product

*2026-08-21. The decision doc for turning LeSearch Mesh's daemon+CLI into a standalone,
FOSS, reviewable product — the way `hermes` is a CLI with a TUI and desktop shell
around it, not an app with a CLI bolted on.*

## Stance

**CLI first.** `mesh` is the product surface: install, pair, doctor, upgrade, status
all happen there. The watch/phone apps, a future TUI, and a lightweight desktop app
are *clients* of the same daemon API. Anyone skeptical can read the daemon (bun +
TypeScript, ~10 files), run `mesh doctor`, and point their own agent at the code —
that reviewability is a feature, not a byproduct.

**No VNC dependency — ever.** We assume SSH exists; we do *not* assume VNC is enabled
or has a password. meshd already provides everything VNC would: `/screen.jpg`
(screencapture-based, per-display) + `/input` (CGEvent/xdotool injection) over
bearer-authed HTTP on the tailnet. VNC stays what it is today: an optional legacy
path for people who already run it. Setup never asks anyone to enable Screen Sharing.

**SSH is the bootstrap lane, not the runtime lane.** `mesh` uses SSH for the one-time
install on a remote box (`curl | sh` over ssh) and as the fallback transport for
`mesh upgrade` when a daemon is too old/dead to self-update. Runtime traffic is always
the daemon's HTTP API.

## Command surface (target)

Following the hermes shape — every verb is discoverable from `--help`, every state
question has a command:

| Command | Status | Notes |
|---|---|---|
| `mesh doctor [--fix]` | ✅ shipped 0.3.0 | setup truth; `--fix` pops macOS TCC dialogs |
| `mesh pair [--qr]` | code ✅ / QR new | QR = zero-typing pairing, second verification layer |
| `mesh upgrade [host]` | **new, P0** | atomic self-update; the fleet is stuck on 0.2.x because this doesn't exist |
| `mesh status` | new | one line per host: version, uptime, doctor summary |
| `mesh setup` | new | interactive wizard: install → token → service → pair → doctor |
| `mesh host add/list` | ✅ | |
| `mesh wake <host>` | new | Wake-on-LAN via a peer daemon on the same LAN |
| `mesh token rotate` | new | rotate `~/.mesh/token`, update peers, force re-pair |

## The user scenarios (TDD anchors)

Every scenario below gets a check under `scripts/` before its feature is called done.
These are the real ones, not invented personas:

1. **Leave the house while the machine boots.** Power the Mac/dataflow on, walk out,
   phone+watch pick it up with no ritual. → needs: daemon autostarts (✅ installer),
   *stable* online indication (no flapping), `mesh wake` / WoL from phone for a
   machine that shows offline. Check: `check-wol.sh` (magic-packet bytes),
   `check-connection-phase.swift` (✅ exists).
2. **Gym / outside: resume work in one minute.** Open watch → machine → running
   cmux/herdr session → read agent state → answer the waiting prompt. → needs: the
   agent-waiting notification to arrive **once** (not 30×), session list fast on
   cold open. Check: `check-mesh-push.sh` dedupe (✅), phone-side throttle check (new).
3. **One-handed approval while eating.** Trackpad mode: single tap = left click,
   double tap = right click, drag = move. Check: `check-trackpad-clicks.swift` (new).
4. **Spotlight/Raycast anywhere.** One button that sends ⌘-Space (or the Raycast
   hotkey) then types + enters. Already possible via `/input`; needs a first-class
   watch/phone button. Check: covered by input checks.
5. **Speak instead of type.** Watch push-to-talk → editable transcript → dispatch to
   agent stdin or Mac keystrokes. Spec: [VOICE-INPUT-SPEC.md](VOICE-INPUT-SPEC.md)
   (local-only ASR, bias-first vocabulary). Phase 1 = system dictation + review UI.
6. **Clipboard across devices.** Copy on iPhone → paste on Mac/dataflow, and back.
   `/clipboard` GET/POST exists (✅); needs UI affordances on phone/watch.
7. **Cold reality check.** `mesh status` from any terminal answers "what version is
   every box running and is anything broken" in one screen.

## Sequencing

1. **Stability + notification hygiene** (phone-side grace window + local throttle) —
   nothing else matters if the app cries wolf 30 times in 5 minutes.
2. **`mesh upgrade`** — the fleet is on 0.2.1/0.2.2 while 0.3.0 sits in git; every
   future fix is worthless without a deployment path. Then actually upgrade the fleet.
3. **Trackpad mode** (small, high daily value).
4. **QR pairing** (CLI renders, phone scans, still claims through `/pair/claim`).
5. **Voice phase 1** (dictation + review + dispatch; the heavy ASR lanes come per spec).
6. **WoL / wake**, `mesh status`, `mesh setup` wizard.
7. **TUI + desktop shell** — after the CLI surface is stable, not before.

## FOSS posture

- License: decide before public launch (daemon+CLI at minimum; likely the apps too).
- The repo must stay reviewable in one sitting: daemon is dependency-light bun code,
  every capability is one module + two-line `server.ts` patch, every claim has a
  `scripts/check-*.sh` that proves it without hardware.
- Agents are first-class users: `CONTEXT.md` / `MEMORY.md` / `index.md` keep any
  coding agent oriented without re-reading the tree.

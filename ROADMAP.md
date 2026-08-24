# Roadmap

Where LeSearch Mesh is going, in the order it is going there. Shipped work moves to
[`CHANGELOG.md`](CHANGELOG.md); this file only holds the future. Dates are guesses,
sequence is the commitment.

## Stance

**CLI-first.** `mesh` is the product surface — install, pair, doctor, upgrade, status
all happen there. The watch, phone and menu bar apps are *clients* of the same daemon
API, and anything else (a TUI, other platforms) can be too.

**Local-first, forever.** No relay, no account, and nothing of yours leaves your
machines. The daemon may send one anonymized heartbeat a day — version, platform,
coarse numeric counters, a random install id, nothing else — and
`MESHD_TELEMETRY=off` silences even that (see the Telemetry section of the README).
Anything on this roadmap that would require our server in the *data* path gets
redesigned until it doesn't.

**Reviewable in one sitting.** The daemon stays dependency-light Bun + TypeScript;
every capability is one module and a small `server.ts` patch; every claim gets a
`scripts/check-*` that proves it without hardware.

## Now — beta hardening (0.5)

- **APNs proven on real devices, end to end.** The signing path ships; delivery to a
  cold TestFlight device is the last unproven leg.
- **Live Activity push-to-start.** Today the Lock Screen card can only *start* while
  the app is foregrounded — from a cold pocket you get the notification but not the
  card.
- **iPhone polish.** A workspace-clean session list, better session cards, and adding
  a machine by hand that feels as good as pairing.
- **One daemon lineage.** The dev copy and the installer payload of `meshd` are
  reconciled into a single versioned source, so a fix lands everywhere or nowhere.

## Next

- **Native usage limits.** Read Claude Code and Codex usage straight from their own
  session files — no third-party dependency in the loop.
- **Voice, phase 2.** System dictation shipped; the spec in
  [`docs/VOICE-INPUT-SPEC.md`](docs/VOICE-INPUT-SPEC.md) moves the heavy local-ASR
  models to the Mac with a bias-first vocabulary, keeping the watch thin.
- **Linux parity.** Wayland input (X11 works today) and screen capture, so a Linux
  box is a first-class citizen rather than "input and files only".
- **App Store release.** TestFlight is the beta channel; a proper listing is the
  goal once the beta stops teaching us surprising things.

## Later

- **A TUI and cross-platform desktop client** around the same daemon API — after the
  CLI surface is stable, not before.
- **Per-agent isolation as a first-class flow.** One command that gives an agent its
  own Unix user with its own daemon, so a misbehaving agent can only wreck its own
  sandbox. (The Linux installer already supports `--user`; the apps should understand
  it.)
- **Android.** The daemon and its API are platform-neutral; the wrist-first client is
  not tied to one wrist.

## Non-goals

- **A cloud relay.** If your phone cannot reach your machine, neither can we — that
  is the design, not a limitation to fix.
- **VNC.** `meshd` already provides the screen and input surface over bearer-authed
  HTTP; setup will never ask you to enable Screen Sharing.
- **An account system.** Pairing is a code your own machine printed. That stays.

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

## Now — shipping (this blocks everything else)

Every item below is finished code that no user is running. Until these clear, building
more features adds nothing a person can touch, and no feedback can come back.

- ~~**Give `mesh.lesearch.ai` a DNS record.**~~ DONE (verified 2026-08-28): the CNAME
  resolves via public resolvers and `https://mesh.lesearch.ai/install.sh` answers 307 →
  the GitHub release asset. `scripts/check-links.sh` now guards it in CI, so a regression
  turns the suite red instead of rotting silently.
- **Submit the latest build for Beta App Review.** Uploading is not publishing: external
  testers — everyone holding the public link — only receive a build after review. The
  Aug 21 and Aug 24 builds are both sitting at `READY_FOR_BETA_SUBMISSION`, so the newest
  build a friend can install is from **20 Aug**. See [`docs/updating.md`](docs/updating.md).
  `mesh-install` **v0.5.0 is published** (27 Aug); machines update with `mesh upgrade`
  or a fresh curl of the GitHub release. Phones do not.

## Now — 0.6.x, from the first device test (2026-09-04)

The owner drove 0.6 from a real iPhone against a live Claude Code session and built a
habit tracker from the phone. Everything below is what that hour taught, in the order it
hurt. Shipped fixes are already in the changelog; this is what is left.

- **Terminal gestures and chords.** Swipe to switch pane/window, pinch to zoom, a D-pad
  with custom corners, and a chord builder (`C-b, S-t`) on the same key route the daemon
  already has. This is the gap a tmux user feels in the first minute; Moshi has it, we
  have a key row. See [`docs/compare-moshi.md`](docs/compare-moshi.md).
- **Hold-to-talk with a correction step.** On-device speech into the chat composer, the
  transcript shown for a fix before it is sent — long thoughts, spoken, without typing.
  The watch already dictates; the phone gets the same with review.
- **Model choice at launch.** A picker in the new-session sheet (`claude --model …`,
  Codex's equivalent), because "which model am I talking to" was the first question asked.
- **Mac permissions at setup, not mid-build.** Building and installing an app from the
  phone triggered macOS prompts (App Management, Accessibility) that only a person at the
  Mac can answer. `mesh setup` and `mesh doctor --fix` should surface every grant an
  agent will need, once, with a plain explanation of each.
- **Friendly app addresses.** Built web apps are served at the Mac's IP today; use the
  machine's `.local` name or MagicDNS so the URL a user adds to their Home Screen reads
  like a name, not an address.
- **What the agent is doing when the session looks idle.** Claude Code spawns background
  jobs and worktrees that the transcript only hints at; the chat should say "2 background
  jobs running" instead of looking asleep while tests loop out of sight.
- **Preferences that compound.** `app-brief` now writes `~/.mesh/app-preferences.md`;
  the next step is showing and editing that memory from the phone, and letting the
  interview draw on every app you have built.
- **Terminal legibility.** A phone-width terminal that does not require pinching to
  read a permission prompt: reader mode on the phone like the watch has, and the
  approval card rendered from the prompt text rather than the raw screen.

## Now — beta hardening (0.5)

- **APNs proven on real devices, end to end.** The signing path ships; delivery to a
  cold TestFlight device is the last unproven leg.
- **Live Activity push-to-start.** Today the Lock Screen card can only *start* while
  the app is foregrounded — from a cold pocket you get the notification but not the
  card.
- **iPhone polish.** A workspace-clean session list, better session cards, and adding
  a machine by hand that feels as good as pairing.
- **Answering an agent from the wrist.** A `PermissionRequest` hook is proven to fire,
  block, and have its verdict obeyed, and sessions are now keyed on the id the agent
  itself reports rather than a name the multiplexer owns. What is left is the daemon
  populating `Agent.sessionId` so the match can complete in production.
- **Resuming a rate-limited session.** Reading why Codex stopped and when its window
  resets is done and measured against a real stalled session. Delivering the resume — and
  the same for Claude Code — is not.

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

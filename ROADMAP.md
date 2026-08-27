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

- **Publish `mesh-install` v0.5.0.** The fleet installs whatever that repo last released,
  which is **v0.4.1 from 21 Aug**. Its `/health` has no `capabilities` field at all, so
  seven capabilities the apps call every day are answered by nothing — and it still ships
  the `lsof -ti :PORT | xargs kill -9` that SIGKILLs the daemon whenever an interactive
  shell starts. **Every new user currently installs a daemon that dies when they open a
  terminal.** The 0.5.0 payload is built and smoke-tested: 22 capabilities, daemon boots,
  `mesh version` agrees with it.
- **Give `mesh.lesearch.ai` a DNS record.** It has none. The install command in the
  README, on the website, and in the launch drafts cannot resolve for anybody — ten
  references across four files, all dead. One Cloudflare CNAME to `cname.vercel-dns.com`,
  DNS-only, fixes all ten. The site itself is already deployed and healthy at
  `lesearch-mesh-web.vercel.app`.
- **Submit the latest build for Beta App Review.** Uploading is not publishing: external
  testers — everyone holding the public link — only receive a build after review. The
  Aug 21 and Aug 24 builds are both sitting at `READY_FOR_BETA_SUBMISSION`, so the newest
  build a friend can install is from **20 Aug**. See [`docs/updating.md`](docs/updating.md).

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

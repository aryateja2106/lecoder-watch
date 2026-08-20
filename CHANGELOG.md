# Changelog

What changed, in the words a user would use. Newest first.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are
`MARKETING_VERSION` in `project.yml`; the build number after it is the UTC upload stamp.
**The `## [Unreleased]` block is the source for TestFlight "What to Test" notes** — write
each entry as you ship the slice, not at release time.

## [Unreleased]

## [0.2.0] — 2026-08-20

The release that makes the app installable by someone who is not its author, and turns
"an agent is waiting on you" into one tap on your wrist.

### Added
- **`mesh hooks install` — the thing that makes all of the above actually fire.** Every
  agent alert in this app starts with a hook an agent runs when it stops and waits for
  you, and nothing was registering one: the tools were installed and the events never
  came, which reads as "the app doesn't do that". The installer now wires it into
  Claude Code automatically, merging into your existing settings rather than replacing
  them, backing the file up first, and doing nothing on a re-run.
- **Alerts now name the session you can actually answer.** The hook reports the
  tmux/rmux session it is running inside; it used to fall back to the working
  directory, which produced an alert you could see and could not reply to.
- **A watch-face complication.** How many agents are waiting on you, on your face all
  day, in every accessory family (circular, corner, inline, rectangular) — plus the
  watch Smart Stack. When nothing is waiting it shows how much of your mesh is up. When
  the reading goes stale it says so rather than asserting a count from three hours ago.
- **"Needs you" is now the top of both apps.** Every agent across every machine that is
  stopped waiting on you, newest first, with **Continue** on the row. This is the list
  the product is for; it used to be buried under a machine list. A question you have
  since answered drops off by itself.
- **A live card for the session that needs you.** Lock Screen, Dynamic Island, and —
  on watchOS 11 and later — the watch Smart Stack, from one activity. It shows the
  agent, its state, the last line it printed, and CPU/memory; tapping it opens that
  session. Nothing is pinned by hand: the card follows whichever session is blocked or
  broken, falling back to the one you have open. A merely-busy session gets no card,
  because a permanent "Working" banner is wallpaper.
- **Answer a blocked agent from the notification.** When an agent stops and waits for
  you, the alert now carries three buttons on the wrist and the phone: **Continue**
  (Enter — accepts whatever the agent has highlighted, rather than guessing a "y"),
  **Reply** (dictate or scribble, sent as typed input), and **Stop** (ctrl-C). No app
  launch, no machine list, no session picker.
- **Blocked agents are time-sensitive**, so they pierce a Focus. A finished turn stays
  a normal alert with no buttons — typing Enter into a session nobody is waiting on is
  worse than staying quiet.
- Alerts from one session collapse into one thread.
- **Pairing.** Run `mesh pair` on a machine; it prints an address and an eight-character
  code good for ten minutes and one use. Enter those two on the phone and the machine
  hands over its real token — no 64-character bearer token typed on a phone keyboard.
- **Pairing one machine adopts the fleet.** The machine you paired already knows the
  rest from its `hosts.json`, so four boxes take one code. Loopback addresses in there
  are rewritten to the address your phone actually reached, because `127.0.0.1` is true
  for the daemon and useless for the phone.
- A first-run screen that explains the two steps instead of showing an empty list.

### Known limits
- The live card can only *start* while the app is open — an ActivityKit rule. From a
  pocket, the actionable notification is what reaches you and the card appears next
  time you open the app. Lifting this needs push-to-start.

### Changed
- **The Machines list no longer shows every machine twice.** It was a compact status
  row near the top and then a full diagnostics section below it, both saying "green".
  Now it is one row per machine; tap it for the diagnostics.
- **The app no longer prints your bearer token as a shell command to copy.** Three
  places did. Updating an agent uses the public installer, which keeps the existing
  token, and a rejected token now says "run `mesh pair` again" — which fixes it in
  place rather than asking you to paste a secret into a terminal.
- **The watch stops saying "Connecting…" forever** when nothing is paired. It says what
  to do instead.
- Adding a machine by hand no longer invents a random token that could only ever 401.
- **No machines ship with the app.** It used to seed three of the author's own tailnet
  addresses, which is a bug report for everyone else. The list starts empty and fills
  itself when you pair. (Existing installs keep everything they had saved.)
- Machine names are shown as-is; the old code stripped one particular person's naming
  prefix and mangled everyone else's.
- Pull to refresh on Machines.

### Fixed
- **Agent events graded `needs-input` or `finished` were being ignored.** Two
  vocabularies reach the event feed and only one was understood, so real alerts from
  some producers never reached the wrist. Both are accepted now, and a check compares
  the Swift and TypeScript lists so they cannot drift apart again.
- **Push would have died on its first TestFlight notification.** The app hardcoded the
  sandbox APNs environment, but a TestFlight build's device token is only valid at the
  production gateway — Apple answers `BadDeviceToken`, which meshd read as "this device
  is gone" and unregistered it permanently, silently, with nothing to see anywhere. The
  app now reads the environment out of its own embedded provisioning profile, and meshd
  tries the other gateway once before writing any device off.

## [0.1.0] — 2026-08-20 · build 202608201519

First TestFlight build. Installable by anyone on the team; the watch app ships inside it.

### Added
- **Control your Mac from the watch.** Trackpad with velocity-based pointer gain, tap to
  place the cursor, Digital Crown scroll (sideways toggle for horizontal), middle click,
  drag lock.
- **Every key, not just letters.** 48 letter/digit/punctuation keys plus F1–F12 and
  home/end/page, all honouring sticky modifiers — so `cmd-K` and `ctrl-C` are reachable.
  Dictation can produce words but never a chord.
- **Air mouse.** Point your arm, move the cursor (CoreMotion rotation rate, so it
  self-centres). Double Tap pinch clicks, on Series 9 and later.
- **Multi-display.** A chip per screen. Switching repoints preview, tap-to-place and
  window snapping together, so the screen you look at is the screen you drive.
- **Window snapping** — left/right/top/bottom/centre/full, and move a window to another
  display, via Accessibility (no extra permission, no helper app).
- **App switcher** — running apps first with a front-app dot, then everything installed.
- **Media, brightness and system power** — play/pause, next/prev, display and keyboard
  brightness, lock, screen saver, display sleep, sleep (two taps).
- **Clipboard** both ways, and volume.
- **Remote desktop without VNC** at `/desktop` — polls `/screen.jpg`, posts `/input`.
  No Screen Sharing toggle, no websockify, no sudo, multi-display for free.
- **File browser** at `/files` — filesystem only, so it is the one remote surface that
  works on a headless box.
- **Linux control** — the same `/input` contract via xdotool/xclip/pactl, so the watch
  drives any X11 machine. No client changes.
- **Push straight from your own machines.** APNs signed on the machine itself; agent
  events reach your wrist with no cloud relay in the path.
- **Haptics** on every landed action — the screen preview lags two seconds, so without
  them you cannot tell a click from a missed touch.
- App icon, and version + build stamp in Settings.

### Fixed
- **Machines reported offline when they were fine.** Tailscale had dropped to a DERP
  relay (~0.5s per round trip) against a 3s timeout with six sequential requests per
  machine. Timeout raised, panes fetched concurrently, and a missed poll now holds the
  last good reading as "last seen Xs ago" instead of blanking the row. This also
  un-disabled the New Session buttons, which is why sessions "could not be created".
- **First paint took 16 seconds** waiting on one long-offline host. Machines now publish
  as they answer.
- **The watch showed stale data** because it never asked the phone to refresh — it only
  rendered what the phone pushed before iOS suspended it. It asks now.
- **Every read failed off-tailnet**: the relay's reply handler was being discarded.
- **Preview taps landed in the wrong place** whenever the preview letterboxed.
- **The cursor drifted instead of landing** on absolute jumps — the WindowServer
  re-derives position from the mouse delta through pointer acceleration.
- **Display corners were a dead spot** — the exact corner sits on the seam between
  screens and the event is dropped. Target rects are inset 1pt.
- **iOS Local Network denial** now says so, instead of reporting every machine offline.

### Security
- Retired the shared `testtoken`; both live machines carry fresh 256-bit tokens and no
  token ships in the app.
- Auth is header-only off-box — `?token=` leaks into proxy logs and browser history.
  Loopback is exempt, judged from the socket peer address and never from a header.
- No restart or shutdown in `/system`: they kill every running agent session and a wrist
  tap is too cheap for that.

# Changelog

What changed, in the words a user would use. Newest first.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are
`MARKETING_VERSION` in `project.yml`; the build number after it is the UTC upload stamp.
**The `## [Unreleased]` block is the source for TestFlight "What to Test" notes** — write
each entry as you ship the slice, not at release time.

## [Unreleased]

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

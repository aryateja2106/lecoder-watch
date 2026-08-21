# Changelog

What changed, in the words a user would use. Newest first.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are
`MARKETING_VERSION` in `project.yml`; the build number after it is the UTC upload stamp.
**The `## [Unreleased]` block is the source for TestFlight "What to Test" notes** — write
each entry as you ship the slice, not at release time.

## [Unreleased]

The stability release: the app stops crying wolf, and the fleet stops running last
month's daemon.

### Fixed
- **"Online… offline… online" is over.** The flapping was manufactured on the phone —
  overlapping polls racing each other (a stale timed-out poll could overwrite a fresh
  green one with "offline") and a miss counter that could burn all three strikes in one
  refresh. Polls are single-flight now and a machine only reads offline after 45
  seconds of real silence. Opening the app polls immediately instead of showing
  whatever was true when iOS parked it.
- **The notification flood is capped by proof, not hope.** Thirty "went offline"/"back
  online" banners in five minutes is now arithmetically impossible: at most one
  offline/online pair per host per ten minutes, recovery only announced if the outage
  was, and identical agent alerts deduped for ten minutes — with a self-check that
  simulates the exact reported flap and demands exactly two banners.
- **Once the task is done, the notification vanishes.** An "agent waiting" banner used
  to sit on the Lock Screen long after the agent had finished, with the next alert for
  the same session stacking underneath it. Now each session owns exactly one banner —
  a later "Claude stopped" replaces "Claude needs attention" instead of piling on —
  and the moment the phone sees that nobody is waiting on that session any more, the
  banner is pulled down. Pushed and locally raised alerts share one identifier, so the
  sweep clears both, and an alert queued a second before the work ended never lands.

### Added
- **Know which machines are active and live, at a glance.** The Lock Screen card now
  carries the fleet count alongside the session that needs you — "2/3 machines online"
  — so the other half of the question ("is everything still up?") stops costing an app
  launch. It shows in the Dynamic Island's expanded view too.
- **A real trackpad mode.** A chip on the pad swaps the screen preview out for a
  full-height trackpad: tap to click, **tap-tap for right click** — built for
  approving something one-handed while the other hand holds lunch.
- **Dictate anywhere you could type.** One tap opens dictation in the Type sheet,
  agent replies and new tasks; the words land in an editable draft and nothing is sent
  until you confirm. (The full local-ASR plan lives in docs/VOICE-INPUT-SPEC.md — the
  watch lane turned out to have no Speech framework at all, so the system input is the
  on-watch path and the heavy models move to the Mac.)
- **Pair by QR.** `mesh pair` prints a scannable QR (vendored encoder — works even
  where qrencode isn't installed). Scan it with the iPhone's own Camera app: the pair
  sheet opens pre-filled, you confirm the code against the terminal and tap Pair. No
  in-app scanner, no camera permission.
- **Wake a machine that's gone dark.** Machines report their hardware MAC while awake;
  when one sleeps, its detail screen grows "Wake via <peer>" — any awake machine on
  the same LAN broadcasts the magic packet for it. Leave the house while it boots.
- **`mesh upgrade`** — the missing deployment path. Stages the new daemon, proves it
  runs on a throwaway port, swaps by rename, restarts the service, verifies the
  version, rolls back by rename if it doesn't answer. Your token, hosts, push
  registrations and KB are never touched; unchanged binaries keep their macOS
  Accessibility grant. `mesh upgrade -H host` upgrades a remote machine through a tmux
  session that survives the daemon restarting.
- **`mesh status`** — the whole fleet in one screen: version, uptime, doctor summary
  per host. Its first real run is why this release exists: every box was quietly two
  versions behind.

## [0.3.0] — 2026-08-20

The release about what happens when you actually press the button — and the first one
where driving your Mac from your phone is a real trackpad rather than a web page.

### Added
- **The affirmative now names what it will do.** "Continue" sends a bare Return, and
  Return accepts whichever option the agent has highlighted — so it was never
  "acknowledge", it was "yes", pressed by someone walking who read two lines at most.
  A question that would force-push, `rm -rf`, hard-reset, drop a table, pipe a download
  into a shell or run as root now gets a **red button naming the verb** — *Force push*,
  *Delete files* — and one line saying what happens. Everything else stays a calm
  Continue. The rule list is deliberately narrow: flagging everything trains you to
  skip the warning.
- **A live wait timer.** Every blocked agent shows how long it has been sitting there,
  counting up on the row, the Lock Screen card and the watch face. Six minutes of a
  machine doing nothing is the number this whole app exists to shrink.
- **Remote control you can actually aim.** Remote was a web view; now it is native, on
  both the phone and the watch, and it draws **its own pointer**. You cannot aim at a
  1512-point display rendered 390 points wide — the real cursor is two pixels — so
  seeing where you are about to click is the whole difference between a demo and a tool.
  - **Pinch to zoom, 1×–6×**, and the view follows the pointer, clamped at the edges, so
    there is nothing to pan and no way to lose the cursor. Finger travel is divided by
    zoom, so magnifying buys precision rather than just size.
  - **Landscape**, and the tab bar gets out of the way. A Mac display is about 1.54
    wide; a portrait phone was spending 60% of its glass on black bars.
  - **A real modifier row** — ⇧ ⌃ ⌥ ⌘ sticky until the next key, so ⌘⇧4 is two taps and
    a key — plus esc, tab, return, delete and arrows, explicit click and right-click,
    and double-tap for double-click.
  - One finger moves, two fingers scroll, two-finger tap right-clicks, press-and-hold
    drags. **Paste from iPhone** puts your phone's clipboard into whatever has focus on
    the Mac; **Copy from the machine** does the reverse.
  - On the watch: the same drawn cursor and zoom in the preview, which is where the
    aiming problem is worst. Tapping places the cursor exactly, through the zoom.
  - The picture is four times sharper — the old one was sized for a watch. meshd's web
    console is still there, one row down.
- **An honest all-clear.** The watch says "Nothing waiting on you" instead of rendering
  no section at all. An empty list and a dead poll used to look identical, which on a
  glance surface is the whole failure.

### Changed
- **The complication keeps the question.** With two agents waiting it used to say
  "2 agents waiting" over a bare session name — the only line you can act on vanished
  exactly when things got busy. Now it always shows three bands: how many, which one,
  and what it asked. A destructive question gets the warning glyph instead of the
  speech bubble.
- **Notifications are asked for after you pair a machine**, not on first launch. iOS
  shows that prompt exactly once ever; asking a stranger to accept alerts from an app
  that has nothing to alert them about yet spends the only chance this product gets.
- **The stale complication says "Tap to reconnect"** rather than naming the app you are
  already wearing a complication for.

### Fixed
- **The watch said "pair a machine" to people who already had.** When the watch had
  nothing to show it gave the one instruction guaranteed not to help, because an empty
  list looked the same as an unanswered phone. It now names which of the four things
  actually happened — iPhone unreachable, iPhone silent, iPhone paired to nothing, or
  still asking — offers a Retry, and carries a Link row saying whether the phone is
  answering and how many machines it sent.
- **The answer button was inside the row's tap target.** On the watch, Continue was a
  24pt control nested in a full-row `NavigationLink`; on iOS the same row had a tap
  gesture over the whole thing. Whichever gesture the system resolved a tap to, you
  could not tell by looking — and one of the two presses Return in a live shell. Both
  rows are rebuilt: the question is the payload, the actions are siblings of it, and
  the row navigates nowhere by itself.
- **Every timestamp from the daemon failed to parse.** `ISO8601DateFormatter` in its
  default configuration refuses fractional seconds, and meshd stamps events as
  `…:35.185Z`. The blocked-since timer rendered as nothing, and event times in Monitor
  rendered as empty strings, on both iOS and the watch. Every fixture in the repo was
  hand-written as `…:00Z`, so the checks were green throughout.
- A glance written by 0.2.0 would have failed to decode on upgrade and blanked the
  complication until the app next refreshed.

### Security and infrastructure
- **The daemon hardens against browser attacks.** A page from another origin cannot
  request `http://127.0.0.1:8899` by sending a cross-site fetch with a spoofed Host
  header (DNS rebinding). `meshd` now rejects any request with an Origin header or
  cross-site Sec-Fetch-Site (checked before the auth gate), and validates the Host
  header against known Tailscale and local addresses. The loopback exemption is safe —
  it can only be reached by a process on this machine or by a tool with the right token
  and tailnet address.
- **`mesh doctor` — test what the daemon can actually do.** Accessibility and
  Screen Recording are TCC grants that fail silently: clicks vanish, screenshots show
  only wallpaper. `GET /doctor` tests all systems without prompting; `POST /doctor/fix`
  shows the real macOS permission dialogs so the user gets a button instead of a
  Settings scavenger hunt. `mesh doctor [--fix]` on the CLI does the same. Capabilities
  are advertised on `/health` and the app gates its UI on them — Linux now says it has
  no screen capture instead of spinning on a screenshot that is never coming.
- **Bearer tokens are now fail-closed.** An empty `MESHD_TOKEN` used to mean "open";
  it now means loopback-only (header-only, matched with constant-time compare). A
  misconfigured unit file can no longer accidentally RCE. Tokens are stored mode 600
  in `~/.mesh/token` and `~/.mesh/hosts.json` (one per machine after pairing).
- **Push alerts dedupe on the question, not every state transition.** If the same title
  and body hit the same session and host within a 10-minute window, `shouldSend` drops
  the alert so a stuck agent buzzes once every 10 minutes, not an alert per state change.
- **Permissions are verified by exercising the real path.** `mesh-input.swift` now
  preflights Screen Recording with `CGPreflightScreenCaptureAccess()` before the daemon
  tries to use it, so a grant denial is caught early, not on first screencap.

### Known limits
- The Live Activity still has no buttons on the card, and can only be *started* while
  the app is in the foreground — from a cold pocket you get the notification but not
  the Lock Screen card.
- Screen capture is macOS only. Linux gets input, files and shell, and now says so
  instead of spinning on a picture that is never coming.
- APNs delivery to a real device is still unproven.

## [0.2.0] — 2026-08-20

The release that makes the app installable by someone who is not its author, and turns
"an agent is waiting on you" into one tap on your wrist.

### Added
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

- **`mesh hooks install` — the thing that makes all of the above actually fire.** Every
  agent alert in this app starts with a hook an agent runs when it stops and waits for
  you, and nothing was registering one: the tools were installed and the events never
  came, which reads as "the app doesn't do that". The installer now wires it into
  Claude Code automatically, merging into your existing settings rather than replacing
  them, backing the file up first, and doing nothing on a re-run.
- **Alerts now name the session you can actually answer.** The hook reports the
  tmux/rmux session it is running inside; it used to fall back to the working
  directory, which produced an alert you could see and could not reply to.

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
- **"Needs you" was empty on every Mac.** macOS reports its hostname with a `.local`
  suffix in the event, while the app stores the name pairing gave it, and the two were
  compared exactly — so a real blocked agent produced no row, no live card and no
  complication count. Caught by running the app against a live daemon, not by reading
  it. Every surface now matches host names the same way.
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

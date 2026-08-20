# PROGRESS — clean watch app that controls the whole Mac

Goal (2026-08-19, overnight): MeshWatch on the wrist drives the MacBook end to end —
pointer, keyboard, media, apps, windows, system — through `meshd`, with a UI worth
using daily. One slice at a time, full build gate, commit only when green.

## Done

- **Remote control core** — meshd 0.2.2 `/input` `/clipboard` `/volume`, Swift CGEvent
  helper, watch trackpad + crown + keys. Verified live on `:8899` (cursor, keys with
  modifier flags, pixel scroll, clipboard, volume). `64d5eb7`, `21c6166`.
- **On-device transport fixes** — route decided by the status probe, screen preview via
  the relay, volume/clipboard relayed, input never queued for late delivery. Installed
  and launched on the iPhone (iOS 27 / Xcode 27); tailnet counters confirm polling. `9dbb77b`.

- **S1 real credentials on the watch** — `MachineSnapshot.config` carries the phone's
  machine record (address, port, live token); the watch merges it, caches it in
  UserDefaults for cold start, and re-probes an open Control screen so a relayed session
  upgrades to direct in place. Both schemes build; self-checks pass.

- **S2 Control at the top level** — "Control <mac>" is now the first section of the
  machines list for any host advertising the `input` capability, instead of four taps
  deep. Both schemes build.

- **S3 media + system** — `{"t":"media"}` posts NX system-defined events (play/pause,
  next/prev, display + keyboard brightness); meshd `/system` allowlists lock, display
  sleep, screen saver and sleep. Watch Keys screen gained Media and System sections;
  Sleep Mac is two-tap. Verified on the live daemon: media events reach the HID stream
  (observed key=21/22 on a listen-only tap), allowlist rejects anything unnamed.

- **S4 relay reply path** — `WCSession.sendMessage`'s reply handler was being thrown
  away, so every *read* died whenever the watch was off the tailnet. `WatchLink.request`
  now awaits an answer (double-resume-safe under the timeout), the phone handler returns
  payload data, and clipboard read + input status work relayed. Enabler for the app list.

- **S5 app switcher** — meshd `/apps` lists running (via `lsappinfo`, so no Automation
  prompt on top of Accessibility) and installed apps; POST activates by name through
  `open -a` argv. Watch gained an Apps screen: running first with a front-app dot, then
  everything installed. Verified live — front went Claude → Finder, unknown app errors cleanly.

- **S6 window control** — `{"t":"window","place":…}` snaps the frontmost window via
  AXUIElement, which the Accessibility grant we already hold covers, so no extra
  permission and no helper app. left/right/top/bottom/center/full, position set before
  size so an edge-pinned window can grow. Verified against a real window: 99,33
  1349x897 → left 0,33 756x897 → right 756,33 → center 226,123 1058x718.
- **S7 haptics** — a click, drag-lock start/stop and every discrete action now tap the
  wrist. The screen preview is two seconds behind, so without it you cannot tell a
  landed click from a missed touch.
- **P0 phone tokens** — the phone had NO saved machine list, so it fell back to compiled
  defaults with `testtoken`, which meshd rotated away from on 2026-08-13: every host
  showed "token rejected". Wrote the real tokens from the Mac's `~/.mesh/hosts.json`
  into the app's UserDefaults over devicectl; verified they survive relaunch. ("timed
  out" in the relayed snapshot is just iOS suspending a backgrounded app, not a fault.)
- **S9a multi-display, Mac side** — `mesh-input --displays` enumerates the arrangement;
  `moveTo` and `window` take a 1-based display index matching `screencapture -D`;
  window snapping defaults to the display the window is already on. meshd gained
  `/displays` and `/screen.jpg?display=N`. Two fixes found by testing on the real
  two-screen setup: absolute jumps must not carry a delta (the WindowServer re-derives
  position from it through pointer acceleration, so the cursor drifted instead of
  landing), and the target rect is inset 1pt because the exact corner sits on the seam
  between displays and the event is dropped. Verified: every corner and centre exact on
  both screens; captures 480x311 and 480x270 confirm distinct displays.
- **S9b multi-display on the watch** — a chip per screen above the preview; switching
  repoints the preview, tap-to-place and window snapping together, so the screen you
  are looking at is the one you are driving. "Move window to <display>" per screen.
  The relayed path carries the display index too, so it works through the phone.
- **S10 complete mouse & keyboard** — middle click, horizontal scroll (crown-sideways
  toggle), and a full on-screen keyboard: 48 letter/digit/punctuation keys plus F1–F12
  and home/end/page keys, all honouring the sticky modifiers, so chords like ctrl-C and
  cmd-K are reachable — dictation can produce letters but never a chord. check-mesh-input
  validates all 63 key literals against the helper's keycode table. Verified live:
  dx=40, dy=-25 and middle button=2 observed on a listen-only tap.
- **S8 one Control hub** — the Keys screen had grown to eleven sections. Replaced with a
  hub (Quick chords · Apps · Keyboard · Windows · Media · System · Clipboard · Mouse),
  each its own short page, reached by one button on the trackpad screen. Quick row adds
  Spotlight, Mission Control, App windows, Screenshot, Show desktop, Force quit.
- **S11 tap mapping + a check suite that actually runs** — tap-to-place-cursor mapped
  against the container, not the drawn image, so every tap was wrong whenever the
  preview letterboxed (16:9 external screen in a 2.86 slot). Extracted the geometry to
  `normalizedPreviewPoint` and covered it. Then found the checks themselves were
  vacuous: Swift strips `assert` under `-O`, and a deliberately broken implementation
  still exited 0. `scripts/check-all.sh` compiles every Swift check with `-Onone` and
  runs the shell checks too — verified it goes red on a broken implementation.
- **S12 pointer feel + reconnect** — velocity-based gain (`pointerGain`), because one
  fixed multiplier cannot both cross a 3432pt two-screen arrangement and let you hit a
  close button; covered by `check-pointer-gain` for monotonicity, the ceiling, and
  reach. A relayed session now re-probes the direct path every 20s instead of staying
  slow for the rest of the session.

- **S12b CHANGELOG** — `CHANGELOG.md` now carries the user-facing history, and its
  `Unreleased` block is the source for TestFlight "What to Test" notes.
- **0.1.0 on TestFlight** — build `202608201519`, processingState VALID, watch app
  verified inside the IPA (8 entries under `Watch/`). Gotchas paid for: upload with the
  stable Xcode (a beta-built binary is accepted then fails processing with 90534), iPad
  in `TARGETED_DEVICE_FAMILY` demands all four orientations (90474), and
  `ITSAppUsesNonExemptEncryption` must be declared. See `docs/release-workflow.md`.

- **S13 pairing** — `mesh pair` mints a one-time code over loopback; the phone redeems
  it at `/pair/claim`, the one unauthenticated route, and gets the real token plus every
  host in that machine's `hosts.json`. `Machine.defaults` is gone, and with it the
  tombstone machinery that existed only to suppress it. Verified against a live daemon:
  minting is refused from the tailnet (403), a wrong code is refused, the right code
  works lowercase-with-a-dash and returns 3 hosts with 127.0.0.1 rewritten to the
  reachable address, replay is refused, five wrong guesses burn the code, and `/stats`
  still 401s without a token. `check-pairing` covers the merge — negative-tested: it
  goes red when address-identity is broken.

- **S16 actionable agent alerts** — `meshd` marks an event actionable when a session
  exists and `mesh-hook` graded it warning/error, and stamps the payload with the host,
  the `AGENT_ATTENTION` category and a per-session thread id. Both apps register the
  same category (`Shared/AgentNotifications.swift`), and both route the answer — the
  watch direct when it can reach the tailnet, else through the phone. The payload
  builder is pure and asserted, the action mapping is asserted, and the category string
  is grepped across both languages so it cannot drift silently. Host matching had to be
  tolerant: pairing stores `Aryas-MacBook-Pro`, its own events say
  `Aryas-MacBook-Pro.local`. Delivery to a device is still unproven — `devices:0` until
  the phone runs the app once.

## In the morning

1. Open **MeshWatch on the watch**. If it isn't there: iPhone → Watch app → My Watch →
   Available Apps → Install.
2. Tap **Control arya-macbook-pro** — the first row.
3. Display chips `1` `2` switch which screen you're driving. Tap the preview to place the
   cursor, drag the pad to nudge it, crown scrolls, `⋯` opens everything else.

If the trackpad says **"via phone"** that's the relay and it still works, just slower.
**"Needs Accessibility"** means the grant lapsed — the hub has *Ask the Mac now*.

## Next

Ordered by what stops a stranger using this. Everything above shipped for *one* user with
three hardcoded machines; none of it is reachable by anyone else.

**P0 — anyone can onboard**
1. ~~**S13 pairing.**~~ DONE — see Done.
2. **S14 QR pairing.** The code is typeable, but a camera scan of the `mesh://pair` URL
   `mesh pair` already emits is one step instead of two.

**P1 — the watch is the product**
3. **S15 watch widgets.** Smart Stack + watch-face complications: machines up, agents
   waiting on you. This is the reason to keep the app on the wrist.
4. ~~**S16 actionable notifications.**~~ DONE — see Done. Needs a device to prove
   delivery end to end.
5. **S17 Live Activity** — merge `MeshWatchWidgets` from `claude/eloquent-hopper-0a653d`.

**P2 — earned polish**
6. **S18 UI rework** — machines list duplicates the status list; quick commands are a
   fixed table.
7. **S19 SSH onboarding** — add a machine by address + credentials, run the installer
   over SSH.
8. **S20 Linux `/screen.jpg`** — input and files work headless; capture is Mac-only.
9. Rotate `arya-pi`'s token when it comes back online.

## Blockers

- **Watch dev tunnel unavailable.** `devicectl` could pair the watch but every
  connection was refused ("rejected the Bluetooth connection attempt"); an unpair/re-pair
  cycle then dropped it from discovery entirely and it has not come back, with the iPhone
  wired and Developer Mode on. Xcode's Devices window is the usual way to re-establish it.
  Until then, watch-side verification is the build gate plus a Mac-side CGEventTap probe,
  not on-watch logs — the app itself still reaches the watch embedded in the iPhone bundle.
- **The `~/.mesh/meshd/server.ts` patch is three lines in a file another agent owns.**
  `input.ts` and `mesh-input.swift` are standalone, but if that lineage is redeployed the
  import + route line go with it. Re-apply from `install/payload/meshd/server.ts`.

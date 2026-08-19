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

## Next

1. **S8 one Control hub** — the Keys screen has grown into a pile of eight sections.
   Split into Keys / Window / Media & System / Clipboard behind a short hub, and add
   quick actions (Spotlight, Mission Control, screenshot, Launchpad).
2. **S9 ship it** — rebuild signed, reinstall on the phone, refresh docs.

## Blockers

- **Watch dev tunnel unavailable.** `devicectl` pairs the watch but every connection is
  refused; an unpair/re-pair cycle dropped it from discovery entirely. Developer Mode is
  on. A background watcher retries every 30s. Until it returns, watch verification is
  build-gate + the Mac-side input probe, not on-watch logs. The app still reaches the
  watch embedded in the iPhone bundle.

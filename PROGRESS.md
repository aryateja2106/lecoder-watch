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

## Next

1. **S5 app switcher** — list running apps from meshd, focus/launch/quit by name.
2. **S6 window control** — snap left/right/full/centre for the frontmost window.
3. **S7 UI pass** — one coherent Control screen, not a pile of sections.

## Blockers

- **Watch dev tunnel unavailable.** `devicectl` pairs the watch but every connection is
  refused; an unpair/re-pair cycle dropped it from discovery entirely. Developer Mode is
  on. A background watcher retries every 30s. Until it returns, watch verification is
  build-gate + the Mac-side input probe, not on-watch logs. The app still reaches the
  watch embedded in the iPhone bundle.

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

## Next

1. **S2 Mac control at the top level** — Control is four taps deep (Machines → Sessions →
   Monitor → Control Mac). Put it on the machine row.
3. **S3 media + system keys** — play/pause, next/prev, brightness, lock, sleep display,
   Mission Control, Spotlight, screenshot.
4. **S4 app switcher** — list running apps from meshd, focus/launch/quit by name.
5. **S5 window control** — snap left/right/full/centre for the frontmost window.
6. **S6 UI pass** — one coherent Control screen, not a pile of sections.

## Blockers

- **Watch dev tunnel unavailable.** `devicectl` pairs the watch but every connection is
  refused; an unpair/re-pair cycle dropped it from discovery entirely. Developer Mode is
  on. A background watcher retries every 30s. Until it returns, watch verification is
  build-gate + the Mac-side input probe, not on-watch logs. The app still reaches the
  watch embedded in the iPhone bundle.

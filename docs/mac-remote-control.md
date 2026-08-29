# Controlling the Mac from the watch

LeSearch Mesh drives the MacBook end to end from the wrist: pointer, full keyboard, media,
apps, windows, system power — across every attached display.

```
Watch  RemoteView ──HTTP POST /input──▶ meshd ──stdin NDJSON──▶ mesh-input ──CGEvent──▶ macOS
  └── (off-tailnet) ──WCSession──▶ iPhone ──HTTP──┘
```

A watch app cannot inject input into macOS itself, and watchOS blocks low-level
networking (TN3135) — no `NWConnection`, no WebSocket. `URLSession` to meshd is the one
channel that works, and it is the channel Mesh already used.

## Pieces

| File | Role |
|---|---|
| `install/payload/bin/mesh-input.swift` | NDJSON on stdin → CGEvent / AXUIElement. Long-lived, so a drag streams. |
| `install/payload/meshd/input.ts` | `/input` `/clipboard` `/volume` `/system` `/apps` `/displays`. Builds and supervises the helper. |
| `Shared/MeshClient.swift` | Typed calls for all of the above. |
| `Watch/RemoteView.swift` | Trackpad, display picker, hub, keyboard, apps. |
| `scripts/check-mesh-input.sh` | Helper compiles; every key, media key, window place and system action the watch sends maps to something the Mac knows. |

`meshd/server.ts` only gains an import, one route line and the `input` capability —
deliberately small, because the repo, payload and deployed copies have drifted.

## Grant Accessibility (required, once)

Quartz **silently drops every event** until the helper binary is trusted.

```bash
curl -s -H "Authorization: Bearer $(cat ~/.mesh/token)" 'http://127.0.0.1:8899/input?prompt=1'
```

That prints `{"trusted":…,"helper":"…/.mesh/bin/mesh-input"}` and raises the macOS
dialog. Add that binary under **System Settings › Privacy & Security › Accessibility**.
The watch shows "Needs Accessibility" on the trackpad until it clears, and the hub has
an *Ask the Mac now* button.

Checking from a shell proves nothing: a binary run from a terminal inherits the
terminal's grant and reports `trusted:true` while the launchd daemon is still deaf.
Always check through `curl` against `:8899`. Recompiling the helper voids the grant;
meshd recycles the child process when a status check sees trust change.

Screen previews additionally need **Screen Recording** for meshd — already granted for
the launchd daemon, not for a meshd you start from a shell.

## API

```
GET  /input                 -> {ok, trusted, helper, hint}   ?prompt=1 raises the dialog
POST /input                 <- {"events":[…]}                max 200 per request
GET  /displays              -> {displays:[{index,x,y,width,height,main,name}]}
GET  /screen.jpg?display=N  -> JPEG of one display (no param: whole main screen)
GET  /apps                  -> {front, running:[{name,bundleID,front}], installed:[…]}
POST /apps                  <- {"activate":"Safari"}
GET|POST /clipboard         -> {text} / <- {text}
GET|POST /volume            <- {level:0-100} | {delta:±n} | {muted:bool}
POST /system                <- {"action":"lock"|"displaysleep"|"screensaver"|"sleep"}
```

Input events:

| Event | Meaning |
|---|---|
| `move{dx,dy}` | relative; becomes a drag while the button is held |
| `moveTo{x,y,display}` | absolute, normalized 0…1 within one display |
| `click{button,count}` | left / right / middle, 1–3 clicks |
| `down` / `up` | hold and release the left button (drag lock) |
| `scroll{dx,dy}` | pixel scroll, both axes |
| `key{key,mods}` | any keycode with cmd/shift/opt/ctrl/fn |
| `text{s}` | arbitrary Unicode, no keycode needed |
| `media{key}` | play/pause, next/prev, display and keyboard brightness |
| `window{place,display}` | snap frontmost window: left/right/top/bottom/center/full |

```bash
# nudge the cursor and click
curl -s -H "Authorization: Bearer $(cat ~/.mesh/token)" -H 'content-type: application/json' \
  -d '{"events":[{"t":"move","dx":60,"dy":40},{"t":"click"}]}' http://127.0.0.1:8899/input
```

## Multiple displays

Display indices are 1-based and shared with `screencapture -D` (1 = main), so a preview
and a `moveTo` always mean the same screen. The watch shows a chip per display above the
preview; switching repoints the preview, tap-to-place and window snapping together.
Window snapping with no display named stays on the display the window is already on.

Two things the second screen exposed, both fixed:

- **Absolute jumps must not carry a mouse delta.** The WindowServer re-derives position
  from the delta and runs it through pointer acceleration, so `moveTo` drifted toward
  the target instead of landing on it — invisible on one screen, obvious across a
  3432pt arrangement.
- **The exact corner of a display sits on the seam** with its neighbour and the event is
  dropped, so the target rect is inset by one point.

## Opening the desktop

From the Mac itself: **http://127.0.0.1:8899/desktop**. Loopback needs no token — a
process running as you on this machine can already read `~/.mesh/token` and run
anything, so demanding one from 127.0.0.1 protects nothing. Off-box requests are
unchanged: bearer header or 401.

Opening `desktop.html` as a `file://` path cannot work — its fetches have no server
and no token. It has to be served by meshd.

From the phone: the app's **Remote › Screen & control**, which sends the header.

## Watch UI

- **Control &lt;mac&gt;** is the first row of the machines list for any host advertising the
  `input` capability.
- Display chips (when >1) → preview → trackpad → `⋯` hub.
- Preview: **tap it to put the cursor exactly there**, refreshed every 2s.
- Trackpad: drag to move, tap to click, Digital Crown scrolls (sideways when toggled).
  Every action taps the wrist, because the preview is two seconds behind.
- Hub: quick chords (Spotlight, Mission Control, App windows, Screenshot, Show desktop,
  Force quit), Apps, Keyboard (incl. an every-key grid with sticky modifiers), Windows,
  Media & sound, System, Clipboard, mouse buttons.

## Transport

The watch talks to meshd directly when it can, and falls back to the iPhone otherwise.
`WCSession`'s reply handler carries answers back, so reads (clipboard, app list,
displays, permission status) work on both paths. Input is never queued for later
delivery when the phone is unreachable — a click arriving ten minutes late lands on
whatever is on screen then, so dropping it is the safe failure.

**Tokens.** The watch ships compiled-in defaults that go stale the moment a token is
rotated on the Mac; a 401 then silently demotes everything to the slow relay. The phone
now relays its own machine records (address, port, live token) in each snapshot and the
watch caches them. If the phone itself shows "token rejected", its stored token is wrong
— the Mac's real ones live in `~/.mesh/hosts.json`.

## Air mouse (the WowMouse approach)

WowMouse pairs a Wear OS watch as a Bluetooth **HID** mouse. watchOS gives third-party
apps no HID peripheral role, so that transport is closed on Apple Watch — but HID was
only its transport. The parts that matter port directly:

- **Pointing**: CoreMotion device motion at 50Hz, wrist yaw → x, pitch → y, mapped by
  `airMouseDelta` and sent over the network path instead of over HID. Rotation *rate*,
  not attitude, so the cursor self-centres when your arm stops.
- **Pinch to click**: Double Tap is bound as the scene's primary action, so the same
  index-finger-to-thumb gesture clicks. Native, Series 9 and later.

Sensitivity and deadzone are calibration knobs in `airMouseDelta`, covered by
`scripts/check-air-mouse.swift`.

## Deliberately not built

- **BLE/GATT transport.** URLSession over Tailscale already works and is proven here.
- **Privileged (`sudo`) daemon + XPC + proximity gate.** meshd can already run anything
  through a session; a root helper is a large new attack surface for no new capability.
- **Restart / shutdown.** They kill every running agent session, and a wrist tap is too
  cheap for that. Sleep is included but needs two taps.

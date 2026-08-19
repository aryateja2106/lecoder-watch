# Mac remote control from the watch

Drive the MacBook's cursor, keyboard, scroll, clipboard and volume from MeshWatch.
Watch → `meshd` over the tailnet (plain `URLSession`) → a Swift helper that posts real
HID events through Quartz Event Services.

```
Watch  RemoteView ──HTTP POST /input──▶ meshd ──stdin NDJSON──▶ mesh-input ──CGEvent──▶ macOS
  └── (off-tailnet) ──WCSession──▶ iPhone ──HTTP──┘
```

A watch app cannot inject input into macOS itself, and watchOS blocks low-level
networking (TN3135) — no `NWConnection`, no WebSocket. `URLSession` to meshd is the
one channel that just works, and it is the channel MeshWatch already uses.

## Pieces

| File | Role |
|---|---|
| `install/payload/bin/mesh-input.swift` | Reads NDJSON on stdin, posts CGEvents. Long-lived, so a drag streams. |
| `install/payload/meshd/input.ts` | `/input`, `/clipboard`, `/volume`. Builds + supervises the helper. |
| `Shared/MeshClient.swift` | `input(_:)`, `inputStatus()`, `clipboard()`, `volume()`. |
| `Watch/RemoteView.swift` | Screen preview, trackpad, crown scroll, keys, dictation. |
| `scripts/check-mesh-input.sh` | Helper compiles + every watch key name maps to a keycode. |

`meshd/server.ts` only gains an import, one route line, and the `input` capability —
deliberately small, because the repo, payload and deployed copies have drifted.

## Grant Accessibility (required, once)

Quartz **silently drops every event** until the helper binary is trusted.

```bash
curl -s -H "Authorization: Bearer $(cat ~/.mesh/token)" 'http://127.0.0.1:8899/input?prompt=1'
```

That prints `{"trusted":…,"helper":"/Users/you/.mesh/bin/mesh-input"}` and raises the
macOS dialog. Add that binary under **System Settings › Privacy & Security ›
Accessibility**. The watch shows "Needs Accessibility" on the trackpad until it clears,
and the Keys screen has an *Ask the Mac now* button that hits the same endpoint.

Recompiling the helper changes its signature, so re-approve it after a payload update.
meshd only rebuilds when `mesh-input.swift` is newer than the binary.

## API

```
GET  /input            -> {ok, trusted, helper, hint}      ?prompt=1 raises the TCC dialog
POST /input            <- {"events":[…]}                   max 200 per request
GET  /clipboard        -> {text}
POST /clipboard        <- {text}
GET|POST /volume       <- {level:0-100} | {delta:±n} | {muted:bool}
```

Events: `move{dx,dy}`, `moveTo{x,y}` (0…1 of the **main** display), `click{button,count}`,
`down`/`up` (drag lock), `scroll{dx,dy}`, `key{key,mods}`, `text{s}`.

```bash
# nudge the cursor and click
curl -s -H "Authorization: Bearer $(cat ~/.mesh/token)" -H 'content-type: application/json' \
  -d '{"events":[{"t":"move","dx":60,"dy":40},{"t":"click"}]}' http://127.0.0.1:8899/input
```

## Watch UI

- **Sessions › Monitor › Control Mac** (only on hosts advertising the `input` capability).
- Screen preview on top: **tap it to put the cursor exactly there**. Refreshes every 2s.
- Trackpad below: drag to move, tap to click. Digital Crown scrolls.
- Buttons: double-click, right-click, drag lock (hold the button down across moves),
  dictate/scribble text, and a Keys screen with arrows, ⌘-shortcuts, sticky modifiers,
  volume and the Mac clipboard.

Off the tailnet the watch falls back to the iPhone relay over WatchConnectivity and
throttles to 300ms — usable for clicks and keys, not for smooth dragging.

## Deliberately not built

- **BLE/GATT transport.** URLSession over Tailscale already works and is proven here.
- **Privileged (`sudo`) daemon + XPC + BLE proximity gate.** meshd can already run
  anything through a session; a root helper is a large new attack surface for no new
  capability. Add it only if the watch must run privileged commands with no session.
- **CoreMotion air-mouse.** The pad plus tap-the-preview covers pointing. ~15 lines in
  `RemoteView` if the wrist-tilt version is ever wanted.
- **Multi-display `moveTo`.** Normalized to the main display, which is what
  `screencapture` (and therefore the preview) shows. `CGGetActiveDisplayList` when needed.

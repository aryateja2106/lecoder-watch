# MEMORY — decisions and dead ends

Why things are the way they are. `CONTEXT.md` is the map; this is the reasoning, so
nobody re-litigates a settled call or re-walks a dead end.

## Settled decisions

**Transport is `URLSession` to meshd, not BLE.** watchOS blocks low-level networking
for normal apps (TN3135): no `NWConnection`, no WebSocket, no Bonjour. HTTP over
Tailscale is the one channel that works, and it already carried the rest of the app.

**Input injection is a long-lived Swift child, not a spawn per event.** A drag is
dozens of events; a process launch each would be all latency. meshd builds
`mesh-input` on demand and keeps it on stdin.

**New meshd capability = its own module + a two-line `server.ts` patch.** Three
lineages have drifted (see CONTEXT). Anything bigger creates a merge conflict for
whoever owns the other copy.

**Auth is header-only off-box; loopback is exempt.** A `?token=` leaks into proxy logs
and browser history — that hardening is deliberate, keep it. Loopback is exempt
because a process running as this user can already read `~/.mesh/token` and execute
anything; the exemption is judged from the socket peer address, never a header.

**No restart/shutdown in `/system`.** They kill every running agent session and a
wrist tap is too cheap for that. Sleep is included but needs two taps.

**No root helper / XPC / sudo daemon.** meshd can already run anything through a
session, so a privileged daemon is a large new attack surface for no new capability.

## Dead ends — do not retry

**WowMouse's approach cannot be copied literally.** It pairs the Wear OS watch as a
Bluetooth **HID** mouse. watchOS gives third-party apps no HID peripheral role. The
port is CoreMotion → `airMouseDelta` → the network path, plus Double Tap bound as the
scene's primary action for the pinch-click. Same result, different transport.

**noVNC/websockify is not the way to see a Mac screen here.** It needs a brew install
*plus* a Screen Sharing toggle behind the user's password. meshd already captures any
display and injects input, so `/desktop` is a page that polls one and posts the other
— no VNC server, no sudo, multi-display for free. `resolvedVNC` remains only for hosts
that genuinely run a bridge.

**Driving iOS by injected clicks through iPhone Mirroring does not work.** Pixel
hunting on a mirrored phone opened two wrong apps. Use `devicectl` for install and
launch, and ask the user for on-device taps.

**`?token=` for the desktop page.** Rejected — see auth above. The app injects
`window.MESH_TOKEN` at document start instead.

## Bugs that were not what they looked like

- **"Every machine offline"** was not a network fault. Tailscale had dropped to a DERP
  relay (~0.5s/round trip) and the phone fired 6+ sequential requests per machine
  against a 3s timeout. The knock-on: "can't create a session" — the New buttons are
  `disabled` while a machine reads unreachable. meshd was fine throughout.
- **"Token rejected" on every host** was the iOS app having *no* saved machine list, so
  it fell back to `Machine.defaults` and its compiled-in `testtoken`, which meshd had
  rotated away from. Real tokens are in `~/.mesh/hosts.json`.
- **"Watch shows stale data"** — the watch never asked the phone to refresh; it only
  rendered what the phone pushed before iOS suspended it.
- **Notification showed a generic icon** — the project had no asset catalog at all.

## Still open

- Watch/phone **UI/UX rework** — owner asked for it, then asked to check the
  reliability fix first. Known bad: Machines shows a duplicate-looking Status list;
  hosts and `testtoken` are compiled into `Machine.defaults`; quick commands are a
  fixed table.
- **Linux parity.** `mesh-input` is macOS-only (CGEvent/AXUIElement). Linux needs an
  equivalent (X11 XTEST or Wayland/uinput) plus capture, behind the same `/input`,
  `/screen.jpg`, `/displays` contract so no client changes.
- **SSH onboarding** — add a machine by IP + credentials, then run the installer over
  SSH so any box joins the mesh.
- **`testtoken` still ships** in `Models.swift` `Machine.defaults`, and it now grants
  keystroke injection. Rotate it.

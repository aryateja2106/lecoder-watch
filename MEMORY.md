# MEMORY — decisions and dead ends

Why things are the way they are. `CONTEXT.md` is the map; this is the reasoning, so
nobody re-litigates a settled call or re-walks a dead end.

## Settled decisions

**Onboarding is pairing, not configuration.** `mesh pair` mints an 8-character code
over loopback; the phone redeems it at `/pair/claim` — the one route that answers
without a token — and gets the real token plus every host in that machine's
`hosts.json`. No machines are compiled into the app. The claim window only exists for
the ten minutes after a human ran the command, it is single use, and five wrong
guesses burn it, which is why an unauthenticated route is acceptable here.

**Everything that shows "what needs me" reads one function.** `sessionsNeedingAttention`
in `Shared/Models.swift` feeds the watch home, the phone's Machines tab, the Live
Activity and the complication. A second answer to the same question is a bug waiting to
happen — the same reasoning makes `check-mesh-push.sh` grep the `AGENT_ATTENTION`
category string across Swift *and* TypeScript.

**Continue sends Enter, never a guessed "y" or "1".** Enter accepts whatever option the
agent has highlighted, which is exactly what pressing return at the terminal does.
Anything else is answering a question we cannot see, on someone's real machine.

**The complication degrades rather than lying.** It cannot poll, so it renders the
app's last reading and shows a dash past fifteen minutes. "2 agents waiting" from three
hours ago sends someone to their desk for nothing.

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

**Opening `desktop.html` as a `file://` path.** It has no server for its fetches and
no token, so it shows a broken image and "screen unavailable". It must be served by
meshd: `http://127.0.0.1:8899/desktop` locally, or the app's Remote tab off-box.

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

## 2026-08-20 (later) — pairing, actionable alerts, live card, complication

- **Push would have been dead on arrival in TestFlight.** The app registered
  `env: "dev"` unconditionally, but an archive signs `aps-environment` from the
  provisioning profile — `production` for TestFlight. A production token sent to the
  sandbox gateway returns `BadDeviceToken`, and `pushAlert` treated that as a dead
  device and deleted it: first push after install, push gone permanently, no error
  visible anywhere. Fixed both ends — `APNsEnvironment` parses the embedded profile,
  and meshd retries the other gateway once and remembers the answer before dropping a
  device. Found only by inspecting the signed entitlements of a probe archive.
- **A deleted App ID cannot be reused.** Apple answers "An App ID with Identifier … is
  not available", which reads like a name clash. `…watchkitapp.complication` is burned;
  the complication target uses `…watchkitapp.glance`.
- **Xcode creates and assigns App Groups by itself** once `APP_GROUPS` is enabled on
  the bundle IDs and the entitlement names the group — no portal visit, no API for it
  in `asc`. Verified in the signed entitlements of a Release archive.
- **`~/.mesh/hosts.json` records the Mac as `127.0.0.1`,** which is true for the daemon
  and useless for a phone. Pairing rewrites loopback entries to the address the client
  actually reached, and dedupes them against the self entry.
- **Removing `Machine.defaults` made the watch hang on "Connecting…"** — an empty list
  and an unanswered poll looked identical from there. Any "we have nothing" state needs
  to be distinguishable from "we do not know yet".
- The repo `install/payload/meshd/` lineage and the deployed `~/.mesh/meshd/` one both
  now carry `pair.ts` and the actionable `push.ts`, applied as module + two-line patch.
  Backups: `~/.mesh/meshd/*.pre-pair-*.bak`, `*.pre-actionable-*.bak`, `*.pre-envretry-*.bak`.

## The lesson from 2026-08-20, worth more than the code

**Two features shipped correct and dead.** The attention loop was built end to end —
hook, event, push, category, buttons, live card, complication, "Needs you" — and two
separate things meant no user would ever have seen any of it:

1. **Nothing registered the hook.** `mesh-hook` was installed by the installer and wired
   into nothing, so no event had been posted since 17 June.
2. **The host names never matched.** macOS puts `.local` on the hostname in the event;
   the app stores the name pairing gave it. An `==` comparison found no machine, so the
   list was always empty.

Both were invisible to the build gate and to a suite whose fixtures I wrote myself —
every one used matching names on both sides. Both were obvious within a minute of
running the app against the live daemon. **Run the thing.** A green build and a green
check suite say the code does what the code says; only running it says the product does
what the product claims. The same mistake in a different costume as
"verified on the wrong side of the boundary".

## Still open

- Watch/phone **UI/UX rework** — owner asked for it, then asked to check the
  reliability fix first. Known bad: Machines shows a duplicate-looking Status list;
  hosts and `testtoken` are compiled into `Machine.defaults`; quick commands are a
  fixed table.
- ~~**Linux parity.**~~ DONE 2026-08-20 (`feat/apns-push`, 0f497e5). `input-linux.ts`:
  pointer/click/drag/scroll/keys(cmd→ctrl)/text/media via xdotool, clipboard via
  xclip, volume via pactl, lock/displaysleep. `input.ts` dispatches per-platform, same
  `/input` contract — no client changes. Verified end-to-end on dataflowagents (POST
  /input moved the Xvfb pointer to exact coords). Still TODO: Linux `/screen.jpg`
  capture (Mac-only today) and Wayland (ydotool/uinput; xdotool is X11-only). Gotcha:
  bare Xvfb resets on last-client-disconnect — start with `-noreset`.
- **SSH onboarding** — add a machine by IP + credentials, then run the installer over
  SSH so any box joins the mesh.
- ~~**`testtoken` still ships**~~ — `Machine.defaults` is gone entirely; nothing ships
  with a token. (Still true and still a trap: dataflow's `~/.mesh/token` file reads
  `testtoken` while its systemd unit carries the real one — the daemon's token is the
  unit's `MESHD_TOKEN`, not the file.) `arya-pi` is offline and still on the old shared
  token; re-pair it when it returns.
- **Push-to-start for the Live Activity.** ActivityKit only starts an activity in the
  foreground, so the card appears from a pocket only after you next open the app.
  `Activity.pushToStartTokenUpdates` plus a `liveactivity` push from meshd lifts that.

## 2026-08-20 — reliability fix + APNs + Linux, verified

- **"Inconsistent connection" was the Mac sleeping** (Deep Idle on AC), not the mesh.
  Stopgap `caffeinate -s` live; permanent fix (user): `sudo pmset -c sleep 0`.
- **"Inconsistent alerts" was the polling model** (iOS suspends the app). Fixed: APNs
  pushed directly from each meshd on every `POST /events`. Key `7GD3G8AY4V` installed
  on macbook + dataflow (`~/.mesh/apns/`), both `configured:true`. `devices:0` until
  the iPhone app (rebuilt from this branch) launches once and uploads its token.
- ff-merged `claude/mesh-watch-mac-remote-a62154` → local `main`; work continues on
  `feat/apns-push`. Not pushed (policy: never push main).

## 2026-08-20 — remote desktop, file browser, air mouse

- **`/desktop`** — remote desktop assembled from `/screen.jpg` + `/input`. Verified:
  a click at normalized (0.5,0.5) put the real cursor at 756,491 on a 1512x982 screen.
- **Loopback exempt from bearer auth**, judged from `server.requestIP`, never a header.
  A local process can already read the token and exec anything. Verified the tailnet
  path still 401s without a token.
- **`/fs` + `/files`** — filesystem only, so it is the surface that works on a headless
  box. Verified on dataflowagents: listed `/home/arya`, descended, read `/etc/hostname`.
- **Air mouse + Double Tap** — the WowMouse idea minus its BT HID transport, which
  watchOS does not permit. CoreMotion rotation *rate* (self-centring), `airMouseDelta`
  holds the tuning knobs, `check-air-mouse` covers the curve.
- **Push was blocked by signing, not the key.** `configured:true` all along, but the
  app carried the XC Wildcard profile, which cannot hold `aps-environment`. A `clean
  build -allowProvisioningUpdates` created the explicit App ID and the entitlement is
  now in the signed app. `devices:0` persists only because the phone was locked, so
  the app could not launch to register.
- **"Every machine offline"** was Tailscale on a DERP relay (~0.5s/round trip) against
  a 3s timeout with 6+ sequential requests per machine — and it disabled every button,
  which is why sessions "could not be created". Timeout 8s, panes concurrent, and a
  missed poll now holds last-good for three polls as "last seen Xs ago".
- App icon added (there was no asset catalog at all — hence the generic notification
  glyph); Settings shows version + build timestamp read from the bundle.

## 2026-08-20 — token rotation, and two traps it exposed

- **Rotated both live machines** to fresh 256-bit tokens (macbook + dataflow), updated
  `~/.mesh/token`, `hosts.json`, the launchd plist and the systemd unit, and retired
  `testtoken` from `Machine.defaults`. `arya-pi` is offline and still carries the old
  shared token — rotate it when it comes back.
- **`launchctl kickstart -k` does NOT reload the plist environment.** launchd caches
  `EnvironmentVariables` from when the job was bootstrapped, so editing the plist and
  kickstarting silently keeps the old token. Use `launchctl bootout gui/$(id -u)/<label>`
  then `launchctl bootstrap gui/$(id -u) <plist>`.
- **The loopback exemption makes local `curl` useless for auth tests.** Every request
  from 127.0.0.1 is authorized regardless of token, so a rotation "verified" locally
  proves nothing. Always test against the tailnet address.
- **The systemd unit writes the token as `Environment="MESHD_TOKEN=…"` — quoted.** A
  sed anchored on `^Environment=MESHD_TOKEN=` matches nothing and reports success.
- **Writing the iOS app's UserDefaults must come *after* the install, not before.**
  An install following the write clobbers it. Kill app → write → read back to verify →
  launch.
- **`devicectl process launch` does not keep an iOS app running.** iOS suspends it as
  soon as it is not frontmost, so remote verification of polling behaviour is not
  possible — the tailnet byte counters stay flat and it looks like a network fault.
  iPhone Mirroring reports "iPhone in Use" when the owner is holding the phone.
  Foreground checks need the owner.

# Handoff — notifications rebuild + on-device screen testing

Written 2026-09-01 by the session that ran the device-capability research.
The next session should start here rather than re-deriving any of it.

## Why this exists

Two jobs, both too big for the session that scoped them:

1. **Notifications and Live Activities are not usable.** Multiple empty
   notifications per session, several stale Live Activities, and no way to
   approve from the iPhone notification. Arya's verdict: *"I genuinely don't
   see any point of having these kinds of notifications when they don't work."*
2. **There is no way to test the app's screens.** Wanted: walk every screen,
   perform actions, collect evaluations, catch the screens an agent silently
   broke while editing something else.

Run these with ultrathinking and dynamic workflows. Do not try to hold both
in one context.

---

## Verified facts about the device stack

All measured on this Mac, 2026-09-01. Do not re-test these; do not assume
anything beyond them.

### What works

| Capability | Command | Evidence |
|---|---|---|
| Screenshot, full native res | `xcrun devicectl device capture screenshot --device <id> --destination x.png` | 1179x2556, 3.2 MB, ~5.5 s over Wi-Fi |
| List installed apps | `devicectl device info apps --include-all-apps` | 259 apps, bundle ids, stable JSON |
| Launch any App Store app | `devicectl device process launch <bundle-id>` | verified on `ai.perplexity.app` |
| Device/lock state | `devicectl device info lockState` / `details` / `processes` | works |
| Mac screen recording | `rec start <name> [-d N]` then `rec stop` | 3024x1964, 120 fps |
| Frames for analysis | `rec frames <file.mov> [fps]` | ffmpeg, verified |

Device id: `AA729359-402F-563A-918F-F3867D85D8F7` (iPhone 15 Pro, iOS 27.0).

### What does NOT work — proven, stop trying

- **`devicectl` has no input.** No tap/swipe/type/press verbs. `HIDDigitizer`
  exists in `CoreDevice.framework` but is absent from the CLI binary. Xcode 26.6
  and Xcode 27 ship identical CoreDevice `636.3`.
- **`devicectl` has no UI/accessibility tree.** Zero hits across all 67 help
  texts, the CLI binary, and the framework.
- **Screen recording is refused by this device.** `Screen Recording` is absent
  from its 63 advertised capabilities. `Capture Screenshot` and `View Device
  Screen` are present. Untested over USB — the cable has never been connected
  during any of this work.
- **iPhone Mirroring exposes NO accessibility tree.** The whole tree is three
  nodes; the hosting view has zero children; hit-testing at five icon positions
  returns the same whole-window group. Even Apple's own "iPhone in Use" panel
  publishes nothing. Pixels only.
- **Competitor app files are unreadable.** `containerAccessible: false` on all
  186 App Store apps. Only the 3 developer-built apps are readable.
- **Instruments / `xctrace` cannot attach** to apps without `get-task-allow`.
- **libimobiledevice is broken** since iOS 17 and has been for three years.
- **Pinch is impossible via mirroring** — a mouse posts one contact point.

### The operational constraint that shapes everything

**iPhone Mirroring dies the moment the phone is picked up**, and stays dead
until the phone is locked again. Capture runs are unattended, phone-parked
work. Over Wi-Fi, `devicectl` capture ALSO fails while the phone is in use:

```
ERROR 4016: The device is not able to fulfill the requested usage assertion requirements
RequestedDeviceStates = powerAssertionTaken, remoteServiceDiscoveryTrustedConnectivityAvailable
```

**Test USB first.** The cable has never actually been plugged in
(`system_profiler SPUSBDataType` has shown 0 iPhones throughout). It may fix
both the capture-while-in-use failure and unlock screen recording.

### Not yet tested — the highest-value unknown

```sh
uvx pymobiledevice3 developer accessibility list-items
```

`pymobiledevice3` speaks `com.apple.accessibility.axAuditDaemon.remoteserver`,
the same protocol Xcode's Accessibility Inspector uses to inspect **any** app on
a connected device. No signing, no WDA, no sudo on iOS 27. If this returns real
labels, an agent can navigate by **text** and never pay for vision.

Caveat: it is a focus-walk, not a tree dump — focusable elements only, in
VoiceOver order, ~1 s each. Naturally compact, but thinner than WDA's tree.

Input still has no free route. Options: WebDriverAgent (Arya has a **paid**
Apple account, so 365-day profiles — the usual 7-day killer does not apply),
or Arya drives by hand.

---

## Confirmed root causes

### 1. Back-swipe on the remote screen — FIXED

`iOS/RemoteScreenView.swift`, `TrackpadSurface.Coordinator`. The delegate
returned `true` from `shouldRecognizeSimultaneouslyWith` for **every** other
recognizer, including `UINavigationController`'s `interactivePopGestureRecognizer`
(a left-edge pan — the same gesture as "move the pointer left"). Dragging left
moved the pointer and popped the screen simultaneously.

Fixed on branch `fix/remote-trackpad-back-swipe`, commit `8395a94`.
Builds clean (`xcodebuild` MeshWatch, iOS Simulator, exit 0).
**Not verified on device** — needs a real drag.

### 2. Notifications with no actions — STARTING POINT, not yet root-caused

Categories ARE registered correctly: `Shared/AgentNotifications.swift:106-143`
defines `attentionCategory` with approve / decline / stop actions, and
`registerCategories()` is called from both `iOS/NotificationManager.swift:101`
and `Watch/WatchNotifications.swift:32`.

The suspect: `iOS/NotificationManager.swift:633`

```swift
if let category { content.categoryIdentifier = category }
```

`category` is **optional**. Any sender that passes `nil` produces a notification
with no actions — exactly the actionless, empty notifications being reported.
**Start by auditing every call site of that function** and finding which paths
omit the category.

### 3. Live Activity pile-up — STARTING POINT

`iOS/LiveActivityController.swift:77-82` already keeps the first activity and
ends the rest. Arya reports 5-7 simultaneous stale activities, so either that
path does not run, activities are requested elsewhere, or the reconciliation
happens at the wrong moment. `Activity.request` is at line 235.

---

## The design question worth answering before writing code

Arya's own framing: *"ours is still not a drop-in replacement for Claude.
Claude is still better. It asks me accurately."*

Push notifications and Live Activities are currently **redundant** — the same
event arrives twice, and neither is actionable. Decide what each surface is
FOR before rebuilding either:

- One notification per event that needs an answer, carrying its actions.
- Live Activity for **state you watch**, not events you answer.
- Nothing at all for events that need neither.

Fewer, actionable, deduplicated beats more.

---

## Tooling built for this work

| Tool | Purpose |
|---|---|
| `rec start/stop/frames` | Record the Mac screen, extract stills. Arya demonstrates a bug instead of describing it. Recordings in `~/recordings`. |
| `sess` | tmux-backed agent sessions on an isolated socket. |
| `htab` / `hrun` | Open a real, visible herdr tab and run commands in it. |
| `herdr agent wait` | Blocks until an agent changes state — better than sleep-and-poll. |

## Repo hazards

- **`.claude/scripts/gates.sh` does not exist**, though `CLAUDE.md` documents it
  as the required gate. Last seen in commit `cc81c8c`. The documented
  verification path is dead.
- Never merge, never push `main` (`CLAUDE.md` rule 1, plus a blocking hook).
- Landing-page WIP is checkpointed on `backup/2026-08-31` (`8fde192`), not main.

# Installing to a real iPhone / Apple Watch, and pulling evidence back off it

The proven cable flow for Arya's physical devices — iPhone 15 Pro and Apple Watch Series 9,
both on OS 27. No Xcode UI required for any of this except the one-time Developer Mode
dance (see the bottom of this file and
[XCODE-WATCH-DEVICE-RUNBOOK.md](../XCODE-WATCH-DEVICE-RUNBOOK.md)).

**These devices need the Xcode 27 beta, not stable.** Stable Xcode (26.6) only carries the
26.5 SDK and cannot deploy to a device running OS 27 at all — see
[xcode-cli.md](xcode-cli.md).

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

## 1. Find the device and confirm it is actually reachable

```sh
xcrun devicectl list devices
```

Read the **state** column, not just presence in the list:

- `available (paired)` — connected (cable or Wi-Fi sync), unlocked, trusted. You can build
  and install to it.
- `unavailable (paired)` — known and previously trusted, but currently unplugged or
  locked. Reconnect the cable / wake and unlock the device, then re-run the list.
- Not listed at all — never trusted this Mac, or Developer Mode is off. See the checklist
  at the bottom of this file.

Copy the UDID out of a device in `available (paired)` state before continuing.

## 2. Build for that specific device

```sh
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch \
  -destination "platform=iOS,id=$UDID" -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData build
```

Or, without a UDID in hand yet, the generic device destination catches signing problems
early but cannot install or launch anything on its own:

```sh
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData build
```

`xcodegen generate` first if `project.yml` changed — see [xcode-cli.md](xcode-cli.md).

The built app lands under `build/DerivedData/Build/Products/Debug-iphoneos/MeshWatch.app`
(device builds use the `-iphoneos` product dir, not `-iphonesimulator`).

## 3. Install and launch

```sh
xcrun devicectl device install app --device "$UDID" \
  build/DerivedData/Build/Products/Debug-iphoneos/MeshWatch.app

xcrun devicectl device process launch --device "$UDID" com.lecoder.meshwatch
```

**`devicectl process launch` does not keep an iOS app running for you.** iOS suspends any
app that is not frontmost, so this is good for "does it launch and survive presenting its
first screen" but cannot be used to observe background behavior (polling intervals,
WatchConnectivity handoffs) remotely — that needs the app held in the foreground by a
person holding the device. Don't read a suspended app's flat network counters as a bug;
it's the OS doing its job.

**The watch app does not install this way.** `MeshWatch Watch App` is embedded in
`MeshWatch` (`embed: true` in `project.yml`) and ships to the paired watch through the
normal companion-app install path, not a direct `devicectl install` targeting the watch's
own UDID. If it doesn't appear on the watch after installing the phone app: iPhone → Watch
app → scroll to **Available Apps** → **Install**. If Developer Mode is stuck on the watch
before any of this, see the checklist in
[XCODE-WATCH-DEVICE-RUNBOOK.md](../XCODE-WATCH-DEVICE-RUNBOOK.md) — that failure mode is
device trust and OS-version support, not app code, and no amount of rebuilding fixes it.

## 4. Pull evidence back off the device — no Xcode UI, no user needed

### Crash logs

```sh
xcrun devicectl device copy from --device "$UDID" \
  --domain-type systemCrashLogs --source . --destination /tmp/crashlogs
```

This is **slow** — it pulls hundreds of system logs, not just yours. App crashes are named
`<AppName>-<date>.ips` (e.g. `LeSearch Mesh-2026-08-27-160512.ips`); filter for that
pattern rather than reading the whole pull.

An `.ips` file is **two JSON documents separated by a newline**. The second document's
`lastExceptionBacktrace` is where an Objective-C `throw` names itself — this is the field
that actually told us `UITextField.appearance()...` was the crash (see the story in
[README.md](README.md) rule 1). `exception.type` alone (`EXC_CRASH`, `SIGABRT`) says
nothing useful on its own; always read past it into `lastExceptionBacktrace`.

### App prefs / container contents

```sh
xcrun devicectl device copy from --device "$UDID" \
  --domain-type appDataContainer --domain-identifier com.lecoder.meshwatch \
  --source Library/Preferences --destination /tmp/prefs
```

Swap `--source` for other relative paths inside the app's container as needed
(`Documents`, `Library/Application Support`, etc.) — `Library/Preferences` is what you want
for `UserDefaults`-backed state.

### A screenshot of the physical device

```sh
xcrun devicectl device capture --device "$UDID" --output /tmp/device.png
```

The iOS-Simulator MCP screenshot tool is **simulator-only** and needs an interactive grant
in this environment; it cannot see a physical device. Use `devicectl device capture`
instead for anything on real hardware.

## If the device never gets to `available (paired)`

That is a **trust / Developer Mode / OS-support** problem, not something a rebuild fixes.
Full checklist — reboot order, Developer Mode toggles on both iPhone and Watch, storage
headroom, pending watchOS updates — lives in
[XCODE-WATCH-DEVICE-RUNBOOK.md](../XCODE-WATCH-DEVICE-RUNBOOK.md). Do not spend time
iterating on the build while the device itself is untrusted; fix trust first, confirm with
`xcrun devicectl list devices` showing `available (paired)`, then come back here.

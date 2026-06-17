# Xcode + real Apple Watch runbook

This captures current signing/device issues and the likely fixes. Use this before trying to run MeshWatch on Arya's physical watch.

## Current observed environment

Verified from terminal:

```text
Xcode 26.5
Build version 17F42
macOS 26.5.1 build 25F80
```

Project configuration currently has:

```yaml
DEVELOPMENT_TEAM: ""
CODE_SIGN_STYLE: Automatic
PRODUCT_BUNDLE_IDENTIFIER: com.lecoder.meshwatch
PRODUCT_BUNDLE_IDENTIFIER: com.lecoder.meshwatch.watchkitapp
```

Screenshot evidence:

- Xcode UI shows Team = `Arya Teja Rudraraju` for the iOS target.
- Project navigator shows `TerminalView.swift` and `WatchViews.swift` modified.
- Xcode Cloud prompt says project has no remote repository.
- Device run got stuck around checking Developer Mode on Apple Watch.
- Watch settings show accessibility features enabled, including Control Nearby Devices and Touch Accommodations.

## Likely signing reset root cause

The project is generated from `project.yml` using XcodeGen. Manual Xcode signing selections can be overwritten whenever `xcodegen generate` runs because `project.yml` has:

```yaml
DEVELOPMENT_TEAM: ""
```

Fix by editing `project.yml`, not only Xcode UI. The repo has a helper:

```bash
scripts/set-development-team.sh <ARYA_TEAM_ID>
```

It updates `project.yml` and runs `xcodegen generate` when XcodeGen is installed.

Recommended durable change:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: <ARYA_TEAM_ID>
    CODE_SIGN_STYLE: Automatic
```

Also ensure both targets inherit the team:

```yaml
MeshWatch:
  PRODUCT_BUNDLE_IDENTIFIER: com.lecoder.meshwatch
MeshWatch Watch App:
  PRODUCT_BUNDLE_IDENTIFIER: com.lecoder.meshwatch.watchkitapp
```

Do not do this blindly: first confirm the Team ID from Xcode account settings or `xcodebuild -showBuildSettings` after Xcode has selected the team.

## Xcode Cloud prompt is not required

The prompt saying:

> The project “MeshWatch” does not have a remote repository.

is for Xcode Cloud workflows. It is not required to build/run locally on iPhone/watch.

Ignore Xcode Cloud until the local device loop works.

## Physical watch Developer Mode checklist

Before debugging code, verify hardware/device state:

1. iPhone and Apple Watch are paired to each other.
2. iPhone is unlocked and trusted by the Mac.
3. Apple Watch is unlocked and on wrist if possible.
4. Apple Watch has Developer Mode enabled.
5. iPhone has Developer Mode enabled.
6. Apple Watch and iPhone OS versions are compatible with installed Xcode.
7. Xcode has required device support for the watchOS beta version.
8. Watch has enough storage; Arya observed roughly 30 GB free.
9. Watch update is pending and asks for power; install update if developer mode remains stuck.
10. Reboot iPhone, Watch, and Mac after enabling Developer Mode or installing updates.

## If Xcode says “Checking Developer Mode...” forever

Try in this order:

1. Install the pending watchOS update while connected to power.
2. Reboot Apple Watch after update.
3. Reboot iPhone after update.
4. Reboot Mac or restart Xcode.
5. Open Xcode → Window → Devices and Simulators.
6. Select the paired iPhone/watch and wait for indexing/preparation.
7. Delete MeshWatch from iPhone and Watch.
8. Re-run from Xcode with the iOS app scheme first.
9. If still blocked, disable/re-enable Developer Mode on iPhone and Watch, then reboot both.
10. If on developer beta and Xcode stable lacks support, either update Xcode beta or move devices to compatible public beta/stable.

## Useful commands for the next debugging agent

List attached/known devices:

```bash
xcrun devicectl list devices
xcrun xctrace list devices
xcodebuild -showdestinations -project MeshWatch.xcodeproj -scheme MeshWatch
xcodebuild -showdestinations -project MeshWatch.xcodeproj -scheme "MeshWatch Watch App"
```

Show signing settings:

```bash
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch -showBuildSettings | grep -E 'DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_STYLE|PROVISIONING_PROFILE'
xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch Watch App" -showBuildSettings | grep -E 'DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_STYLE|PROVISIONING_PROFILE'
```

Simulator builds that passed:

```bash
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
xcodebuild -project MeshWatch.xcodeproj -scheme 'MeshWatch Watch App' -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData build
```

## Build gotchas already learned

- Build via scheme + destination, not raw `-sdk iphonesimulator`.
- XcodeGen can reset signing if `project.yml` does not contain team settings.
- Xcode Cloud remote repository setup is unrelated to local watch run.
- Physical watch failures may be device trust / developer mode / OS support, not Swift code.
- WatchConnectivity errors in simulator are not always meaningful for physical paired devices.

## Recommended next debugging target

After Arya finishes the watchOS update, run:

```bash
xcrun devicectl list devices
xcodebuild -showdestinations -project MeshWatch.xcodeproj -scheme MeshWatch
xcodebuild -showdestinations -project MeshWatch.xcodeproj -scheme "MeshWatch Watch App"
```

Then capture the exact physical watch destination ID and exact Xcode error. Do not guess from simulator behavior.

# MeshWatch Agent Notes

## Source Of Truth

- `project.yml` is the canonical Xcode project definition.
- Run `xcodegen generate` when `project.yml` changes or `MeshWatch.xcodeproj` drifts.
- Do not preserve stale `MeshWatchWidgets` or UI-test targets unless their sources are added back to `project.yml`.
- Keep the Watch deployment target low enough for the physical paired Watch; `watchOS: "10.0"` is the current compatibility floor for the current SwiftUI navigation/toolbars.

## Build Checks

```sh
xcodegen generate
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
xcodebuild -project MeshWatch.xcodeproj -scheme 'MeshWatch Watch App' -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData build
```

## Physical Device Checks

```sh
xcrun devicectl list devices
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch -showdestinations
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch -destination 'id=00008130-000C78E20EC0001C' -derivedDataPath build/DeviceDerivedData build
xcrun devicectl device install app --device AA729359-402F-563A-918F-F3867D85D8F7 build/DeviceDerivedData/Build/Products/Debug-iphoneos/MeshWatch.app
xcrun devicectl device process launch --device AA729359-402F-563A-918F-F3867D85D8F7 com.lecoder.meshwatch
```

Physical launch requires the iPhone to be unlocked. Direct Watch install may fail if the paired Watch rejects the debug/pairing channel; install through the companion iPhone first.

If `xcodebuild -showdestinations` reports the physical Watch with a blank watchOS version or `RemotePairingError 1035`, lowering the deployment target is not enough. Unlock the iPhone, connect the companion phone directly to the Mac, and re-pair/re-trust the Watch debug channel in Xcode/devicectl.

## Runtime Checks

```sh
curl -fsS -H 'Authorization: Bearer testtoken' http://100.94.221.115:8899/health
curl -fsS -H 'Authorization: Bearer testtoken' http://100.94.221.115:8899/agents
curl -fsS -H 'Authorization: Bearer testtoken' http://100.94.221.115:8899/usage
curl -fsS -H 'Authorization: Bearer testtoken' http://100.94.221.115:8899/screen.jpg --output /tmp/mesh-screen.jpg
curl -fsS http://100.94.221.115:7820/ >/dev/null
```

The macOS LaunchAgent for `meshd` must run as `ProcessType=Interactive`; `screen.jpg` can fail from a background agent even when the same code works in a terminal.

## Product Shape

- Watch is a glance-and-intervene surface: status, output preview, command deck, dictation, and separated danger controls.
- iPhone remains the full terminal/VNC surface.
- Keep telemetry local-first: OpenUsage local API first, old cache fallback second.

# MeshWatch Agent Notes

## Source Of Truth

- `project.yml` is the canonical Xcode project definition.
- Run `xcodegen generate` when `project.yml` changes or `MeshWatch.xcodeproj` drifts.
- Do not preserve stale `MeshWatchWidgets` or UI-test targets unless their sources are added back to `project.yml`.

## Build Checks

```sh
xcodegen generate
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
xcodebuild -project MeshWatch.xcodeproj -scheme 'MeshWatch Watch App' -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData build
```

## Runtime Checks

```sh
curl -fsS -H 'Authorization: Bearer testtoken' http://100.94.221.115:8899/health
curl -fsS -H 'Authorization: Bearer testtoken' http://100.94.221.115:8899/agents
curl -fsS -H 'Authorization: Bearer testtoken' http://100.94.221.115:8899/usage
curl -fsS -H 'Authorization: Bearer testtoken' http://100.94.221.115:8899/screen.jpg --output /tmp/mesh-screen.jpg
curl -fsS http://100.94.221.115:7820/ >/dev/null
```

## Product Shape

- Watch is a glance-and-intervene surface: status, output preview, command deck, dictation, and separated danger controls.
- iPhone remains the full terminal/VNC surface.
- Keep telemetry local-first: OpenUsage local API first, old cache fallback second.

# iOS/ — the iPhone app: your machine list, terminals, remote screen, pairing, and the relay that carries the watch's requests to your machines

**Read first:** `docs/agents/CODEMAP.md` § `iOS/` (which file, which check) · `docs/agents/UI-MAP.md` § iPhone (screen → file:line → routes) · `iOS/MeshStore.swift` (the one store every view calls)
**Surface:** phone
**Serialized (one agent at a time):** `PairMachineView.swift`, `PairingScanner.swift`, token storage in `MeshStore.swift` (pairing/tokens, AGENTS.md:239); `MeshStore.swift` `handle(_:)` (`MeshStore.swift:1075`) moves in lockstep with `WatchCommand` in serialized `Shared/Models.swift`. Views in one file are parallel-safe (AGENTS.md:228).
**Prove a change:**
- `./.claude/scripts/gates.sh fast` (under a minute; does not compile the app)
- `xcodegen generate && xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build` (AGENTS.md:139)
- the file's own checks from CODEMAP's *checks* column, e.g. `sh scripts/check-native-terminal-keys.sh`, `sh scripts/check-remote-screen-gestures.sh`, `sh scripts/check-relay-receiver.sh`
- launch proof: `sh scripts/check-ios-smoke.sh` (minutes, runs `xcodebuild test`; skips with exit 0 when no iOS 26+ simulator unless `MESH_SMOKE_REQUIRED=1`)
- a real daemon on a side port (AGENTS.md rule 5), then the screen; mic, camera, Face ID, push banners need Arya's iPhone (AGENTS.md:261)

**Traps:**
- The smoke test finds tabs and buttons by their visible text (`UITests/SmokeTests.swift:36`, `:85`): renaming "Machines", "Terminal", "Apps", "Settings" or "Pair a machine" turns `check-ios-smoke.sh` red.
- Tabs are Machines, Terminal, Apps, Settings (`ContentView.swift:16`, `:26-29`); Monitor is the bell. `docs/product/PRODUCT.md:223` still says five tabs incl. Monitor and Remote — trust the code.
- Session deep links need exactly two path parts (`MeshStore.swift:1068`); a session name containing `/` is silently ignored (unverified at runtime; see `MeshWatchWidgets/AGENTS.md`).
- Build clients with `MeshStore.client(for:)`, not a bare `MeshClient`, so daemon capabilities travel (UI-MAP "Add an iPhone screen"); an old daemon answers 200 with the old shape (AGENTS.md rule 6).
- Every file's first comment line is its CODEMAP purpose; `scripts/check-codemap.sh` goes red when the map is stale — run `python3 scripts/codemap-index.py` after adding a file.
- `MeshWatch.entitlements` declares only `aps-environment` = development (`MeshWatch.entitlements:5-6`); a new capability needs `sh scripts/check-entitlements.sh` and `project.yml` (serialized).

**SDLC stage:** Build, Test — the shipping phone client; most features land here and are proven through its launch test (see [docs/sdlc/3-build.html](../docs/sdlc/3-build.html), [docs/sdlc/4-test.html](../docs/sdlc/4-test.html))
**Map:** [INDEX.md](INDEX.md) (generated; regenerate with python3 scripts/folder-index.py)

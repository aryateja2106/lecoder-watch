# MeshDesktop/ — the Mac menu-bar app: shows whether this Mac's background service (meshd) is running, asks for the Mac permissions it needs, and shows the QR code a phone scans to pair

**Read first:** `docs/product/PRODUCT.md` §7.3 and §8 (spec, and the planned Permissions window), `MeshDesktop/LocalDaemon.swift` (every network call and wire type), `project.yml:115-142` (why the target compiles only this folder)
**Surface:** mac
**Serialized (one agent at a time):** `MeshDesktop/LocalDaemon.swift` when a wire type or the pairing link changes (it copies `Shared/Models.swift` shapes and the `mesh pair` link by hand); `project.yml` (AGENTS.md serialized list)
**Prove a change:**
- Compile: `xcodegen generate && xcodebuild -project MeshWatch.xcodeproj -scheme MeshDesktop -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build` (same as `scripts/gate-build.sh:51`, `.github/workflows/ci.yml:154`)
- Launch: `MESH_SIM_LIVE=1 sh scripts/check-sim-fleet.sh` (opt-in; SKIP without the flag, `scripts/check-sim-fleet.sh:16`)
- Names and ids: `sh scripts/check-brand.sh`; spec coverage: `sh scripts/check-product-spec.sh`
- Behaviour: no dedicated check — add `scripts/check-mesh-desktop.sh` (pin `pairingLink` against `install/payload/bin/mesh:807` and `Shared/Models.swift:139`, and the /doctor shape). Until then run the built app against the live daemon, read-only calls only (AGENTS.md rule 1)
**Traps:**
- Pairing QR format is written three times: `LocalDaemon.swift:184-187`, `install/payload/bin/mesh:807`, parsed at `Shared/Models.swift:139-161`. Change all; nothing checks the Mac copy.
- Opening the Pair window mints a new code and voids any code `mesh pair` printed (`PairView.swift:8-10`, `install/payload/meshd/pair.ts:98`).
- "Open web console" opens `/desktop` with no token (`MeshDesktopApp.swift:60`); works only while the loopback exemption is on (`install/payload/meshd/loopback-trust.ts:23-25`).
- Port 8899 is hard-coded (`LocalDaemon.swift:13-16`); a side-port test daemon (AGENTS.md rule 5) is invisible to this app.
- Built product is `MeshWatch.app` (`project.yml:139`), same name as the iOS app; Mac build is `build/DerivedData/Build/Products/Debug/`, phone is `Debug-iphonesimulator/` (`scripts/check-sim-fleet.sh:47-48`).
- Notifications permission is requested (`PermissionsView.swift:241-249`) but nothing here ever posts one.
**SDLC stage:** Build and Maintain — the Mac setup surface; Test only via compile and the opt-in launch check.
**Map:** see the file list above (4 files); purposes in `docs/agents/CODEMAP.md` section `MeshDesktop/`

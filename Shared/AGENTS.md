# Shared/ — the common language the iPhone app, the Apple Watch app and their widgets all speak to your machines

**Read first:** `docs/agents/CODEMAP.md` §Shared (which file), `docs/agents/CONTRACTS.md` (capabilities, relay commands), `docs/product/PRODUCT.md` §7.5 (relay contract)
**Surface:** shared-models
**Serialized (one agent at a time):** `Models.swift` (every wire type incl. `WatchCommand`), `MeshClient.swift` (every endpoint call) — AGENTS.md "Must be serialized"
**Prove a change:**
- `./.claude/scripts/gates.sh fast` — its types gate runs `swiftc -typecheck` on the 9 files in `scripts/check-all.sh:14` `DEPS` (`scripts/gate-types.sh:33-35`)
- `sh scripts/check-all.sh` — every `scripts/check-*.swift` is compiled `-Onone` against those same 9 files (`scripts/check-all.sh:19-27`)
- Files outside `DEPS` (`MeshClient`, `PtyClient`, `SecureStore`, `SessionActivity`, `SessionCard`, `PowerActions`, `TerminalKeyRouter`, `VoiceSegments`): only the iOS + watchOS `xcodebuild` in AGENTS.md "Build and verify" compiles them; `TerminalKeyRouter` also `sh scripts/check-native-terminal-keys.sh`, `VoiceSegments` also `sh scripts/check-voice-accumulate.sh`
- Anything that talks to meshd: run it against a side-port daemon (AGENTS.md rules 1, 5)

**Traps:**
- Four targets compile this whole folder: iOS app, iOS widgets, watch app, watch widget (`project.yml:66,147,174,205`). An iOS-only framework needs `#if canImport` (`SessionActivity.swift:3`). The Mac menu-bar app does NOT; it keeps hand copies of wire types (`MeshDesktop/LocalDaemon.swift:6-7`) that you must update yourself.
- Keep `Models.swift` and the other `DEPS` files free of SwiftUI/ActivityKit: bare `swiftc` builds every self-check from them (`SessionCard.swift:7-8`). A new file a check needs must be added to `DEPS`, which lives in a `scripts/check-*` file (CLAUDE.md non-negotiable 3: not in an unattended run).
- `MeshClient.swift:4` says "iPhone-only (the watch never calls this)". False: `Watch/RemoteView.swift:93-94` and `Watch/WatchMeshStore.swift:139` use it.
- A new `WatchCommandKind` case (`Models.swift:1415`) must be handled in `iOS/MeshStore.swift` `handle(_:)`, or the watch shows a tick for nothing; failures travel as `RelayReply` (`Models.swift:1392`). Pinned by `check-relay-ack.swift`, `check-relay-receiver.sh`.
- A call that needs a newer daemon must gate on `supports("x")` (`MeshClient.swift:31`) and be listed in `DaemonCapabilities` — an old daemon answers 200 with the old shape (AGENTS.md rule 6).
- `AgentNotification.attentionCategory` (`AgentNotifications.swift:19`) is string-matched against `meshd/push.ts` by `check-mesh-push.sh:135`; renaming it strands pending alerts without buttons (`AgentNotifications.swift:15-17`).

**SDLC stage:** Design + Build (the wire contract every client and meshd agree on), Test (the pure logic the self-checks link against).
**Map:** `Shared/INDEX.md` (17 tracked files; to be generated) — until then `docs/agents/CODEMAP.md` §`Shared/`

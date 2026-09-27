# Watch/ — the Apple Watch app: see your machines, answer waiting agents, and drive the Mac from your wrist

**Read first:** `docs/agents/UI-MAP.md` § Apple Watch (every screen, its routes); `Watch/WatchMeshStore.swift:11` (direct vs phone-relay paths); `docs/agents/CONTRACTS.md:131` (relay commands the phone must handle)
**Surface:** watch
**Serialized (one agent at a time):** none inside this folder (`WatchViews.swift` is parallel-safe per AGENTS.md:228). A change that adds a relay command also touches `Shared/Models.swift` (`WatchCommand`) and `project.yml` — both serialized (AGENTS.md:233).
**Prove a change:**
- `sh scripts/check-watch-terminal-wiring.sh; sh scripts/check-mesh-input.sh; sh scripts/check-drag-lock-release.sh; sh scripts/check-relay-receiver.sh; sh scripts/check-inspect-crop.sh; sh scripts/check-harness-picker.sh` (seconds, structural)
- Swift logic checks (`-Onone`, AGENTS.md "Build and verify"): `DEPS=(Shared/Models.swift Shared/LimitHelpers.swift Shared/AgentNotifications.swift Shared/WatchGlance.swift Shared/APNsEnvironment.swift Shared/RiskClassifier.swift Shared/ScreenZoom.swift Shared/AlertGating.swift Shared/DaemonCapabilities.swift); for c in check-watch-scrollback check-connection-phase check-air-mouse check-relay-ack; do swiftc -Onone -o /tmp/$c scripts/$c.swift "${DEPS[@]}" && /tmp/$c || echo FAIL $c; done`
- Compile: the `'MeshWatch Watch App'` xcodebuild line in AGENTS.md "Build and verify" (minutes), then `sh scripts/check-watch-smoke.sh` (launch, not just build — AGENTS.md rule 1)
- Wrist-only behaviour (mic, banner buttons, crown feel) cannot be proven by an agent: hand back (AGENTS.md:263)
**Traps:**
- Logic written in `Watch/` cannot be unit-checked: `scripts/check-all.sh:14` links Swift checks against `Shared/` only. Testable watch math lives in Shared (`airMouseDelta` `Shared/Models.swift:1325`, `connectionPhase` `Shared/Models.swift:642`); `firstLink`/`lastLink` (`Watch/WatchLinks.swift:16,37`) have no check.
- Eleven existing checks name these files by path (e.g. `scripts/check-watch-terminal-wiring.sh:17-18,131-133`, `scripts/check-mesh-input.sh:12`). Renaming or splitting a file turns them red, and existing checks may not be edited unattended (CLAUDE.md non-negotiable 3).
- A new `WatchCommandKind` needs a case in `iOS/MeshStore.swift` `handle(_:)`, or it is acked as a silent tick (`docs/agents/CONTRACTS.md:133`).
- Scrollback size is capped by WatchConnectivity's 262,144-byte context that throws silently (`scripts/check-watch-scrollback.swift:5-8`); the watch asks for 300 lines (`Watch/WatchMeshStore.swift:562`).
- `WCSession.isReachable` flaps every few seconds; the UI must key off `connectionPhase`, not `phoneReachable` (`Watch/WatchMeshStore.swift:39-45`).
- The machine cache carries meshd tokens: Keychain via `SecureStore` only, never UserDefaults (`Watch/WatchMeshStore.swift:245-248`). New send keys go in both clients (AGENTS.md:192).
**SDLC stage:** Build, Test — the watch client code and the structural checks that pin it; Design lives in `docs/agents/UI-MAP.md`.
**Map:** `Watch/INDEX.md` (to be generated: 9 tracked files); until then `docs/agents/CODEMAP.md` § `Watch/` and `docs/agents/UI-MAP.md` § Apple Watch

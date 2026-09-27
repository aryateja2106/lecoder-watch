# WatchWidgets/ — the watch-face complication: how many agents are waiting on you, shown on the watch face all day

**Read first:** `Shared/WatchGlance.swift` (the data it shows); `Watch/WatchMeshStore.swift:505` (the only writer); `scripts/check-glance.swift` (what "stale" means)
**Surface:** watch
**Serialized (one agent at a time):** `WatchWidgets.entitlements` and the widget kind `"MeshGlance"` — frozen identifiers pinned by `scripts/check-brand.sh:26,30`; the target itself is defined in `project.yml:201-225` (serialized, AGENTS.md:239)
**Prove a change:** `sh scripts/check-brand.sh; sh scripts/check-entitlements.sh`, and `DEPS=(Shared/Models.swift Shared/LimitHelpers.swift Shared/AgentNotifications.swift Shared/WatchGlance.swift Shared/APNsEnvironment.swift Shared/RiskClassifier.swift Shared/ScreenZoom.swift Shared/AlertGating.swift Shared/DaemonCapabilities.swift); swiftc -Onone -o /tmp/cg scripts/check-glance.swift "${DEPS[@]}" && /tmp/cg`; compile via the watch-app xcodebuild line in AGENTS.md "Build and verify" (it embeds this extension, `project.yml:198-200`). How it looks on a real face is a human check (AGENTS.md:263).
**Traps:**
- The widget never fetches. It only reads what the watch app last wrote to App Group `group.com.lecoder.meshwatch` (`Shared/WatchGlance.swift:131`, written only at `Watch/WatchMeshStore.swift:510`); after 15 minutes the reading is stale (`Shared/WatchGlance.swift:51`, timeline at `WatchWidgets/WatchGlanceWidget.swift:49-61`).
- Kind `"MeshGlance"` (`WatchWidgets/WatchGlanceWidget.swift:21`) and the App Group are frozen identifiers (`scripts/check-brand.sh:5,26,30`); renaming either fails the check. Effect on faces already set up: unverified.
- `Info.plist` is written by xcodegen from `project.yml:207-213`; edit `project.yml`, not the plist. The extension version must match the parent app or App Store Connect rejects it (`project.yml:210-211`).
- The bundle id ends `.glance` because a deleted App ID (`…complication`) can never be reused (`CONTEXT.md:97-99`).
**SDLC stage:** Build, Test — the complication view and timeline; its data contract is tested in `scripts/check-glance.swift` (see [docs/sdlc/3-build.html](../docs/sdlc/3-build.html), [docs/sdlc/4-test.html](../docs/sdlc/4-test.html))
**Map:** 5 tracked files; run `git ls-files WatchWidgets` to list them (`WatchGlanceWidget.swift`, `Info.plist`, `WatchWidgets.entitlements`, `PrivacyInfo.xcprivacy`); `docs/agents/CODEMAP.md` § `WatchWidgets/`

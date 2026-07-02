---
name: claude-design-to-meshwatch-swiftui
description: Convert a Claude design URL, HTML/CSS prototype, local prototype archive, screenshot, or mockup into a MeshWatch SwiftUI view for the watch app, iPhone app, widgets, or shared components. Use when the user asks to translate a visual prototype into this repo's SwiftUI code, adapt a web mockup to watchOS/iOS, or create a narrow redesign experiment from a design reference.
---

# Claude Design To MeshWatch SwiftUI

## Overview

Translate prototypes into native MeshWatch SwiftUI without assuming plugin MCPs, Chrome tooling, or Xcode automation are available. Keep the output narrow: one new view or a small patch to the existing screen that proves the design direction.

This is adapted for this repo from the workflow in https://github.com/heyadam/claudedesign-to-swiftui.

## Workflow

1. Read the local app shape first. For watch UI, start in `Watch/WatchViews.swift`; for iPhone terminal UI, start in `iOS/TerminalView.swift`; for shared badges/cards, start in `Shared/SessionCard.swift`.
2. If `.agents/skills/meshwatch-ui-taste/SKILL.md` exists, read it before judging the design. It carries the local taste and watch-terminal constraints.
3. Ingest the reference. Accept a URL, `.tar.gz`, HTML/CSS files, screenshot, or pasted brief. If a design URL is one-shot or inaccessible, ask for a fresh artifact instead of guessing.
4. Inventory only what matters: layout rhythm, hierarchy, controls, color role, type scale, motion idea, empty/error/loading states, and any asset that must survive.
5. Map to native SwiftUI:
   - Prefer `NavigationStack`, `List`, `Form`, `ScrollView`, `Button`, `Label`, SF Symbols, system fonts, and SwiftUI materials.
   - Use watchOS-native command surfaces instead of trying to embed a full xterm on the watch.
   - Keep the iPhone `WKWebView` bridge as the full terminal surface.
   - Do not add Lottie, progressive blur, custom keyboard, or TTS dependencies unless the user explicitly asks and the target supports them.
6. Implement the smallest useful patch. Favor presentational changes over data/transport changes; avoid touching `WatchMeshStore`, `MeshStore`, `WatchLink`, `PhoneConnectivity`, `MeshClient`, or `install/payload/rmux-bridge/*` for a visual redesign.
7. Verify the target build. Watch-only:

```sh
xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch Watch App" -destination 'generic/platform=watchOS Simulator' build
```

iPhone:

```sh
xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch" -destination 'generic/platform=iOS Simulator' build
```

## MeshWatch Targets

- Watch redesign experiments should usually land in `Watch/WatchViews.swift`.
- iPhone terminal-session polish should usually land in `iOS/TerminalView.swift`, especially `SessionPeekScreen`.
- Shared status language belongs in `Shared/SessionCard.swift` only when the same badge/status treatment should affect phone, watch, and widgets.
- Run `xcodegen generate` only if `project.yml` changed or the Xcode project is missing.

## Watch Terminal Rule

On watch, design for glance and intervention: latest output, session state, pane awareness, a command deck, dictation/Scribble reply, and danger controls. Full terminal emulation belongs on iPhone through the existing rmux bridge.

## Skip

- Skip plugin marketplace setup, MCP-only flows, browser visual diff loops, and copied web animation stacks unless explicitly requested.
- Skip broad rewrites. A redesign experiment should make one coherent screen better before touching app architecture.

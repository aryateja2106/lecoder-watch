---
name: apple-native-apis
description: Build native Apple applications with modern Swift 5.9+/6 and SwiftUI across iPhone, iPad, Apple Watch, and Mac. Master specialized Apple capabilities including Live Activities (ActivityKit), Interactive Widgets (WidgetKit), Siri Shortcuts (AppIntents), Push/Local Notifications with Actions (UserNotifications), and WatchConnectivity.
---

# Apple Native APIs & Specialized Frameworks (iOS, watchOS, iPadOS, macOS)

Authoritative reference and engineering patterns for building native Apple applications on iOS 17/18+, watchOS 10/11+, iPadOS 17/18+, and macOS 14/15+.

Every API name below was checked against Apple's own developer documentation. If you reach
for something not named here, check it yourself before shipping it — do not guess a
signature or a case name.

---

## 1. Platform & Language Baselines

- **Swift Version:** Swift 5.9 / Swift 6 with strict concurrency (`Sendable`, `@MainActor`, `Actor`).
- **State Management:** Modern `@Observable` (Observation framework) over legacy `ObservableObject` / `@Published`.
- **Target Deployment Minimums:**
  - iOS: 17.0+ (iOS 18+ for new Control Center widgets & App Intents features)
  - watchOS: 10.0+ (watchOS 11+ for `onScrollGeometryChange` & Double Tap)
  - macOS: 14.0+ Sonoma (macOS 15+ Sequoia for iPhone Mirroring & Window tiling integration)
  - iPadOS: 17.0+ (Multi-window Stage Manager, desktop-class iPad toolbars)

---

## 2. Specialized Framework Index

| Capability | Framework | Reference Document | Key APIs |
|---|---|---|---|
| **Live Activities & Dynamic Island** | `ActivityKit` | `references/live-activities-dynamic-island.md` | `ActivityAttributes`, `ActivityContent`, `DynamicIsland`, `Activity.request` |
| **Interactive Widgets & Smart Stack** | `WidgetKit` | `references/widgets-smart-stack.md` | `AppIntentConfiguration`, `Button(intent:)`, `WidgetFamily`, timeline providers |
| **Siri & App Shortcuts** | `AppIntents` | `references/siri-app-intents.md` | `AppIntent`, `AppShortcutsProvider`, `Parameter`, Siri voice invocation |
| **Interactive Notifications** | `UserNotifications` | `references/notifications-actions.md` | `UNUserNotificationCenter`, `UNNotificationAction`, `UNNotificationCategory` |
| **iPhone & iPad Native UI** | `SwiftUI` / `SwiftData` | `references/ios-ipados-swiftui.md` | `@Observable`, `NavigationStack`, `SwiftData`, haptics, `TipKit` |
| **Apple Watch UI** | `WatchKit` / `SwiftUI` | `references/watchos-swiftui.md` | `.digitalCrownRotation`, Smart Stack complications, `WCSession`, haptics |
| **Mac (macOS) Native UI** | `AppKit` / `SwiftUI` | `references/macos-swiftui.md` | `MenuBarExtra`, `WindowGroup`, `Settings`, `Process`, Keychain |

---

## 3. Core Architecture Rules

1. **Always use modern `@Observable` instead of `ObservableObject`:**
   ```swift
   import SwiftUI
   import Observation

   @Observable
   final class AppModel {
       var title: String = ""
       var count: Int = 0
   }
   ```
2. **XcodeGen (`project.yml`) Conventions:**
   - `DEVELOPMENT_TEAM` and the bundle identifier prefix are never hardcoded. Run
     `mesh apps config` first to read the values the user already set (or ask them, then
     save with `mesh apps config --team <ID> --prefix <com.example>` — see the
     `native-app-builder` skill).
   - Register a custom URL scheme per app (`CFBundleURLTypes` → `<bundle-prefix>.<app-slug>`)
     using whatever prefix `mesh apps config` reports.
   - Enable `NSSupportsLiveActivities: true` when building Live Activities.
3. **No Legacy APIs:**
   - Reject `NavigationView` (use `NavigationStack` / `NavigationSplitView`).
   - Reject `WKInterfaceController` storyboard layouts (use 100% SwiftUI on watchOS).
   - Reject manual notification parsing where `AppIntents` or `UNNotificationAction` are native.

---

## 4. How MeshWatch itself uses these

This app is a working example of most of the frameworks above. Read the real code before
inventing a pattern from scratch:

- **Live Activity** — `Shared/SessionActivity.swift` defines `SessionActivityAttributes:
  ActivityAttributes` and its `ContentState`; `MeshWatchWidgets/SessionLiveActivity.swift`
  and `MeshWatchWidgets/SessionLockScreenView.swift` render it on the Lock Screen and
  Dynamic Island.
- **Actionable notifications** — `Shared/AgentNotifications.swift` registers the
  `UNNotificationCategory`/`UNNotificationAction` pairs (`Action.approve`, `.decline`,
  `.stop`) via `UNUserNotificationCenter.current().setNotificationCategories(...)`;
  `iOS/NotificationManager.swift` schedules the alerts that carry those categories.
- **Widgets** — `MeshWatchWidgets/` is the whole target: a Live Activity view plus a Lock
  Screen accessory family, not a general-purpose Smart Stack widget. Read it before adding
  a new widget family so the two don't diverge.
- **Watch Digital Crown + haptics** — `Watch/WatchViews.swift` scrolls the terminal peek
  screen with the Crown and calls `WKInterfaceDevice.current().play(.failure)` (and the
  other `WKHapticType` cases) for physical feedback on agent state changes. Follow its
  existing helper rather than re-deriving crown-scroll wiring.

---

## 5. Talking to the local daemon

Every one of these frameworks eventually needs to reach the Mac. There is exactly one
control-plane API, `meshd`, documented in full in `AGENTS.md` under "The daemon API, in one
place." The essentials an agent needs while writing Apple-side code:

- Base URL: `http://<mac-lan-ip>:8899` (default port; override via `MESHD_PORT`).
- Auth: every route except `GET /health` and the served PWA assets requires
  `Authorization: Bearer <token>`. The token lives in `~/.mesh/token` on the Mac and in the
  Keychain on iOS/watchOS once paired — never hardcode one.
- Start an agent session: `POST /agents/new {name, cwd, cmd, initialText}`.
- Answer an approval prompt: `POST /agents/<name>/send {key: "enter"}` to approve,
  `{key: "escape"}` to decline. Free-text replies use `{text: "..."}` instead of `key`.
- List sessions: `GET /agents` → a bare JSON array of session rows.

The reference docs below use this API, not a placeholder. If a snippet in this skill
directory ever shows a different host, port, or path, that snippet is wrong — fix it
rather than copy it.

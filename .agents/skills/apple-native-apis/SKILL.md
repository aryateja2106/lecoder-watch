---
name: apple-native-apis
description: Build native Apple applications with modern Swift 5.9+/6 and SwiftUI across iPhone, iPad, Apple Watch, and Mac. Master specialized Apple capabilities including Live Activities (ActivityKit), Interactive Widgets (WidgetKit), Siri Shortcuts (AppIntents), Push/Local Notifications with Actions (UserNotifications), and WatchConnectivity.
---

# Apple Native APIs & Specialized Frameworks (iOS, watchOS, iPadOS, macOS)

Authoritative reference and engineering patterns for building native Apple applications on iOS 17/18+, watchOS 10/11+, iPadOS 17/18+, and macOS 14/15+.

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
| **iPhone & iPad Native UI** | `SwiftUI` / `SwiftData` | `references/ios-ipados-swiftui.md` | `@Observable`, `NavigationStack`, `SwiftData`, `CoreHaptics`, `TipKit` |
| **Apple Watch (iWatch) UI** | `WatchKit` / `SwiftUI` | `references/watchos-swiftui.md` | `.digitalCrownRotation`, Smart Stack complications, `WCSession`, haptics |
| **MacBook (macOS) Native UI** | `AppKit` / `SwiftUI` | `references/macos-swiftui.md` | `MenuBarExtra`, `WindowGroup`, `Settings`, native hotkeys, local subprocesses |

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
   - Always declare `DEVELOPMENT_TEAM: B5B87F7AXF` (or read from config).
   - Always register custom URL scheme (`CFBundleURLTypes` -> `com.aryateja.<app-slug>`).
   - Enable `NSSupportsLiveActivities: true` when building Live Activities.
3. **No Legacy APIs:**
   - Reject `NavigationView` (use `NavigationStack` / `NavigationSplitView`).
   - Reject `WKInterfaceController` storyboard layouts (use 100% SwiftUI on watchOS).
   - Reject manual notification parsing where `AppIntents` or `UNNotificationAction` are native.

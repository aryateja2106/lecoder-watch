# Modern iOS 17/18+ & iPadOS Native APIs

Comprehensive reference for building iPhone and iPad applications using modern SwiftUI, Observation, SwiftData, and hardware features.

---

## 1. Observation Framework (`@Observable`)

Replaces `ObservableObject`, `@Published`, and `@EnvironmentObject` with compile-time tracking:

```swift
import SwiftUI
import Observation

@Observable
public final class ProjectStore {
    public var projects: [String] = []
    public var isLoading: Bool = false

    public func add(name: String) {
        projects.append(name)
    }
}

struct ProjectListView: View {
    @Bindable var store: ProjectStore // Use @Bindable for 2-way bindings

    var body: some View {
        List {
            ForEach(store.projects, id: \.self) { project in
                Text(project)
            }
        }
    }
}
```

---

## 2. iPadOS Adaptability (`NavigationSplitView`)

iPadOS requires adaptive multi-column layouts that gracefully collapse to single-column on iPhone:

```swift
struct AdaptiveRootView: View {
    @State private var selectedTab: String? = "agents"

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink("Agents", value: "agents")
                NavigationLink("Artifacts", value: "artifacts")
                NavigationLink("Machines", value: "machines")
            }
            .navigationTitle("Mesh")
        } content: {
            // Secondary list column (iPad/Mac)
            Text("Select an item")
        } detail: {
            // Primary detail canvas
            Text("Main workspace")
        }
    }
}
```

---

## 3. SwiftData Storage

```swift
import SwiftData
import SwiftUI

@Model
public final class GeneratedArtifact {
    public var id: UUID
    public var slug: String
    public var title: String
    public var isPWA: Bool
    public var createdAt: Date

    public init(slug: String, title: String, isPWA: Bool) {
        self.id = UUID()
        self.slug = slug
        self.title = title
        self.isPWA = isPWA
        self.createdAt = Date()
    }
}

// In App entrypoint:
// WindowGroup { ContentView() }.modelContainer(for: GeneratedArtifact.self)
```

---

## 4. TipKit for User Onboarding

```swift
import TipKit

struct HomeInstallTip: Tip {
    var title: Text {
        Text("Add to Home Screen")
    }
    var message: Text? {
        Text("Tap the Share button in Safari and choose 'Add to Home Screen' to use this app offline.")
    }
    var image: Image? {
        Image(systemName: "plus.app")
    }
}

// In View:
// TipView(HomeInstallTip())
```

---

## 5. Haptic Feedback (UIKit)

`UIFeedbackGenerator` and its subclasses live in UIKit, not CoreHaptics — CoreHaptics
(`CHHapticEngine`, `CHHapticPattern`) is the lower-level framework for authoring custom
haptic patterns. For a simple success/warning/impact tap, UIKit's generators are the right
tool and need no pattern authoring at all:

```swift
import UIKit

public final class HapticFeedback {
    public static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    public static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    public static func impact() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
```

For watchOS, there is no `UIFeedbackGenerator` — see `references/watchos-swiftui.md` for
`WKInterfaceDevice.current().play(_:)` instead.

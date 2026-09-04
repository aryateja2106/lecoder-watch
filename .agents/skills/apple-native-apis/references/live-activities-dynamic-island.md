# Live Activities & Dynamic Island (ActivityKit)

Complete engineering reference for implementing Apple Live Activities on the Lock Screen, StandBy, and the Dynamic Island (iPhone 14 Pro, 15, 15 Pro, 16 series).

---

## 1. Prerequisites & Info.plist

In `project.yml` or `Info.plist`:
```yaml
properties:
  NSSupportsLiveActivities: true
  NSSupportsLiveActivitiesFrequentUpdates: true # Optional: for sub-second updates
```

---

## 2. Activity Attributes & Content State

Define the static attributes (configured at launch) and dynamic content state (updated live):

```swift
import ActivityKit
import SwiftUI

public struct AgentTaskAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var statusText: String
        public var progress: Double // 0.0 to 1.0
        public var currentTool: String?
        public var isWaitingForApproval: Bool
        public var updatedDate: Date

        public init(statusText: String, progress: Double, currentTool: String? = nil, isWaitingForApproval: Bool = false, updatedDate: Date = Date()) {
            self.statusText = statusText
            self.progress = progress
            self.currentTool = currentTool
            self.isWaitingForApproval = isWaitingForApproval
            self.updatedDate = updatedDate
        }
    }

    // Static immutable attributes
    public var taskTitle: String
    public var machineHost: String
    public var agentSlug: String

    public init(taskTitle: String, machineHost: String, agentSlug: String) {
        self.taskTitle = taskTitle
        self.machineHost = machineHost
        self.agentSlug = agentSlug
    }
}
```

---

## 3. Dynamic Island & Lock Screen Widget Implementation

Implement the `Widget` configuration conforming to `ActivityConfiguration`:

```swift
import WidgetKit
import SwiftUI

public struct AgentTaskLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentTaskAttributes.self) { context in
            // Lock Screen Banner & StandBy View
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(context.attributes.taskTitle, systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(context.attributes.machineHost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: context.state.progress)
                    .tint(context.state.isWaitingForApproval ? .orange : .blue)

                HStack {
                    Text(context.state.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    if let tool = context.state.currentTool {
                        Text(tool)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.agentSlug, systemImage: "atom")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isWaitingForApproval {
                        Text("Action Needed")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    } else {
                        Text("\(Int(context.state.progress * 100))%")
                            .font(.caption.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.statusText)
                            .font(.footnote)
                            .lineLimit(1)
                        ProgressView(value: context.state.progress)
                            .tint(.cyan)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isWaitingForApproval ? "exclamationmark.triangle.fill" : "hammer.fill")
                    .foregroundStyle(context.state.isWaitingForApproval ? .orange : .cyan)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "atom")
                    .foregroundStyle(.cyan)
            }
            .keylineTint(.cyan)
        }
    }
}
```

---

## 4. Lifecycle Management (Start, Update, End)

```swift
import ActivityKit

@MainActor
public final class LiveActivityManager {
    public static let shared = LiveActivityManager()

    public func startLiveActivity(title: String, host: String, slug: String) -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }

        let attributes = AgentTaskAttributes(taskTitle: title, machineHost: host, agentSlug: slug)
        let initialContent = AgentTaskAttributes.ContentState(statusText: "Starting agent run...", progress: 0.05)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialContent, staleDate: Date().addingTimeInterval(3600)),
                pushType: .token // If using APNs push updates
            )

            // Listen for push token updates if using remote push
            Task {
                for await pushToken in activity.pushTokenUpdates {
                    let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
                    print("Live Activity Push Token: \(tokenString)")
                }
            }

            return activity.id
        } catch {
            print("Failed to start Live Activity: \(error)")
            return nil
        }
    }

    public func update(activityId: String, status: String, progress: Double, tool: String? = nil, isWaiting: Bool = false) async {
        guard let activity = Activity<AgentTaskAttributes>.activities.first(where: { $0.id == activityId }) else { return }
        let updatedState = AgentTaskAttributes.ContentState(
            statusText: status,
            progress: progress,
            currentTool: tool,
            isWaitingForApproval: isWaiting,
            updatedDate: Date()
        )
        await activity.update(.init(state: updatedState, staleDate: Date().addingTimeInterval(600)))
    }

    public func end(activityId: String, finalStatus: String) async {
        guard let activity = Activity<AgentTaskAttributes>.activities.first(where: { $0.id == activityId }) else { return }
        let finalState = AgentTaskAttributes.ContentState(statusText: finalStatus, progress: 1.0, updatedDate: Date())
        await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
    }
}
```

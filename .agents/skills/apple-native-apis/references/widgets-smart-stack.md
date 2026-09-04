# Interactive Widgets & Smart Stack (WidgetKit & AppIntents)

Complete engineering reference for building interactive widgets on iOS 17/18+, iPadOS, macOS 14/15, and watchOS 10/11+ Smart Stack.

---

## 1. Supported Widget Families

- **iOS / iPadOS / macOS:** `.systemSmall`, `.systemMedium`, `.systemLarge`, `.systemExtraLarge` (iPad/Mac), `.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline` (Lock Screen & Mac desktop).
- **watchOS:** `.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline`, `.accessoryCorner`.

---

## 2. Interactive AppIntent for Widget Buttons

Widgets in iOS 17+ can trigger swift code directly without opening the main app using `AppIntent`:

```swift
import AppIntents
import WidgetKit

public struct TriggerAgentRunIntent: AppIntent {
    public static var title: LocalizedStringResource = "Trigger Agent Build"
    public static var description = IntentDescription("Starts an autonomous build session on LeSearch Mesh.")

    @Parameter(title: "Prompt")
    public var prompt: String

    @Parameter(title: "Machine Host")
    public var machineHost: String

    public init() {}

    public init(prompt: String, machineHost: String) {
        self.prompt = prompt
        self.machineHost = machineHost
    }

    public func perform() async throws -> some IntentResult {
        // Dispatch to local mesh daemon on port 7777 or via local MeshClient
        guard let url = URL(string: "http://127.0.0.1:7777/api/sessions") else {
            return .result()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["prompt": prompt, "platform": "ios"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        _ = try? await URLSession.shared.data(for: request)

        // Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

---

## 3. Timeline Provider & Widget Definition

```swift
import WidgetKit
import SwiftUI

public struct MeshStatusEntry: TimelineEntry {
    public let date: Date
    public let activeSessions: Int
    public let lastAgentName: String
    public let isOnline: Bool
}

public struct MeshStatusProvider: TimelineProvider {
    public func placeholder(in context: Context) -> MeshStatusEntry {
        MeshStatusEntry(date: Date(), activeSessions: 1, lastAgentName: "Claude Code", isOnline: true)
    }

    public func getSnapshot(in context: Context, completion: @escaping (MeshStatusEntry) -> Void) {
        completion(MeshStatusEntry(date: Date(), activeSessions: 2, lastAgentName: "Cursor Agent", isOnline: true))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<MeshStatusEntry>) -> Void) {
        Task {
            let entry = await fetchMeshStatus()
            // Refresh every 5 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchMeshStatus() async -> MeshStatusEntry {
        guard let url = URL(string: "http://127.0.0.1:7777/api/health"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return MeshStatusEntry(date: Date(), activeSessions: 0, lastAgentName: "Offline", isOnline: false)
        }

        let active = json["activeSessions"] as? Int ?? 0
        return MeshStatusEntry(date: Date(), activeSessions: active, lastAgentName: "LeSearch Mesh", isOnline: true)
    }
}

public struct MeshStatusWidget: Widget {
    public let kind: String = "MeshStatusWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MeshStatusProvider()) { entry in
            MeshWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("LeSearch Mesh")
        .description("Monitor active agent sessions across your machines.")
        #if os(watchOS)
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

public struct MeshWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MeshStatusEntry

    public var body: some View {
        switch family {
        case .accessoryRectangular:
            // watchOS Smart Stack or Lock Screen
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: entry.isOnline ? "circle.fill" : "circle")
                        .foregroundStyle(entry.isOnline ? Color.green : Color.secondary)
                        .font(.system(size: 8))
                    Text("LeSearch Mesh")
                        .font(.headline)
                }
                Text("\(entry.activeSessions) Active Sessions")
                    .font(.caption2)
                Text(entry.lastAgentName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "atom")
                        .font(.caption)
                    Text("\(entry.activeSessions)")
                        .font(.caption.bold())
                }
            }

        default:
            // System Small / Medium
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Mesh", systemImage: "server.rack")
                        .font(.headline)
                    Spacer()
                    Circle().fill(entry.isOnline ? Color.green : Color.orange).frame(width: 8, height: 8)
                }
                Text("\(entry.activeSessions) Active Agents")
                    .font(.title2.bold())

                // Interactive One-Tap Button
                Button(intent: TriggerAgentRunIntent(prompt: "Check mesh health and triage issues", machineHost: "aryas-mbp")) {
                    Label("Run Health Check", systemImage: "play.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(4)
        }
    }
}
```

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
    public static var description = IntentDescription("Starts an autonomous build session on the paired Mac.")

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
        // meshd, default port 8899. POST /agents/new starts a session; there is no
        // /api/sessions route. See references/siri-app-intents.md for the full version
        // of this call, including auth.
        guard let token = tokenForHost(machineHost),
              let url = URL(string: "http://\(machineHost):8899/agents/new") else {
            return .result()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "name": "widget-\(Int(Date().timeIntervalSince1970))",
            "cmd": "claude",
            "initialText": "\(prompt)\n",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        _ = try? await URLSession.shared.data(for: request)

        // Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }

    private func tokenForHost(_ host: String) -> String? { nil }
}
```

---

## 3. Timeline Provider & Widget Definition

A widget's timeline budget is tight, so make one network call, not two. `GET /agents`
(Bearer-authenticated) both proves the daemon is reachable and returns the live session
count in one round trip — it answers with a bare JSON array, not a wrapper object.
`GET /health` needs no token at all if you only want an up/down signal.

```swift
import WidgetKit
import SwiftUI

public struct MeshStatusEntry: TimelineEntry {
    public let date: Date
    public let activeSessions: Int
    public let isOnline: Bool
}

public struct MeshStatusProvider: TimelineProvider {
    public func placeholder(in context: Context) -> MeshStatusEntry {
        MeshStatusEntry(date: Date(), activeSessions: 1, isOnline: true)
    }

    public func getSnapshot(in context: Context, completion: @escaping (MeshStatusEntry) -> Void) {
        completion(MeshStatusEntry(date: Date(), activeSessions: 2, isOnline: true))
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
        // Widgets read from the same Keychain access group as the main app — see
        // Shared/MeshClient.swift for how this app resolves the default machine + token.
        guard let host = defaultMeshHost(), let token = tokenForHost(host),
              let url = URL(string: "http://\(host):8899/agents"),
              var request = Optional(URLRequest(url: url)) else {
            return MeshStatusEntry(date: Date(), activeSessions: 0, isOnline: false)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let sessions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return MeshStatusEntry(date: Date(), activeSessions: 0, isOnline: false)
        }

        return MeshStatusEntry(date: Date(), activeSessions: sessions.count, isOnline: true)
    }

    private func defaultMeshHost() -> String? { nil }
    private func tokenForHost(_ host: String) -> String? { nil }
}

public struct MeshStatusWidget: Widget {
    public let kind: String = "MeshStatusWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MeshStatusProvider()) { entry in
            MeshWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mesh")
        .description("Monitor active agent sessions on your paired Mac.")
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
                    Text("Mesh")
                        .font(.headline)
                }
                Text("\(entry.activeSessions) Active Sessions")
                    .font(.caption2)
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
                Button(intent: TriggerAgentRunIntent(prompt: "Check mesh health and triage issues", machineHost: "")) {
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

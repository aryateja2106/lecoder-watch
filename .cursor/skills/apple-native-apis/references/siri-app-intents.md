# Siri & App Shortcuts (AppIntents)

Complete engineering reference for building voice-driven actions, Siri integration, and Spotlight indexable shortcuts using `AppIntents`.

---

## 1. Defining an AppIntent

```swift
import AppIntents

public struct BuildAppIntent: AppIntent {
    public static var title: LocalizedStringResource = "Build Application with LeSearch"
    public static var description = IntentDescription("Directs the local agent to autonomously scaffold, code, and build a native or web application.")

    @Parameter(title: "App Description", requestValueDialog: "What kind of application would you like to build?")
    public var prompt: String

    @Parameter(title: "Target Platform", default: "ios")
    public var platform: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Build \(\.$platform) app: \(\.$prompt)")
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Send request to local devcluster-mesh daemon
        guard let url = URL(string: "http://127.0.0.1:7777/api/sessions") else {
            return .result(dialog: "Unable to reach local LeSearch Mesh daemon.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "prompt": prompt,
            "platform": platform
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 202 else {
                return .result(dialog: "Mesh daemon rejected the build request.")
            }

            return .result(
                dialog: "Agent is now building your \(platform) app on your Mac. You'll receive a live notification when it's ready to install.",
                view: BuildStartedSnippetView(prompt: prompt, platform: platform)
            )
        } catch {
            return .result(dialog: "Failed to communicate with your Mac: \(error.localizedDescription)")
        }
    }
}
```

---

## 2. AppShortcutsProvider (Zero-Configuration Siri Voice Phrases)

Users do not need to configure anything in the Shortcuts app; `AppShortcutsProvider` registers Siri voice triggers automatically:

```swift
import AppIntents

public struct LeSearchShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BuildAppIntent(),
            phrases: [
                "Build an app with \(.applicationName)",
                "Create a \(\.$platform) app using \(.applicationName)",
                "Ask \(.applicationName) to build an app",
                "Start building with \(.applicationName)"
            ],
            shortTitle: "Build App",
            systemImageName: "hammer.fill"
        )
    }
}
```

---

## 3. Snippet View for Siri UI & Spotlight

```swift
import SwiftUI

public struct BuildStartedSnippetView: View {
    public let prompt: String
    public let platform: String

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.cyan)
                Text("Autonomous Build Queued")
                    .font(.headline)
            }
            Text(prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text("Target: \(platform.uppercased())")
                    .font(.caption.bold())
                Spacer()
                Text("Running locally on Mac")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
```

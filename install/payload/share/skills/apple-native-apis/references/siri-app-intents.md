# Siri & App Shortcuts (AppIntents)

Complete engineering reference for building voice-driven actions, Siri integration, and Spotlight indexable shortcuts using `AppIntents`.

---

## 1. Defining an AppIntent

```swift
import AppIntents

public struct BuildAppIntent: AppIntent {
    public static var title: LocalizedStringResource = "Build an App"
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
        // Start a new agent session on the local mesh daemon (meshd, default port 8899).
        // In the real app, host + token come from the paired-machine store — see
        // Shared/MeshClient.swift — not from a literal string like this sketch uses.
        guard let host = defaultMeshHost(), let token = tokenForHost(host),
              let url = URL(string: "http://\(host):8899/agents/new") else {
            return .result(dialog: "No paired Mac found. Open the app and pair one first.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let sessionName = "siri-\(Int(Date().timeIntervalSince1970))"
        let payload: [String: Any] = [
            "name": sessionName,
            "cmd": "claude",
            "initialText": "Build a \(platform) app: \(prompt)\n",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 201 else {
                return .result(dialog: "The Mac rejected the build request.")
            }

            return .result(
                dialog: "Started on your Mac. You'll get a notification when it's ready to install.",
                view: BuildStartedSnippetView(prompt: prompt, platform: platform)
            )
        } catch {
            return .result(dialog: "Failed to reach your Mac: \(error.localizedDescription)")
        }
    }

    private func defaultMeshHost() -> String? { nil }
    private func tokenForHost(_ host: String) -> String? { nil }
}
```

`POST /agents/new` is the real route (`{name, cwd, cmd, initialText}`, per `AGENTS.md`) and
returns 201 on success. There is no `/api/sessions` route on this daemon — if you see that
path anywhere, it is wrong.

---

## 2. AppShortcutsProvider (Zero-Configuration Siri Voice Phrases)

Users do not need to configure anything in the Shortcuts app; `AppShortcutsProvider` registers Siri voice triggers automatically:

```swift
import AppIntents

public struct MeshShortcutsProvider: AppShortcutsProvider {
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

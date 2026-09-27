# Interactive Notifications & Action Extensions (UserNotifications)

Complete engineering reference for interactive notifications, custom action buttons, and direct wrist/phone responses using `UserNotifications`.

---

## 1. Defining Notification Categories & Actions

To allow users to approve or deny agent commands directly from Lock Screen banners or Apple Watch notifications:

```swift
import UserNotifications

public final class NotificationCategoryRegistrar {
    public static let shared = NotificationCategoryRegistrar()

    public static let agentApprovalCategory = "AGENT_APPROVAL_CATEGORY"
    public static let artifactReadyCategory = "ARTIFACT_READY_CATEGORY"

    public func registerCategories() {
        // 1. Actions for agent approvals
        let allowAction = UNNotificationAction(
            identifier: "ACTION_ALLOW",
            title: "Allow (Y)",
            options: [.foreground]
        )
        let denyAction = UNNotificationAction(
            identifier: "ACTION_DENY",
            title: "Deny (N)",
            options: [.destructive]
        )
        let replyAction = UNTextInputNotificationAction(
            identifier: "ACTION_REPLY",
            title: "Reply...",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type your answer to the agent"
        )

        let approvalCategory = UNNotificationCategory(
            identifier: Self.agentApprovalCategory,
            actions: [allowAction, denyAction, replyAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // 2. Actions for Artifact Ready (Built apps)
        let installAction = UNNotificationAction(
            identifier: "ACTION_INSTALL",
            title: "Install / Open",
            options: [.foreground, .authenticationRequired]
        )
        let artifactCategory = UNNotificationCategory(
            identifier: Self.artifactReadyCategory,
            actions: [installAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([approvalCategory, artifactCategory])
    }
}
```

This app's own registration lives in `Shared/AgentNotifications.swift` — read it before
adding a category, since it already defines the approve/decline/stop action identifiers
this reference mirrors.

---

## 2. Handling Notification Actions (`UNUserNotificationCenterDelegate`)

The daemon (`meshd`, default port 8899) has exactly one route for answering a running
session: `POST /agents/<name>/send`. There is no `y`/`n` text convention — an approval is a
**key press**, not typed text: `{"key": "enter"}` to allow, `{"key": "escape"}` to deny.
Free-text replies use `{"text": "..."}` instead. Every route but `GET /health` requires
`Authorization: Bearer <token>`; never hardcode a token, read it the same way the rest of
the app does (Keychain on-device, `~/.mesh/token` on the Mac).

```swift
import UserNotifications
import UIKit

public final class NotificationResponseHandler: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationResponseHandler()

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let host = userInfo["host"] as? String,
              let session = userInfo["session"] as? String else { return }

        switch response.actionIdentifier {
        case "ACTION_ALLOW":
            await sendAgentKey(host: host, session: session, key: "enter")

        case "ACTION_DENY":
            await sendAgentKey(host: host, session: session, key: "escape")

        case "ACTION_REPLY":
            if let textResponse = response as? UNTextInputNotificationResponse {
                await sendAgentText(host: host, session: session, text: textResponse.userText)
            }

        case "ACTION_INSTALL":
            if let deepLink = userInfo["deepLink"] as? String, let url = URL(string: deepLink) {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
            }

        default:
            break
        }
    }

    // Reuse the app's own client/token storage instead of hand-rolling URLSession —
    // see Shared/MeshClient.swift for the real implementation this sketches.
    private func sendAgentKey(host: String, session: String, key: String) async {
        await post(host: host, session: session, body: ["key": key])
    }

    private func sendAgentText(host: String, session: String, text: String) async {
        await post(host: host, session: session, body: ["text": text])
    }

    private func post(host: String, session: String, body: [String: Any]) async {
        guard let token = tokenForHost(host),
              let url = URL(string: "http://\(host):8899/agents/\(session)/send") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Wherever this app keeps paired-machine tokens (Keychain). Never a literal string.
    private func tokenForHost(_ host: String) -> String? { nil }
}
```

---

## 3. Triggering Local Interactive Notifications

```swift
public func postAgentDecisionNotification(task: String, question: String, host: String, session: String) {
    let content = UNMutableNotificationContent()
    content.title = "Decision Required"
    content.subtitle = task
    content.body = question
    content.categoryIdentifier = NotificationCategoryRegistrar.agentApprovalCategory
    content.sound = .defaultCritical
    content.userInfo = [
        "host": host,
        "session": session
    ]

    let request = UNNotificationRequest(
        identifier: "agent_decision_\(session)_\(Date().timeIntervalSince1970)",
        content: content,
        trigger: nil // Deliver immediately
    )

    UNUserNotificationCenter.current().add(request)
}
```

`.defaultCritical` requires the Critical Alerts entitlement (a separate Apple approval,
distinct from normal push/notification permission) — do not assume it is available without
checking the target's entitlements first.

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

---

## 2. Handling Notification Actions (`UNUserNotificationCenterDelegate`)

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
        let host = userInfo["host"] as? String ?? "localhost"
        let session = userInfo["session"] as? String ?? "default"

        switch response.actionIdentifier {
        case "ACTION_ALLOW":
            await sendAgentCommand(host: host, session: session, text: "y\n")

        case "ACTION_DENY":
            await sendAgentCommand(host: host, session: session, text: "n\n")

        case "ACTION_REPLY":
            if let textResponse = response as? UNTextInputNotificationResponse {
                await sendAgentCommand(host: host, session: session, text: "\(textResponse.userText)\n")
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

    private func sendAgentCommand(host: String, session: String, text: String) async {
        guard let url = URL(string: "http://\(host):7777/api/sessions/\(session)/input") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        _ = try? await URLSession.shared.data(for: req)
    }
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

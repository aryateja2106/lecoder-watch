import Foundation
import UserNotifications

/// An agent that is blocked waiting for a human is the whole reason this app exists on
/// a wrist. Answering it should not cost an app launch, a machine list, a session list
/// and a keyboard — it should cost one tap on the notification.
///
/// Both apps register the *same* category identifiers, because a notification the phone
/// receives and forwards is acted on by whichever device the person is looking at. If
/// the identifiers drift, the buttons quietly disappear on one of them.
enum AgentNotification {
    /// Must match `pushAlert`'s `aps.category` in `meshd/push.ts`.
    static let attentionCategory = "AGENT_ATTENTION"

    enum Action: String, CaseIterable {
        case cont = "AGENT_CONTINUE"
        case reply = "AGENT_REPLY"
        case stop = "AGENT_STOP"

        var title: String {
            switch self {
            case .cont: return "Continue"
            case .reply: return "Reply"
            case .stop: return "Stop"
            }
        }
    }

    /// What an action actually sends to `POST /agents/<session>/send`.
    ///
    /// `Continue` is Enter, not a "yes": Enter accepts whatever option the agent has
    /// highlighted, which is the same thing pressing return at the terminal would do.
    /// Guessing a "1" or a "y" would be answering a question we cannot see.
    static func command(for actionID: String, typed: String?) -> (text: String?, key: String?)? {
        switch Action(rawValue: actionID) {
        case .cont:
            return (nil, "enter")
        case .stop:
            return (nil, "ctrl-c")
        case .reply:
            let text = (typed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (text, nil)
        case nil:
            return nil
        }
    }

    /// The host and session an action should be sent to, pulled out of the APNs
    /// payload. Both are required — a session name is not unique across machines, and
    /// sending Enter to the wrong box is worse than doing nothing.
    static func target(from userInfo: [AnyHashable: Any]) -> (host: String, session: String)? {
        guard let host = userInfo["host"] as? String, !host.isEmpty,
              let session = userInfo["session"] as? String, !session.isEmpty else { return nil }
        return (host, session)
    }

    /// The inverse, for alerts the phone raises itself rather than receives. The two
    /// key strings live in one place so a locally scheduled banner cannot grow buttons
    /// that route nowhere — which is what a silent typo here looks like.
    static func userInfo(host: String, session: String) -> [String: String] {
        ["host": host, "session": session]
    }

    static var categories: Set<UNNotificationCategory> {
        let reply = UNTextInputNotificationAction(
            identifier: Action.reply.rawValue,
            title: Action.reply.title,
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Reply to the agent",
        )
        return [
            UNNotificationCategory(
                identifier: attentionCategory,
                actions: [
                    UNNotificationAction(identifier: Action.cont.rawValue, title: Action.cont.title, options: []),
                    reply,
                    UNNotificationAction(identifier: Action.stop.rawValue,
                                         title: Action.stop.title,
                                         options: [.destructive]),
                ],
                intentIdentifiers: [],
                options: [.customDismissAction],
            ),
        ]
    }

    /// Register on both platforms. Cheap and idempotent, so it runs at every launch
    /// rather than being tracked as state that can drift out of date.
    static func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }
}

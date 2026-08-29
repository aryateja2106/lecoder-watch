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
    ///
    /// STABLE across releases on purpose: a banner already sitting in Notification
    /// Center keeps the category identifier it was delivered with forever, and the
    /// buttons it shows are whatever THIS build has registered under that identifier.
    /// Renaming the *category* would strand every pending alert buttonless; renaming
    /// the *actions* under it does not, which is how the set below can evolve.
    static let attentionCategory = "AGENT_ATTENTION"

    /// The non-actionable lane (meshd 0.5.0+): turn-finished / info events worth a
    /// line in Notification Center but carrying no buttons, because there is no
    /// question to answer — buttons on a statement are how Enter lands in a session
    /// nobody meant to touch.
    static let infoCategory = "AGENT_INFO"

    enum Action: String, CaseIterable {
        case approve = "AGENT_APPROVE"
        case decline = "AGENT_DECLINE"
        case reply = "AGENT_REPLY"
        case stop = "AGENT_STOP"

        var title: String {
            switch self {
            case .approve: return "Approve"
            case .decline: return "Decline"
            case .reply:   return "Reply"
            case .stop:    return "Stop"
            }
        }
    }

    /// What an action actually sends to `POST /agents/<session>/send`. Every key
    /// string below exists in BOTH of meshd's key maps — `KEY_SEND_KEYS` (rmux/tmux)
    /// and `CMUX_KEYS` (cmux) in server.ts — so no route needs a daemon change.
    ///
    /// `Approve` is Enter, not a "yes": Enter accepts whatever option the agent has
    /// highlighted, which is the same thing pressing return at the terminal would do.
    /// Guessing a "1" or a "y" would be answering a question we cannot see.
    ///
    /// `Decline` is Escape — it backs out of the prompt (Claude Code and Codex both
    /// treat Escape as "dismiss / no") without killing the agent. Before it existed
    /// the only "no" was Stop's ctrl-c, which answers a permission question by
    /// shooting the questioner.
    static func command(for actionID: String, typed: String?) -> (text: String?, key: String?)? {
        // Delivered banners outlive app updates: an alert that arrived while an
        // older build's categories were registered can still come back with the old
        // Continue identifier, so it stays mapped even though no current category
        // offers it. Enter, exactly as Approve.
        if actionID == "AGENT_CONTINUE" { return (nil, "enter") }
        switch Action(rawValue: actionID) {
        case .approve:
            return (nil, "enter")    // accept the highlighted option
        case .decline:
            return (nil, "escape")   // back out of the prompt, agent keeps running
        case .stop:
            return (nil, "ctrl-c")   // interrupt the agent process itself
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

    /// The pane the event came from, when the payload carried one — a reply then
    /// lands in the agent's own pane rather than whichever pane the mux session
    /// happens to have active. Separate from `target(from:)`, and `target` stays a
    /// pair, so every existing destructuring call site keeps compiling; a missing or
    /// empty pane is nil, which meshd treats as "the session's active pane" — the
    /// pre-existing behavior.
    static func pane(from userInfo: [AnyHashable: Any]) -> String? {
        guard let pane = userInfo["pane"] as? String, !pane.isEmpty else { return nil }
        return pane
    }

    /// The inverse, for alerts the phone raises itself rather than receives. The
    /// key strings live in one place so a locally scheduled banner cannot grow buttons
    /// that route nowhere — which is what a silent typo here looks like. `pane` is
    /// optional and omitted when empty, mirroring `pane(from:)`.
    static func userInfo(host: String, session: String, pane: String? = nil) -> [String: String] {
        var info = ["host": host, "session": session]
        if let pane, !pane.isEmpty { info["pane"] = pane }
        return info
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
                    UNNotificationAction(identifier: Action.approve.rawValue,
                                         title: Action.approve.title, options: []),
                    UNNotificationAction(identifier: Action.decline.rawValue,
                                         title: Action.decline.title, options: []),
                    reply,
                    UNNotificationAction(identifier: Action.stop.rawValue,
                                         title: Action.stop.title,
                                         options: [.destructive]),
                ],
                intentIdentifiers: [],
                options: [.customDismissAction],
            ),
            // Deliberately empty: the info lane is a statement, not a question.
            UNNotificationCategory(
                identifier: infoCategory,
                actions: [],
                intentIdentifiers: [],
                options: [],
            ),
        ]
    }

    /// Register on both platforms. Cheap and idempotent, so it runs at every launch
    /// rather than being tracked as state that can drift out of date.
    static func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }
}

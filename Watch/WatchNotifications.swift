import Foundation
import UserNotifications

/// The watch half of "answer a blocked agent from the notification".
///
/// A notification the iPhone receives is forwarded to the wrist, and whichever device
/// the person is looking at handles the button. That means the watch needs the same
/// categories registered (`AgentNotification`) *and* a delegate — without one, the
/// buttons appear and then do nothing.
///
/// The delegate is installed at launch, before any store exists, because a tap is what
/// launched the app in the first place. An action that arrives before the store has
/// wired itself in waits here instead of being dropped.
final class WatchNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotifications()

    typealias Handler = (_ host: String, _ session: String, _ text: String?, _ key: String?) -> Void

    var onAgentAction: Handler? {
        didSet { drain() }
    }

    private var pending: [(host: String, session: String, text: String?, key: String?)] = []

    func activate() {
        UNUserNotificationCenter.current().delegate = self
        AgentNotification.registerCategories()
        // Forwarded alerts arrive under the phone's authorisation, but the watch app
        // also raises its own (session ended, machine back) and would be silent without
        // this. Declining costs nothing here — the forwarded path is unaffected.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func drain() {
        guard let handler = onAgentAction, !pending.isEmpty else { return }
        let queued = pending
        pending.removeAll()
        for item in queued { handler(item.host, item.session, item.text, item.key) }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let target = AgentNotification.target(from: response.notification.request.content.userInfo),
              let cmd = AgentNotification.command(
                  for: response.actionIdentifier,
                  typed: (response as? UNTextInputNotificationResponse)?.userText,
              )
        else { return }

        let item = (host: target.host, session: target.session, text: cmd.text, key: cmd.key)
        if let handler = onAgentAction {
            handler(item.host, item.session, item.text, item.key)
        } else {
            pending.append(item)
        }
    }
}

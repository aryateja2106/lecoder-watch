import SwiftUI
import UIKit

/// Receives the APNs device token and hands it to whoever registered interest.
/// meshd (push.ts) delivers alerts straight from each machine — no cloud relay.
final class PushDelegate: NSObject, UIApplicationDelegate {
    static var onToken: ((String) -> Void)?

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Self.onToken?(deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }
}

@main
struct MeshRelayApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @StateObject private var store: MeshStore

    init() {
        let store = MeshStore()
        _store = StateObject(wrappedValue: store)
        PushDelegate.onToken = { token in
            Task { await store.uploadPushToken(token) }
        }
        // Wire at launch (not onAppear) so a cold-start notification tap can resume,
        // and so the UN delegate is set before the tap response is delivered.
        NotificationManager.shared.onLimitResume = { providerId in
            Task { await store.resumePinnedLimit(providerId: providerId) }
        }
        NotificationManager.shared.onAgentAction = { host, session, text, key in
            Task { await store.respondToAgent(host: host, session: session, text: text, key: key) }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                    UIApplication.shared.registerForRemoteNotifications()
                    store.start()
                }
        }
    }
}

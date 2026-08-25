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
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

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
        NotificationManager.shared.onAgentAction = { host, session, text, key, pane in
            Task { await store.respondToAgent(host: host, session: session, text: text, key: key, pane: pane) }
        }
        // Live Activity push tokens go to the machines themselves — meshd pushes the
        // card directly, same as it pushes alerts, so there is no cloud in the path.
        // Wired here rather than in the controller so the controller keeps knowing
        // nothing about the machine list.
        LiveActivityController.shared.uploadToken = { kind, token, session in
            await store.uploadLAToken(kind: kind, token: token, session: session)
        }
        // Adopting orphaned activities has to happen before the first poll: a card left
        // over from a killed launch must be picked back up, not duplicated.
        LiveActivityController.shared.begin()
        // Must happen before launch completes, so it cannot move to onAppear.
        BackgroundRefresh.register(store: store)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if lock.isLocked {
                    // Nothing polls and nothing draws machine state until the device
                    // owner has proved they are present.
                    LockScreen()
                } else {
                    ContentView()
                        .onAppear {
                            #if DEBUG
                            // -uiRemote exists to make the remote screen inspectable; a system
                            // alert sitting over the middle of it defeats the point.
                            if !ProcessInfo.processInfo.arguments.contains("-uiRemote") {
                                NotificationManager.shared.requestAuthorizationOncePaired(hasMachines: !store.machines.isEmpty)
                            }
                            #else
                            NotificationManager.shared.requestAuthorizationOncePaired(hasMachines: !store.machines.isEmpty)
                            #endif
                            UIApplication.shared.registerForRemoteNotifications()
                            store.start()
                        }
                }
            }
            .environmentObject(store)
            .environmentObject(lock)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    lock.didEnterBackground()
                    // Queue a usage check for while the app is closed — this is what
                    // notices you crossed a limit when you aren't looking.
                    BackgroundRefresh.schedule()
                case .active:
                    lock.willEnterForeground()
                    // The 8s timer does not fire while suspended, so without this the
                    // first thing a returning user sees is however stale the world was
                    // when iOS parked the app — and the first natural tick after a long
                    // suspend often fails once while the radio wakes, which used to
                    // read as "offline". Poll immediately instead.
                    Task { await store.refresh() }
                default:
                    break
                }
            }
        }
    }
}

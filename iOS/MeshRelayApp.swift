import SwiftUI

@main
struct MeshRelayApp: App {
    @StateObject private var store: MeshStore
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = MeshStore()
        _store = StateObject(wrappedValue: store)
        // Wire at launch (not onAppear) so a cold-start notification tap can resume,
        // and so the UN delegate is set before the tap response is delivered.
        NotificationManager.shared.onLimitResume = { providerId in
            Task { await store.resumePinnedLimit(providerId: providerId) }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if lock.isLocked {
                    // Nothing is read out of the Keychain and nothing polls until
                    // the device owner has proved they are present.
                    LockScreen()
                } else if store.needsOnboarding {
                    // No polling and no permission prompts until the user has been
                    // told what this app is and has a machine to poll.
                    OnboardingView()
                } else {
                    ContentView()
                        .onAppear {
                            NotificationManager.shared.requestAuthorization()
                            store.start()
                        }
                }
            }
            .environmentObject(store)
            .environmentObject(lock)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lock.didEnterBackground()
            case .active:     lock.willEnterForeground()
            default:          break
            }
        }
    }
}

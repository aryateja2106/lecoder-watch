import SwiftUI

@main
struct MeshRelayApp: App {
    @StateObject private var store: MeshStore

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
            if store.needsOnboarding {
                // No polling and no permission prompts until the user has been told
                // what this app is and has a machine to poll.
                OnboardingView()
                    .environmentObject(store)
            } else {
                ContentView()
                    .environmentObject(store)
                    .onAppear {
                        NotificationManager.shared.requestAuthorization()
                        store.start()
                    }
            }
        }
    }
}

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
        // Any other tap goes to Monitor, where the alert is actually readable.
        // Without this the tap falls through to the restored tab — the terminal,
        // which cannot attach — which is what made every alert look broken.
        NotificationManager.shared.onEventTap = { _, _ in
            Task { @MainActor in AppRouter.shared.tab = .monitor }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                    store.start()
                }
        }
    }
}

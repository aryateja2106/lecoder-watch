import SwiftUI

@main
struct MeshRelayApp: App {
    @StateObject private var store = MeshStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                    NotificationManager.shared.onLimitResume = { providerId in
                        Task { await store.resumePinnedLimit(providerId: providerId) }
                    }
                    store.start()
                }
        }
    }
}

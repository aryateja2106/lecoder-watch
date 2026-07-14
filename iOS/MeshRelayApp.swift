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
            ContentView()
                .environmentObject(store)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                    store.start()
                }
                // Dynamic Island / Lock Screen tap → meshwatch://session/<host>/<session>
                .onOpenURL { url in
                    guard url.scheme == "meshwatch", url.host == "session" else { return }
                    let parts = url.pathComponents.filter { $0 != "/" }
                    guard parts.count >= 2 else { return }
                    store.openSession(host: parts[0], session: parts[1].removingPercentEncoding ?? parts[1])
                }
        }
    }
}

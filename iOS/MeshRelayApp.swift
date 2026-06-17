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

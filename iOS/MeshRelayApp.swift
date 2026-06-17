import SwiftUI

@main
struct MeshRelayApp: App {
    @StateObject private var store = MeshStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                }
                // Poll only while the app is in front; pause when inactive/backgrounded so the
                // 8s fan-out doesn't keep waking the radio in the background.
                // ponytail: per-machine exponential backoff (brief #8) skipped — for a handful
                // of machines a flat in-foreground poll is cheap; add backoff if the mesh grows.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.start() } else { store.stop() }
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

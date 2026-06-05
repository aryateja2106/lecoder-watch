import Foundation
import WatchConnectivity

/// Phone side of the relay: receives commands from the watch, forwards the latest
/// mesh snapshot to the watch via WatchConnectivity (option A — the watch never
/// touches the mesh directly).
final class PhoneConnectivity: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    /// Set by MeshStore so we can service watch commands (send to agent, refresh).
    var commandHandler: ((WatchCommand) async -> Void)?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Push the latest snapshot to the watch (latest-wins).
    func push(_ snapshot: MeshSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try session.updateApplicationContext(["snapshot": data])
        } catch {
            // updateApplicationContext throws if called too fast; safe to drop — next tick replaces it.
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message["command"] as? Data,
              let command = try? JSONDecoder().decode(WatchCommand.self, from: data) else {
            replyHandler(["ok": false])
            return
        }
        Task {
            await commandHandler?(command)
            replyHandler(["ok": true])
        }
    }
}

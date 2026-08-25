import Foundation
import WatchConnectivity

/// Phone side of the relay: receives commands from the watch, forwards the latest
/// mesh snapshot to the watch via WatchConnectivity (option A — the watch never
/// touches the mesh directly).
final class PhoneConnectivity: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    /// Set by MeshStore so we can service watch commands (send to agent, refresh).
    /// Returns optional payload data for reads the watch is waiting on.
    var commandHandler: ((WatchCommand) async -> Data?)?

    /// Why the last snapshot did not reach the watch, or nil if it did. Read by the
    /// phone's own diagnostics — a silent failure here looks exactly like a watch
    /// that has gone quiet.
    @Published private(set) var lastPushFailure: String?

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
            lastPushFailure = nil
        } catch {
            // Called too fast is genuinely safe to drop — the next tick replaces it.
            // Too LARGE is not: every later snapshot carrying that screenshot fails the
            // same way, and the watch sits on stale data with no idea why. Keep the
            // reason so a screen that is not arriving can say something true.
            lastPushFailure = "\(error.localizedDescription) (\((try? JSONEncoder().encode(snapshot))?.count ?? 0) bytes)"
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    private func decodeCommand(_ payload: [String: Any]) -> WatchCommand? {
        guard let data = payload["command"] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchCommand.self, from: data)
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard let command = decodeCommand(message) else {
            replyHandler(["ok": false])
            return
        }
        Task {
            let data = await commandHandler?(command)
            var reply: [String: Any] = ["ok": true]
            if let data { reply["data"] = data }
            replyHandler(reply)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let command = decodeCommand(userInfo) else { return }
        Task { _ = await commandHandler?(command) }
    }
}

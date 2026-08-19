import Foundation
import WatchConnectivity

/// Thin WCSession wrapper for the watch. Receives relayed mesh snapshots from the
/// paired iPhone (the real-device path when the watch can't reach the tailnet
/// directly) and sends commands back. Nonisolated delegate, hops to the store.
final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchLink()

    var onSnapshot: ((MeshSnapshot) -> Void)?
    var onReachable: ((Bool) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var isReachable: Bool { WCSession.isSupported() && WCSession.default.isReachable }

    /// `queueIfUnreachable: false` drops the command instead of parking it in the
    /// user-info queue. Required for remote control: a click or keystroke delivered
    /// ten minutes late lands on whatever is on screen then, which is worse than
    /// losing it.
    func send(_ command: WatchCommand, queueIfUnreachable: Bool = true) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(command) else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(["command": data], replyHandler: nil, errorHandler: nil)
        } else if queueIfUnreachable {
            session.transferUserInfo(["command": data])
        }
    }

    private func decode(_ payload: [String: Any]) {
        guard let data = payload["snapshot"] as? Data,
              let snap = try? JSONDecoder().decode(MeshSnapshot.self, from: data) else { return }
        onSnapshot?(snap)
    }

    func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        onReachable?(s.isReachable)
    }
    func sessionReachabilityDidChange(_ s: WCSession) { onReachable?(s.isReachable) }
    func session(_ s: WCSession, didReceiveApplicationContext ctx: [String: Any]) { decode(ctx) }
    func session(_ s: WCSession, didReceiveUserInfo info: [String: Any]) { decode(info) }
}

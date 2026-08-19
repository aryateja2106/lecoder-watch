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

    /// Ask the phone something and wait for its answer. WCSession has always had a
    /// reply handler; not using it meant every read (clipboard, status, app list)
    /// simply had no answer whenever the watch was off the tailnet.
    func request(_ command: WatchCommand, timeout: TimeInterval = 6) async -> Data? {
        guard WCSession.isSupported(), let payload = try? JSONEncoder().encode(command) else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return nil }
        return await withCheckedContinuation { continuation in
            let once = Resumer(continuation)
            session.sendMessage(["command": payload]) { reply in
                once.finish(reply["data"] as? Data)
            } errorHandler: { _ in
                once.finish(nil)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.finish(nil) }
        }
    }

    /// WCSession can call neither handler (phone asleep), so the timeout has to be
    /// able to resume too — and a continuation resumed twice traps.
    private final class Resumer: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data?, Never>?
        init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
        func finish(_ data: Data?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: data)
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

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
            let once = Resumer<Data?>(continuation)
            session.sendMessage(["command": payload]) { reply in
                once.finish(reply["data"] as? Data)
            } errorHandler: { _ in
                once.finish(nil)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.finish(nil) }
        }
    }

    /// What became of a command the watch handed to the phone.
    ///
    /// `request` folds "the phone answered with nothing to say" and "nothing answered
    /// at all" into the same nil. For a *read* that is fine; for a *write* those are
    /// opposite facts — one is a keystroke delivered, the other a keystroke lost — and
    /// a wrist has no second screen to go and check on. So writes get their own answer.
    enum Ack: Sendable {
        case delivered(Data?)
        /// Parked for the phone to pick up when it next wakes. Not a delivery and not
        /// a failure: the command will run, just not now, and "later" is a different
        /// promise from "done" — one the user has to be told about rather than shown
        /// a tick for.
        case queued
        case failed(String)

        var isDelivered: Bool { if case .delivered = self { return true }; return false }
        var payload: Data? { if case .delivered(let data) = self { return data }; return nil }
    }

    /// Send, and wait for the phone to say it took it.
    ///
    /// `queueWhenUnreachable` mirrors `send`'s user-info queue for the commands where
    /// arriving late still beats not arriving (an agent reply); it stays off for the
    /// ones where it does not (a keystroke, a click).
    func acknowledge(_ command: WatchCommand, timeout: TimeInterval = 8,
                     queueWhenUnreachable: Bool = false) async -> Ack {
        guard WCSession.isSupported(), let payload = try? JSONEncoder().encode(command) else {
            return .failed("this watch cannot reach the iPhone")
        }
        let session = WCSession.default
        guard session.activationState == .activated else { return .failed("watch link not ready") }
        guard session.isReachable else {
            guard queueWhenUnreachable else { return .failed("iPhone not reachable") }
            session.transferUserInfo(["command": payload])
            return .queued
        }
        return await withCheckedContinuation { continuation in
            let once = Resumer<Ack>(continuation)
            session.sendMessage(["command": payload]) { reply in
                // The phone answers `ok: false` only when it could not decode the
                // command at all — a version skew between the two apps, which looks
                // exactly like a network failure unless it is named.
                if let ok = reply["ok"] as? Bool, !ok {
                    once.finish(.failed("iPhone could not read that command"))
                } else {
                    once.finish(.delivered(reply["data"] as? Data))
                }
            } errorHandler: { error in
                once.finish(.failed(Self.shortReason(error)))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.finish(.failed("iPhone did not answer"))
            }
        }
    }

    /// WCError's `localizedDescription` is a paragraph; a watch row is one line.
    private static func shortReason(_ error: Error) -> String {
        guard let wc = error as? WCError else { return "iPhone did not answer" }
        switch wc.code {
        case .notReachable, .sessionNotActivated, .deviceNotPaired, .companionAppNotInstalled:
            return "iPhone not reachable"
        case .deliveryFailed, .messageReplyFailed:
            return "iPhone did not take it"
        case .messageReplyTimedOut:
            return "iPhone did not answer in time"
        case .payloadTooLarge, .payloadUnsupportedTypes, .invalidParameter:
            return "the watch sent something the iPhone rejected"
        default:
            return "iPhone did not answer"
        }
    }

    /// WCSession can call neither handler (phone asleep), so the timeout has to be
    /// able to resume too — and a continuation resumed twice traps.
    private final class Resumer<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?
        init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
        func finish(_ value: T) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
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

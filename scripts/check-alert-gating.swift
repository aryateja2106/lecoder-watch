import Foundation

// The user report this guards against: "over 30 notifications of these alerts" in
// five minutes of a flapping connection. The gate has to make that scenario
// arithmetically impossible while still announcing a real outage and its recovery
// exactly once each. Pure simulation — no UNUserNotificationCenter, no timers.
@main
struct CheckAlertGating {
    static func main() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)

        // The reported disaster: a host flipping every 10 seconds for five minutes.
        // 30 transitions used to mean 30 banners; now it must be exactly two —
        // one "went offline" and the "back online" that answers it.
        var gate = ReachabilityAlertGate(cooldown: 600)
        var fired: [ReachabilityAlertGate.Alert] = []
        var reachable = true
        _ = gate.evaluate(host: "mac", reachable: true, now: t0)
        for step in 1...30 {
            reachable.toggle()
            if let alert = gate.evaluate(host: "mac", reachable: reachable,
                                         now: t0.addingTimeInterval(Double(step) * 10)) {
                fired.append(alert)
            }
        }
        assert(fired == [.wentOffline, .backOnline],
               "a 5-minute flap must produce exactly one offline/online pair, got \(fired)")

        // A second outage after the cooldown is real news again.
        assert(gate.evaluate(host: "mac", reachable: false, now: t0.addingTimeInterval(1000)) == .wentOffline,
               "an outage after the cooldown must alert")
        assert(gate.evaluate(host: "mac", reachable: true, now: t0.addingTimeInterval(1100)) == .backOnline)

        // First sighting is never an alert: launching the app with a machine already
        // offline is not an event, it's the starting state.
        var fresh = ReachabilityAlertGate(cooldown: 600)
        assert(fresh.evaluate(host: "pi", reachable: false, now: t0) == nil,
               "first observation must not alert")
        // ...and coming online from the never-seen state is also not a recovery.
        assert(fresh.evaluate(host: "pi", reachable: true, now: t0.addingTimeInterval(10)) == nil,
               "online after an unannounced offline must stay silent")

        // Hosts are independent: one machine's cooldown must not eat another's outage.
        var two = ReachabilityAlertGate(cooldown: 600)
        _ = two.evaluate(host: "a", reachable: true, now: t0)
        _ = two.evaluate(host: "b", reachable: true, now: t0)
        assert(two.evaluate(host: "a", reachable: false, now: t0.addingTimeInterval(10)) == .wentOffline)
        assert(two.evaluate(host: "b", reachable: false, now: t0.addingTimeInterval(11)) == .wentOffline,
               "per-host state must not be shared")

        // Event dedupe mirrors the daemon: identical alert text for the same session
        // inside the window is one banner; a different session or expired window is new.
        var dedupe = EventAlertDeduper(window: 600)
        assert(dedupe.shouldAlert(host: "mac", session: "s1", title: "Claude stopped", body: "done", now: t0))
        assert(!dedupe.shouldAlert(host: "mac", session: "s1", title: "Claude stopped", body: "done",
                                   now: t0.addingTimeInterval(30)),
               "identical alert inside the window must dedupe")
        assert(dedupe.shouldAlert(host: "mac", session: "s2", title: "Claude stopped", body: "done",
                                  now: t0.addingTimeInterval(31)),
               "a different session is a different alert")
        assert(dedupe.shouldAlert(host: "mac", session: "s1", title: "Claude stopped", body: "done",
                                  now: t0.addingTimeInterval(601)),
               "the window expiring makes the alert fresh again")

        print("check-alert-gating OK")
    }
}

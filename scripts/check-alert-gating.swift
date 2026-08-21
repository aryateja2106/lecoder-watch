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

        checkNotificationIds()
        checkAutoClear()

        print("check-alert-gating OK")
    }

    // The identifier is a contract with `collapseId` in meshd/push.ts: APNs stamps it as
    // the collapse id, the phone schedules local alerts under it, and the sweep below
    // matches on it. The literals here are pinned in check-mesh-push.sh too — if the two
    // languages drift, the phone quietly stops clearing pushed banners and nothing else
    // fails.
    static func checkNotificationIds() {
        assert(meshNotificationId(host: "studio", session: "api") == "mesh-studio-api")
        assert(meshNotificationId(host: "Aryas-MacBook-Pro", session: "deploy-api")
                == "mesh-Aryas-MacBook-Pro-deploy-api")
        // A session name is user-chosen and lands in an HTTP header; anything outside
        // the safe set is folded, on both sides identically.
        assert(meshNotificationId(host: "my host", session: "weird/session name")
                == "mesh-my_host-weird_session_name")

        // APNs rejects an oversized collapse id outright, so overflow must clamp rather
        // than truncate blindly: two long names that share their first 55 characters
        // still get different banners.
        let longA = meshNotificationId(host: String(repeating: "a", count: 40),
                                       session: String(repeating: "b", count: 40))
        let longB = meshNotificationId(host: String(repeating: "a", count: 40),
                                       session: String(repeating: "b", count: 41))
        assert(longA.utf8.count == 64 && longB.utf8.count == 64, "an id must never exceed 64 bytes")
        assert(longA != longB, "clamping must not collapse two different sessions into one banner")
        assert(longA == "mesh-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbb-5a32c2e2",
               "the hashed form is pinned against push.ts, got \(longA)")

        // Ownership, the tolerant direction. meshd stamps the id with the daemon's own
        // hostname while the phone knows the machine by whatever it paired under; an
        // exact-match-only test is how this feature ships green and does nothing.
        assert(meshNotificationId("mesh-dataflowagents-build", isFor: "dataflow", session: "build"),
               "the daemon's spelling of a host must still resolve to the paired one")
        assert(meshNotificationId("mesh-studio.local-api", isFor: "studio", session: "api"))
        assert(!meshNotificationId("mesh-studio-api", isFor: "pi", session: "api"),
               "a same-named session on another machine is a different banner")
        // A session name must match whole: `api` never claims a banner belonging to a
        // session called `apiserver`.
        assert(!meshNotificationId("mesh-studio-apiserver", isFor: "studio", session: "api"))
        assert(meshNotificationId("mesh-studio-legacy-api", isFor: "studio", session: "legacy-api"))

        // `-` is both the separator and a legal character in both halves, so
        // `mesh-studio-legacy-api` really is two readings: studio-legacy/api, or
        // studio/legacy-api. It resolves as a match for both, and that is the safe
        // direction on purpose — `notificationIdsToClear` keeps anything that might
        // still be waiting, and a banner that lingers one poll too long beats one that
        // vanishes while the agent is still stopped.
        assert(meshNotificationId("mesh-studio-legacy-api", isFor: "studio", session: "api"),
               "an ambiguous id must resolve toward keeping the banner, not deleting it")
        assert(notificationIdsToClear(delivered: ["mesh-studio-legacy-api"],
                                      attention: [("studio", "api")]).isEmpty)
    }

    // The user's complaint in one sentence: the banner should not outlive the wait.
    static func checkAutoClear() {
        let delivered = ["mesh-studio-api", "mesh-pi-build", "mesh-studio-web"]
        // studio/api is still waiting; the other two finished.
        let clear = notificationIdsToClear(delivered: delivered, attention: [("studio", "api")])
        assert(Set(clear) == ["mesh-pi-build", "mesh-studio-web"],
               "every session that stopped waiting loses its banner, got \(clear)")
        assert(!clear.contains("mesh-studio-api"), "a session still waiting keeps its banner")

        // Nobody waiting anywhere clears the lot; everybody waiting clears nothing.
        assert(Set(notificationIdsToClear(delivered: delivered, attention: [])) == Set(delivered))
        assert(notificationIdsToClear(delivered: delivered,
                                      attention: [("studio", "api"), ("pi", "build"), ("studio", "web")])
                .isEmpty)

        // This code deletes notifications, so anything it does not positively recognise
        // has to survive — including other apps' and our own other lanes'.
        let foreign = ["com.apple.reminders-1", "event-abc123", "reach-studio-false",
                       "usage-hit-claude-weekly-none", "meshsomething"]
        assert(notificationIdsToClear(delivered: foreign, attention: []).isEmpty,
               "a foreign identifier must never be swept, got \(notificationIdsToClear(delivered: foreign, attention: []))")

        // The usage-limit lane arms its alerts hours ahead and shares the `mesh-` prefix.
        // Sweeping one because no agent happens to be waiting would delete the "limit
        // resets now" banner the user pinned a session for.
        assert(notificationIdsToClear(delivered: ["mesh-limit-reset-claude-weekly"], attention: []).isEmpty,
               "a scheduled limit-reset banner is not an agent banner")

        // A session that finished between two polls: its banner was scheduled a second
        // out and has not landed yet. The pending id goes through the same filter, so
        // the alert never arrives at all.
        assert(notificationIdsToClear(delivered: ["mesh-pi-build"], attention: [("studio", "api")])
                == ["mesh-pi-build"])

        // And the pushed banner, whose id APNs took from the daemon's hostname.
        assert(notificationIdsToClear(delivered: ["mesh-dataflowagents-build"],
                                      attention: [("dataflow", "build")]).isEmpty,
               "a pushed banner for a session still waiting must survive the sweep")
        assert(notificationIdsToClear(delivered: ["mesh-dataflowagents-build"], attention: [])
                == ["mesh-dataflowagents-build"],
               "and be cleared by the same tolerant match once the wait is over")
    }
}

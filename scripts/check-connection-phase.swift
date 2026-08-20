import Foundation

// The watch reaches the mesh through the phone, and WCSession drops isReachable to
// false every few seconds when the phone app suspends. The whole point of
// connectionPhase is to NOT surface that flap as "offline" — so the thing worth
// pinning down is exactly the timing: a fresh snapshot is live, a missed poll or two
// is still "reconnecting" (keep showing the data), and only sustained silence is
// offline. Get the thresholds wrong and the app is either jumpy again or lies that it
// is connected when it is not.
@main
struct CheckConnectionPhase {
    static func main() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        // Never heard back: a cold start is "waiting", not "offline" — there is nothing
        // to be pessimistic about yet.
        assert(connectionPhase(lastContact: nil, now: t0) == .waiting,
               "no contact yet must be waiting, not offline")

        // A fresh snapshot is live.
        assert(connectionPhase(lastContact: t0, now: t0) == .live)
        assert(connectionPhase(lastContact: t0, now: t0.addingTimeInterval(6)) == .live,
               "one poll interval old is still live")
        assert(connectionPhase(lastContact: t0, now: t0.addingTimeInterval(19)) == .live,
               "just under the live window is still live")

        // The band the whole fix exists for: past 'live' but within grace, we keep the
        // last data and say reconnecting — a suspended phone that answers next poll must
        // never have flashed "offline" in between.
        assert(connectionPhase(lastContact: t0, now: t0.addingTimeInterval(21)) == .reconnecting,
               "just past live must be reconnecting, not offline")
        assert(connectionPhase(lastContact: t0, now: t0.addingTimeInterval(74)) == .reconnecting,
               "just under grace is still reconnecting")

        // Only sustained silence is offline.
        assert(connectionPhase(lastContact: t0, now: t0.addingTimeInterval(76)) == .offline,
               "past grace is genuinely offline")
        assert(connectionPhase(lastContact: t0, now: t0.addingTimeInterval(3600)) == .offline)

        // A single 6-second poll can never take us out of live from a fresh contact —
        // that is the property that makes it stop flapping. Prove it across the window.
        for missed in stride(from: 0.0, through: 18.0, by: 6.0) {
            assert(connectionPhase(lastContact: t0, now: t0.addingTimeInterval(missed)) == .live,
                   "\(missed)s (missed polls) must stay live")
        }

        // Boundaries are inclusive on the "still good" side: exactly at 'live' is live,
        // exactly at 'grace' is reconnecting — so a clock landing on the edge doesn't
        // tip the UI into the scarier state.
        assert(connectionPhase(lastContact: t0, now: t0.addingTimeInterval(20)) == .live)
        assert(connectionPhase(lastContact: t0, now: t0.addingTimeInterval(75)) == .reconnecting)

        print("check-connection-phase: OK")
    }
}

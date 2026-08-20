import Foundation

// A complication is the most-seen and least-interactive surface in the product: it is
// on the watch face all day and cannot ask a question. Its only real failure mode is
// confidently showing a number that stopped being true hours ago.
@main
struct CheckGlance {
    static func main() {
        let now = Date()
        let iso = ISO8601DateFormatter()
        func glance(minutesAgo: Int, waiting: Int, up: Int = 2, total: Int = 3) -> WatchGlance {
            WatchGlance(
                updatedISO: iso.string(from: now.addingTimeInterval(TimeInterval(-60 * minutesAgo))),
                waiting: (0..<waiting).map { .init(host: "studio", session: "s\($0)", line: "line \($0)") },
                machinesUp: up, machinesTotal: total,
            )
        }

        // Fresh, with agents waiting: the count is the headline everywhere.
        let busy = glance(minutesAgo: 1, waiting: 2)
        assert(!busy.isStale(now: now))
        assert(busy.shortLabel(now: now) == "2")
        assert(busy.headline(now: now) == "2 agents waiting")

        // One waiting: name it, and show what it asked.
        let one = glance(minutesAgo: 0, waiting: 1)
        assert(one.headline(now: now) == "s0")
        assert(one.detail(now: now) == "line 0")

        // Fresh, nothing waiting: fall back to how much of the mesh is up.
        let calm = glance(minutesAgo: 2, waiting: 0)
        assert(calm.shortLabel(now: now) == "2/3")
        assert(calm.headline(now: now) == "2 of 3 up")
        assert(glance(minutesAgo: 2, waiting: 0, up: 3, total: 3).headline(now: now) == "All machines up")

        // Stale is the case that matters. "2 agents waiting" from three hours ago sends
        // someone to their desk for nothing; it must degrade to an honest dash.
        let stale = glance(minutesAgo: 180, waiting: 2)
        assert(stale.isStale(now: now))
        assert(stale.shortLabel(now: now) == "—", "a stale glance must not assert a count")
        assert(stale.headline(now: now) == "Last seen 180m ago")
        assert(stale.detail(now: now) == "Open LeSearch Mesh")

        // The boundary itself counts as stale, so the timeline entry scheduled for that
        // exact moment shows the stale face rather than the confident one.
        let boundary = glance(minutesAgo: WatchGlance.staleAfterMinutes, waiting: 1)
        assert(boundary.isStale(now: now), "the staleness boundary must be inclusive")
        assert(!glance(minutesAgo: WatchGlance.staleAfterMinutes - 1, waiting: 1).isStale(now: now))

        // Never written at all: stale, and says what to do rather than "0".
        assert(WatchGlance.empty.isStale(now: now))
        assert(WatchGlance.empty.ageMinutes(now: now) == nil)
        assert(WatchGlance.empty.headline(now: now) == "Open to connect")

        // Fresh but nothing paired: not a mesh that is down, a mesh that is absent.
        let unpaired = glance(minutesAgo: 0, waiting: 0, up: 0, total: 0)
        assert(unpaired.headline(now: now) == "No machines")
        assert(unpaired.shortLabel(now: now) == "—", "0/0 is not a status")
        assert(unpaired.detail(now: now) == "Pair one on your iPhone")

        // Round-trips, because it crosses a process boundary as JSON.
        let encoded = try! JSONEncoder().encode(busy)
        assert(try! JSONDecoder().decode(WatchGlance.self, from: encoded) == busy)

        print("check-glance: OK")
    }
}

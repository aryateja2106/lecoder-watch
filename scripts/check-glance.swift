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
        // A verb, not a place: "Open LeSearch Mesh" names the app you are already
        // looking at a complication for. "Tap to reconnect" says what the tap does.
        assert(stale.detail(now: now) == "Tap to reconnect")

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

        // The three bands the rectangular family renders. The regression this guards:
        // with two agents waiting, headline/detail said "2 agents waiting" over a bare
        // session name and the question — the only actionable line — vanished exactly
        // when the face got busy.
        let twoBands = busy.entry(now: now)
        assert(twoBands.eyebrow == "2 WAITING")
        assert(twoBands.title == "s0 · studio", "name the session and its machine")
        assert(twoBands.body == "line 0", "the question survives a second waiting agent")

        let oneBand = one.entry(now: now)
        assert(oneBand.eyebrow == "WAITING ON YOU", "a count of one is not worth saying")
        assert(oneBand.body == "line 0")

        // The host is shortened, because "Aryas-MacBook-Pro.local · deploy-api" does not
        // fit on a watch face.
        let dotted = WatchGlance(updatedISO: iso.string(from: now),
                                 waiting: [.init(host: "Aryas-MacBook-Pro.local", session: "api",
                                                 line: "ok?", risky: true)],
                                 machinesUp: 1, machinesTotal: 1)
        assert(dotted.entry(now: now).title == "api · Aryas-MacBook-Pro")

        // All clear is stated, not implied by an absence.
        let clear = calm.entry(now: now)
        assert(clear.eyebrow == "ALL CLEAR")
        assert(clear.title == "Nothing waiting on you")
        assert(clear.body == "2 of 3 machines up")

        // Stale never asserts a count in any band.
        let staleBands = stale.entry(now: now)
        assert(staleBands.eyebrow.hasPrefix("LAST SEEN"))
        assert(!staleBands.title.contains("2"), "a stale face must not repeat the old count")
        assert(staleBands.title == "Tap to reconnect", "and must say what to do about it")

        let neverBands = WatchGlance.empty.entry(now: now)
        assert(neverBands.eyebrow == "NOT CONNECTED")

        let unpairedBands = unpaired.entry(now: now)
        assert(unpairedBands.eyebrow == "NOT PAIRED")
        assert(unpairedBands.title == "Pair a machine")

        // No band is ever blank where the widget renders one unconditionally.
        for bands in [twoBands, oneBand, clear, staleBands, neverBands, unpairedBands] {
            assert(!bands.eyebrow.isEmpty && !bands.title.isEmpty)
        }

        // Round-trips, because it crosses a process boundary as JSON.
        let encoded = try! JSONEncoder().encode(busy)
        assert(try! JSONDecoder().decode(WatchGlance.self, from: encoded) == busy)

        // A glance written by 0.2.0 has no `risky` key and must still decode, or the
        // complication goes blank for everyone mid-upgrade.
        let old = #"{"updatedISO":"2026-08-20T10:00:00Z","waiting":[{"host":"studio","session":"api","line":"ok?"}],"machinesUp":1,"machinesTotal":1}"#
        let decoded = try! JSONDecoder().decode(WatchGlance.self, from: Data(old.utf8))
        assert(decoded.waiting.first?.isRisky == false)

        print("check-glance: OK")
    }
}

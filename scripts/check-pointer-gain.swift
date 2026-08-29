import Foundation

// The gain curve decides whether the pad can both cross two screens and hit a close
// button. Both ends have to hold, and it must never invert.
@main
struct CheckPointerGain {
    static func main() {
        let base = 2.2

        // At rest and for tiny movements, stay near base so precision survives.
        assert(pointerGain(step: 0) == base)
        assert(pointerGain(step: 0.5) < base * 1.1)

        // Monotonic: faster must never move the cursor less.
        var previous = 0.0
        for step in stride(from: 0.0, through: 60.0, by: 0.5) {
            let travel = step * pointerGain(step: step)
            assert(travel >= previous, "gain inverted at step \(step)")
            previous = travel
        }

        // Clamped, so a flick cannot fling the cursor an unbounded distance.
        assert(pointerGain(step: 1_000) == base * 3.5)
        assert(pointerGain(step: 40) == pointerGain(step: 1_000), "ceiling should bind well before step 40")

        // A fast flick has to cross a 3432pt two-screen arrangement in a sane number of
        // swipes: ~150pt of watch travel per swipe at full gain.
        let perSwipe = 150.0 * pointerGain(step: 20)
        assert(perSwipe > 900, "a full-speed swipe should cover most of one screen, got \(perSwipe)")

        // Degenerate settings fall back to the base rather than exploding.
        assert(pointerGain(step: 10, softening: 0) == base)

        print("check-pointer-gain: OK")
    }
}

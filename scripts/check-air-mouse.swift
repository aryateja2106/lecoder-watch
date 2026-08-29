import Foundation
import CoreGraphics

// A wrist is never still. If the deadzone or the shaping is wrong the cursor either
// drifts on its own or lurches the moment you move.
@main
struct CheckAirMouse {
    static func main() {
        // Resting tremor produces nothing at all.
        assert(airMouseDelta(pitchRate: 0, yawRate: 0) == nil)
        assert(airMouseDelta(pitchRate: 0.04, yawRate: -0.03) == nil, "tremor must not move the cursor")

        // Crossing the deadzone starts from zero, not from a jump.
        let edge = airMouseDelta(pitchRate: 0, yawRate: 0.061)!
        assert(abs(edge.dx) < 0.2, "motion just past the deadzone should barely move, got \(edge.dx)")

        // Direction is preserved and symmetric.
        let right = airMouseDelta(pitchRate: 0, yawRate: 1.0)!
        let left = airMouseDelta(pitchRate: 0, yawRate: -1.0)!
        assert(right.dx > 0 && left.dx < 0)
        assert(abs(right.dx + left.dx) < 0.0001, "equal and opposite rotation must be equal and opposite")

        // Faster rotation always travels further.
        var previous = 0.0
        for rate in stride(from: 0.07, through: 6.0, by: 0.05) {
            let dx = airMouseDelta(pitchRate: 0, yawRate: rate)!.dx
            assert(dx >= previous, "air mouse gain inverted at \(rate)")
            previous = dx
        }

        // A brisk flick has to be able to cross a screen in about a second at 50Hz.
        let perSecond = airMouseDelta(pitchRate: 0, yawRate: 3.0)!.dx * 50
        assert(perSecond > 1200, "a brisk wrist turn should cross a display, got \(perSecond)pt/s")

        // Axes are independent.
        let vertical = airMouseDelta(pitchRate: 1.0, yawRate: 0)!
        assert(vertical.dx == 0 && vertical.dy > 0)

        assert(airMouseDelta(pitchRate: 1, yawRate: 1, sensitivity: 0) == nil)
        print("check-air-mouse: OK")
    }
}

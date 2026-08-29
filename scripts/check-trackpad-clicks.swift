import Foundation

// Full-pad trackpad: single tap = left click, second tap inside the window = right
// click. The window is the whole feel of the feature — too short and right click is
// unreachable at wrist ergonomics, too long and two deliberate approval taps become
// an accidental context menu. Pin it.
@main
struct CheckTrackpadClicks {
    static func main() {
        let t0 = Date(timeIntervalSince1970: 3_000_000)

        assert(trackpadDoubleTapWindow == 0.35,
               "the double-tap window is tuned by feel — change it deliberately, then update this check")

        // No previous tap: never a double tap, even at t=0.
        assert(!isDoubleTap(previous: nil, now: t0))

        // A quick tap-tap is a right click…
        assert(isDoubleTap(previous: t0, now: t0.addingTimeInterval(0.20)))
        assert(isDoubleTap(previous: t0, now: t0.addingTimeInterval(0.34)),
               "just inside the window still counts — being generous beats being twitchy")

        // …and two separate approval taps are not.
        assert(!isDoubleTap(previous: t0, now: t0.addingTimeInterval(0.36)))
        assert(!isDoubleTap(previous: t0, now: t0.addingTimeInterval(2.0)))

        // A "previous" tap in the future is clock weirdness, not a gesture.
        assert(!isDoubleTap(previous: t0.addingTimeInterval(5), now: t0))

        print("check-trackpad-clicks OK")
    }
}

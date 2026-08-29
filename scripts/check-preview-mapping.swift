import Foundation
import CoreGraphics

// Tap-to-place-cursor is the flagship interaction; if the preview is letterboxed and
// the mapping ignores it, every tap lands in the wrong place — silently.
@main
struct CheckPreviewMapping {
    static func near(_ a: Double, _ b: Double, _ tol: Double = 0.001) -> Bool { abs(a - b) < tol }

    static func main() {
        let box = CGSize(width: 160, height: 56)   // the watch preview slot, 2.857:1

        // Aspect matches the container: the image fills it, so mapping is direct.
        let exact = normalizedPreviewPoint(tap: CGPoint(x: 80, y: 28), container: box, imageAspect: 160.0 / 56.0)
        assert(near(exact!.x, 0.5) && near(exact!.y, 0.5))

        // Wider than the container (never happens here, but the branch must be right):
        // letterboxed top and bottom.
        let wide = normalizedPreviewPoint(tap: CGPoint(x: 80, y: 28), container: box, imageAspect: 4)
        assert(near(wide!.x, 0.5) && near(wide!.y, 0.5))
        assert(normalizedPreviewPoint(tap: CGPoint(x: 80, y: 2), container: box, imageAspect: 4) == nil,
               "tap above a pillarboxed image must be ignored")

        // Taller than the container: bars on the left and right. A 16:9 display
        // (1.778) in a 2.857 slot draws 99.5pt wide, centred at x 30.2…129.8.
        let lg = 1920.0 / 1080.0
        let drawn = 56.0 * lg
        let left = (160.0 - drawn) / 2
        assert(near(normalizedPreviewPoint(tap: CGPoint(x: 80, y: 28), container: box, imageAspect: lg)!.x, 0.5))
        assert(near(normalizedPreviewPoint(tap: CGPoint(x: left, y: 0), container: box, imageAspect: lg)!.x, 0))
        assert(near(normalizedPreviewPoint(tap: CGPoint(x: left + drawn, y: 56), container: box, imageAspect: lg)!.x, 1))
        assert(normalizedPreviewPoint(tap: CGPoint(x: 5, y: 28), container: box, imageAspect: lg) == nil,
               "tap in the left bar must be ignored, not clamped to the edge")

        // The built-in display (1.539) and the external one must not map alike.
        let builtin = 1512.0 / 982.0
        let a = normalizedPreviewPoint(tap: CGPoint(x: 50, y: 28), container: box, imageAspect: builtin)!
        let b = normalizedPreviewPoint(tap: CGPoint(x: 50, y: 28), container: box, imageAspect: lg)!
        assert(!near(a.x, b.x), "different display aspects must produce different targets")

        // Degenerate inputs.
        assert(normalizedPreviewPoint(tap: CGPoint(x: 0, y: 0), container: CGSize(width: 0, height: 0), imageAspect: 1.5) == nil)
        assert(normalizedPreviewPoint(tap: CGPoint(x: 0, y: 0), container: box, imageAspect: 0) == nil)

        print("OK: preview tap mapping")
    }
}

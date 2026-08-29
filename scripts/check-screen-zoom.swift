import Foundation
import CoreGraphics

// Aiming is the whole product on this screen. If the drawn cursor and the coordinate we
// send to the Mac disagree by even a few percent, every click lands next to the thing
// the user was looking at — and it looks like the daemon is wrong, not the geometry.
@main
struct CheckScreenZoom {
    static let container = CGSize(width: 390, height: 500)   // a phone, portrait
    static let wide = 1512.0 / 982.0                          // the built-in display
    static let ultra = 1920.0 / 1080.0                        // the external one

    static func main() {
        checkFit()
        checkNoZoomIsUntouched()
        checkPointerRoundTrip()
        checkOffsetNeverExposesBackground()
        checkMoveScalesWithZoom()
        checkClamps()
        checkDegenerate()
        checkTapInverse()
        print("check-screen-zoom: OK")
    }

    static func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.5) -> Bool { abs(a - b) <= tol }

    // The watch places the cursor by tapping the preview, so the tap inverse and the
    // cursor we draw have to be the same function read backwards. If they drift, the
    // pointer lands somewhere other than the pixel under the finger and it looks like
    // the Mac is wrong.
    static func checkTapInverse() {
        for zoom in [CGFloat(1), 2, 4] {
            for target in [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.93, y: 0.07)] {
                let cursor = CGPoint(x: 0.4, y: 0.6)   // where the view is currently centred
                let screen = pointerScreenPosition(pointer: target, imageAspect: wide,
                                                   container: container, zoom: zoom)
                // Draw with the *target* as the centring pointer, then invert with the
                // same one: the round trip must return the target.
                let back = normalizedPoint(fromTap: screen, pointer: target, imageAspect: wide,
                                           container: container, zoom: zoom)
                assert(back != nil, "a tap on the drawn cursor must map back, zoom \(zoom)")
                assert(near(back!.x, target.x, 0.002) && near(back!.y, target.y, 0.002),
                       "tap inverse drifted at zoom \(zoom): \(back!) vs \(target)")
                _ = cursor
            }
        }

        // At zoom 1 it must agree with the mapping the watch already shipped, or the
        // fit-to-screen behaviour silently changes underneath a tested feature.
        let tap = CGPoint(x: 137, y: 260)
        let a = normalizedPoint(fromTap: tap, pointer: CGPoint(x: 0.5, y: 0.5),
                                imageAspect: wide, container: container, zoom: 1)
        let b = normalizedPreviewPoint(tap: tap, container: container, imageAspect: wide)
        assert((a == nil) == (b == nil), "the two must agree about the letterbox")
        if let a, let b {
            assert(near(a.x, b.x, 0.001) && near(a.y, b.y, 0.001),
                   "zoom 1 must be exactly the old mapping, got \(a) vs \(b)")
        }

        // A tap in the letterbox points at no pixel and must not be clamped to an edge.
        let letterbox = CGPoint(x: container.width / 2, y: 4)
        assert(normalizedPoint(fromTap: letterbox, pointer: CGPoint(x: 0.5, y: 0.5),
                               imageAspect: wide, container: container, zoom: 1) == nil,
               "a tap above a letterboxed image must map to nothing, not to the top edge")
    }

    static func checkFit() {
        // A landscape screen in a portrait container is width-limited and letterboxed.
        let fit = fittedSize(imageAspect: wide, container: container)
        assert(near(fit.width, 390), "width-limited fit should fill the width, got \(fit.width)")
        assert(near(fit.height, 390 / CGFloat(wide)), "and keep the aspect, got \(fit.height)")
        assert(fit.height < container.height, "and letterbox vertically")

        // A tall image in a wide container is the other way round.
        let tall = fittedSize(imageAspect: 0.5, container: CGSize(width: 400, height: 200))
        assert(near(tall.height, 200) && near(tall.width, 100))
    }

    static func checkNoZoomIsUntouched() {
        // Fit-to-screen must behave exactly as it did before zoom existed, wherever the
        // pointer happens to be — otherwise adding zoom silently regresses the default.
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)] {
            let off = zoomedOffset(pointer: p, imageAspect: wide, container: container, zoom: 1)
            assert(off == .zero, "zoom 1 must never shift the image, got \(off) for \(p)")
        }
    }

    // The cursor is drawn from one function and the click is sent from another; they
    // agree only if the drawn position maps back to the normalized point.
    static func checkPointerRoundTrip() {
        for zoom in [CGFloat(1), 2, 3.5, 6] {
            for p in [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.1, y: 0.9), CGPoint(x: 0.83, y: 0.22)] {
                let screen = pointerScreenPosition(pointer: p, imageAspect: wide,
                                                   container: container, zoom: zoom)
                assert(screen.x.isFinite && screen.y.isFinite)
                // Invert: undo the offset and the scale, and we should land back on p.
                let fit = fittedSize(imageAspect: wide, container: container)
                let scaled = CGSize(width: fit.width * zoom, height: fit.height * zoom)
                let off = zoomedOffset(pointer: p, imageAspect: wide, container: container, zoom: zoom)
                let centre = CGPoint(x: container.width / 2 + off.width,
                                     y: container.height / 2 + off.height)
                let back = CGPoint(x: (screen.x - centre.x) / scaled.width + 0.5,
                                   y: (screen.y - centre.y) / scaled.height + 0.5)
                assert(near(back.x, p.x, 0.001) && near(back.y, p.y, 0.001),
                       "round trip failed at zoom \(zoom) for \(p): got \(back)")
            }
        }

        // Centred pointer, zoomed in: the cursor is drawn in the middle of the view.
        let mid = pointerScreenPosition(pointer: CGPoint(x: 0.5, y: 0.5), imageAspect: wide,
                                        container: container, zoom: 3)
        assert(near(mid.x, container.width / 2) && near(mid.y, container.height / 2))
    }

    static func checkOffsetNeverExposesBackground() {
        for zoom in [CGFloat(1.2), 2, 4, 6] {
            let fit = fittedSize(imageAspect: wide, container: container)
            let scaled = CGSize(width: fit.width * zoom, height: fit.height * zoom)
            for p in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0)] {
                let off = zoomedOffset(pointer: p, imageAspect: wide, container: container, zoom: zoom)
                let slackX = max(0, (scaled.width - container.width) / 2)
                let slackY = max(0, (scaled.height - container.height) / 2)
                assert(abs(off.width) <= slackX + 0.001,
                       "corner \(p) at zoom \(zoom) pulled the image off its own edge horizontally")
                assert(abs(off.height) <= slackY + 0.001,
                       "corner \(p) at zoom \(zoom) pulled the image off its own edge vertically")
            }
        }

        // The letterboxed axis has no overhang until zoom makes the image taller than
        // the container, so it must not slide at all before that.
        let fit = fittedSize(imageAspect: wide, container: container)
        let zoomStillShorter = (container.height / fit.height) * 0.9
        let off = zoomedOffset(pointer: CGPoint(x: 0.5, y: 1), imageAspect: wide,
                               container: container, zoom: zoomStillShorter)
        assert(near(off.height, 0, 0.001), "no vertical overhang yet, so no vertical slide")
    }

    static func checkMoveScalesWithZoom() {
        let start = CGPoint(x: 0.5, y: 0.5)
        let delta = CGSize(width: 39, height: 0)   // a tenth of the container's width
        let at1 = movedPointer(start, by: delta, imageAspect: wide, container: container, zoom: 1)
        let at3 = movedPointer(start, by: delta, imageAspect: wide, container: container, zoom: 3)
        assert(at1.x > start.x && at3.x > start.x, "both move the same direction")
        assert(near(CGFloat(at1.x - start.x), CGFloat(at3.x - start.x) * 3, 0.001),
               "the same finger travel must buy 3x less at 3x zoom — that is what zoom is for")

        // Clamped: dragging past the edge parks the pointer on the edge, never beyond,
        // because an off-image pointer cannot be clicked or found again.
        let far = movedPointer(start, by: CGSize(width: 10_000, height: 10_000),
                               imageAspect: wide, container: container, zoom: 1)
        assert(far.x == 1 && far.y == 1)
        let back = movedPointer(start, by: CGSize(width: -10_000, height: -10_000),
                                imageAspect: wide, container: container, zoom: 1)
        assert(back.x == 0 && back.y == 0)
    }

    static func checkClamps() {
        assert(clampedZoom(0.2) == 1, "never below fit — the picture would float in nothing")
        assert(clampedZoom(1) == 1)
        assert(clampedZoom(3.7) == 3.7)
        assert(clampedZoom(99) == 6, "past 6 a screenshot is being magnified past its detail")
    }

    // The picture arrives asynchronously, so every one of these runs at least once with
    // nothing to measure. None of them may divide by zero or return a NaN into a layout.
    static func checkDegenerate() {
        let empty = CGSize.zero
        assert(fittedSize(imageAspect: wide, container: empty) == .zero)
        assert(fittedSize(imageAspect: 0, container: container) == .zero)
        assert(zoomedOffset(pointer: CGPoint(x: 0.5, y: 0.5), imageAspect: 0,
                            container: container, zoom: 3) == .zero)
        let p = pointerScreenPosition(pointer: CGPoint(x: 0.5, y: 0.5), imageAspect: 0,
                                      container: container, zoom: 3)
        assert(p.x.isFinite && p.y.isFinite, "must not put a NaN into a frame")
        let moved = movedPointer(CGPoint(x: 0.5, y: 0.5), by: CGSize(width: 5, height: 5),
                                 imageAspect: wide, container: empty, zoom: 1)
        assert(moved == CGPoint(x: 0.5, y: 0.5), "no container yet means no movement, not a NaN")
        assert(movedPointer(CGPoint(x: 0.5, y: 0.5), by: CGSize(width: 5, height: 0),
                            imageAspect: wide, container: container, zoom: 0).x.isFinite,
               "a zero zoom must not divide by zero")

        // The second display has a different aspect, and switching to it must not carry
        // the first one's geometry over.
        let a = pointerScreenPosition(pointer: CGPoint(x: 0.9, y: 0.1), imageAspect: wide,
                                      container: container, zoom: 2)
        let b = pointerScreenPosition(pointer: CGPoint(x: 0.9, y: 0.1), imageAspect: ultra,
                                      container: container, zoom: 2)
        assert(a != b, "a different display aspect must place the cursor differently")
    }
}

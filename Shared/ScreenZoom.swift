import CoreGraphics

/// Geometry for a zoomable remote screen with a pointer drawn on it.
///
/// Remote control on a phone fails for one boring reason: at fit-to-screen a 1512-point
/// Mac display is about 390 points wide, so a click target is two or three pixels and
/// the real cursor is invisible. Zooming fixes the aiming problem and immediately
/// creates a navigation one — so the view follows the pointer instead of asking anyone
/// to pan it, which is why these two live in the same file.

/// The size the screenshot is drawn at when scaled to fit, before zoom.
///
/// `.scaledToFit` letterboxes on whichever axis does not match, and every other number
/// here has to agree with where the image actually lands or the pointer drifts off the
/// thing it is pointing at.
public func fittedSize(imageAspect: Double, container: CGSize) -> CGSize {
    guard imageAspect > 0, container.width > 0, container.height > 0 else { return .zero }
    let containerAspect = Double(container.width / container.height)
    return imageAspect > containerAspect
        ? CGSize(width: container.width, height: container.width / imageAspect)
        : CGSize(width: container.height * imageAspect, height: container.height)
}

/// How far to shift a zoomed image so `pointer` sits as close to the middle as the
/// edges allow.
///
/// Clamped, and the clamp is the whole point: without it, moving the pointer to a
/// corner drags the image away from the container and leaves a band of background
/// where the screen should be — which reads as a rendering bug, not as an edge.
/// At zoom 1 the result is always zero, so the fit-to-screen case is untouched.
public func zoomedOffset(pointer: CGPoint, imageAspect: Double,
                         container: CGSize, zoom: CGFloat) -> CGSize {
    let fit = fittedSize(imageAspect: imageAspect, container: container)
    guard fit != .zero, zoom > 1 else { return .zero }
    let scaled = CGSize(width: fit.width * zoom, height: fit.height * zoom)

    // Where the pointer currently is, measured from the image's centre.
    let wanted = CGSize(width: -(pointer.x - 0.5) * scaled.width,
                        height: -(pointer.y - 0.5) * scaled.height)

    // Never expose background: the image may only slide by its overhang.
    let slackX = max(0, (scaled.width - container.width) / 2)
    let slackY = max(0, (scaled.height - container.height) / 2)
    return CGSize(width: min(max(wanted.width, -slackX), slackX),
                  height: min(max(wanted.height, -slackY), slackY))
}

/// Where a normalized pointer lands inside the container, given the same zoom and
/// offset the image was drawn with. Used to draw the cursor on top of the picture.
public func pointerScreenPosition(pointer: CGPoint, imageAspect: Double,
                                  container: CGSize, zoom: CGFloat) -> CGPoint {
    let fit = fittedSize(imageAspect: imageAspect, container: container)
    guard fit != .zero else { return CGPoint(x: container.width / 2, y: container.height / 2) }
    let scaled = CGSize(width: fit.width * zoom, height: fit.height * zoom)
    let offset = zoomedOffset(pointer: pointer, imageAspect: imageAspect,
                              container: container, zoom: zoom)
    let centre = CGPoint(x: container.width / 2 + offset.width,
                         y: container.height / 2 + offset.height)
    return CGPoint(x: centre.x + (pointer.x - 0.5) * scaled.width,
                   y: centre.y + (pointer.y - 0.5) * scaled.height)
}

/// Move the pointer by a finger delta, in normalized units.
///
/// Divided by zoom on purpose: zooming in is how you aim at something small, so the
/// same finger travel has to buy proportionally less movement or the extra
/// magnification is wasted. Clamped to the screen because a pointer parked off-image
/// cannot be clicked and cannot be found again.
public func movedPointer(_ pointer: CGPoint, by delta: CGSize,
                         imageAspect: Double, container: CGSize, zoom: CGFloat) -> CGPoint {
    let fit = fittedSize(imageAspect: imageAspect, container: container)
    guard fit.width > 0, fit.height > 0 else { return pointer }
    let scaled = CGSize(width: fit.width * max(zoom, 0.01), height: fit.height * max(zoom, 0.01))
    let x = pointer.x + delta.width / scaled.width
    let y = pointer.y + delta.height / scaled.height
    return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
}

/// Zoom is clamped rather than free: below 1 the picture would float in the middle of
/// nothing, and past 6 a Retina screenshot is being magnified well beyond the detail it
/// contains, which looks broken rather than close.
public func clampedZoom(_ zoom: CGFloat) -> CGFloat { min(max(zoom, 1), 6) }

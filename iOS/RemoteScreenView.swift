import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Drive a Mac from the phone: its live screen, a pointer you can see, and a keyboard
/// with the modifiers that actually matter.
///
/// The thing that makes remote control on a phone usable is not the trackpad, it is
/// being able to *see where you are about to click*. At fit-to-screen a 1512-point
/// display is ~390 points wide, the real cursor is two pixels, and you are aiming
/// blind. So this draws its own pointer and sends absolute positions rather than
/// relative deltas (a drawn cursor and a relative protocol drift apart within seconds).
///
/// Zoom used to be the whole answer, with the view hard-centred on the pointer so
/// there was nothing to pan. That is steady but it makes the picture slide under your
/// finger constantly, and it is a blur: magnifying a 480–1400px downsample of a Retina
/// display shows bigger mush, not more detail. Two things fix it, and they need each
/// other:
///
///   * **Region capture** (meshd 0.5.0, "screenRegion"). Once zoomed, ask the daemon
///     for exactly the rect that is on screen, captured at native pixels. Same bytes,
///     real detail. Against an older daemon nothing is requested and nothing changes.
///   * **Drag to pan.** A sharp region is only worth having if you can choose it, so
///     the one-finger drag switches between moving the pointer and moving the view,
///     and the pointer only pushes the view when it reaches an edge.
@MainActor
final class RemoteScreenModel: ObservableObject {
    /// What the one-finger drag does. Two fingers always scroll the remote screen,
    /// which is why panning needed a mode rather than another gesture.
    enum DragMode: String {
        case pointer, pan
    }

    /// The decoded frame, not its bytes: the picture is measured (for the display's
    /// aspect) and drawn, and holding `Data` meant decoding the same JPEG twice for
    /// every one of the three frames a second.
    @Published private(set) var frame: UIImage?
    /// Which part of the display the picture in `frame` covers, normalized 0…1 with a
    /// top-left origin. The unit rect for a whole-screen frame; the requested crop when
    /// the daemon actually served one. Everything on top of the picture — the cursor,
    /// tap mapping — is positioned from the virtual full-display view (`zoom`/`pan`),
    /// so a crop that arrives one frame late is simply drawn where it belongs instead
    /// of snapping the world around.
    @Published private(set) var frameRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published var displays: [DisplayInfo] = []
    @Published var activeDisplay: Int = 1 {
        didSet { if oldValue != activeDisplay { displayChanged() } }
    }
    @Published var status: InputStatus?
    @Published var platform: String?
    @Published var capabilities: [String] = []
    @Published var note: String?

    /// Normalized 0…1 within the active display. The single source of truth for both
    /// the cursor we draw and the coordinate we send.
    @Published var pointer = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var zoom: CGFloat = 1
    /// Offset of the view's centre from the display's centre, as a fraction of the
    /// whole display — the same units `clampedPan`/`visibleRect` speak, so the rect we
    /// draw with and the rect we ask the daemon to capture can never disagree.
    @Published private(set) var pan: CGPoint = .zero
    @Published var dragMode: DragMode = .pointer
    /// Sticky modifiers, cleared by the next non-modifier key — so ⌘⇧4 works.
    @Published var mods: Set<String> = []

    /// No frame for longer than `staleAfter`. The picture is then a photograph of the
    /// past, so it is dimmed and every click is refused: a tap aimed at a stale frame
    /// lands wherever that window has since moved to, which is the one failure mode a
    /// remote pointer must not have.
    @Published private(set) var stale = false
    @Published private(set) var lastFrameAt: Date?
    /// Measured from a *full* frame only — a crop's own aspect describes the crop.
    @Published private(set) var measuredAspect: Double?

    /// The screen surface's size in points, republished by the view. Held here so the
    /// polling loop can work out which region to ask for without a view in hand.
    var containerSize: CGSize = .zero

    let machine: Machine
    /// The session (and pane) this screen was opened for, when it was opened from one.
    /// That is what makes "paste into the agent" possible instead of only "paste into
    /// whatever happens to have focus".
    let session: String?
    let pane: String?

    private static let staleAfter: TimeInterval = 8

    private var client: MeshClient { MeshClient(machine: machine, capabilities: capabilities) }
    private var pump: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private var flush: Task<Void, Never>?
    private var frameKick: Task<Void, Never>?
    private var pendingPointer: CGPoint?

    /// Linux meshd serves input, files and a shell but cannot capture a screen, so the
    /// picture is the one part of this view that legitimately never arrives.
    var canSeeScreen: Bool { capabilities.isEmpty || capabilities.contains("screenPeek") }
    var supportsRegion: Bool { capabilities.contains("screenRegion") }
    var supportsPaste: Bool { capabilities.contains("paste") }
    var pasteModifier: String { (platform ?? "darwin").hasPrefix("darwin") ? "cmd" : "ctrl" }

    /// Staleness only means anything where a stream was expected in the first place.
    var inputBlocked: Bool { stale && canSeeScreen }

    init(machine: Machine, session: String? = nil, pane: String? = nil) {
        self.machine = machine
        self.session = session
        self.pane = pane
    }

    /// The FULL display's aspect, whatever the last picture happened to cover.
    var imageAspect: Double {
        if let measuredAspect, measuredAspect > 0 { return measuredAspect }
        return displays.first { $0.index == activeDisplay }?.aspect ?? 1.6
    }

    private var displayArgument: Int {
        displays.first { $0.index == activeDisplay }?.index ?? displays.first?.index ?? 1
    }

    private func aspect(_ size: CGSize) -> Double {
        size.height > 0 ? Double(size.width / size.height) : 0
    }

    // MARK: Lifecycle

    func start() {
        Task { await refreshMeta() }
        // Count the stall from the moment we started asking, not from the first frame:
        // a machine that never answers at all should say so rather than spin forever.
        lastFrameAt = Date()
        stale = false
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshScreen()
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    func stop() {
        pump?.cancel(); pump = nil
        clock?.cancel(); clock = nil
        flush?.cancel(); flush = nil
        frameKick?.cancel(); frameKick = nil
    }

    /// The retry behind the "Reconnecting…" overlay: tear the polling down and stand it
    /// back up, so a socket wedged behind a sleeping Mac is actually replaced.
    func retry() {
        stop()
        start()
    }

    private func tick() {
        guard canSeeScreen, let lastFrameAt else { stale = false; return }
        stale = Date().timeIntervalSince(lastFrameAt) > Self.staleAfter
    }

    private func refreshMeta() async {
        status = try? await client.inputStatus()
        let health = try? await client.healthInfo()
        platform = health?.platform
        capabilities = health?.capabilities ?? []
        if let list = try? await client.displays(), list.ok {
            displays = list.displays
            if !displays.contains(where: { $0.index == activeDisplay }) {
                activeDisplay = displays.first(where: { $0.main == true })?.index ?? displays.first?.index ?? 1
            }
        }
    }

    private func displayChanged() {
        measuredAspect = nil
        frameRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        zoom = 1
        pan = .zero
        dragMode = .pointer
        kickFrame(after: 0)
    }

    // MARK: Frames

    private func refreshScreen() async {
        guard canSeeScreen else { return }
        let container = containerSize
        let containerAspect = aspect(container)
        // Only crop where a crop is both possible and worth it: at 1× the region *is*
        // the screen, and an old daemon must never be asked for one at all.
        let wantsRegion = supportsRegion && zoom > 1.05 && containerAspect > 0
        var requested: CGRect? = wantsRegion
            ? visibleRect(zoom: zoom, pan: pan, containerAspect: containerAspect, imageAspect: imageAspect)
            : nil
        // Never ask for a crop we would not recognise coming back. Just past 1× the
        // region is nearly the display's own shape, and a full frame answered on that
        // request would be read as a crop and drawn 5% off — every click landing beside
        // what you aimed at. That band is worth nothing anyway: it is the same picture.
        if let rect = requested, !cropIsDistinguishable(rect) { requested = nil }
        // Native pixels are the entire point of a region capture, but just past 1× the
        // region is nearly the whole display and "native" is a multi-megabyte frame
        // three times a second. The cap only lifts once the region is genuinely small.
        let width: Int?
        if requested == nil {
            width = zoom > 2 ? 2000 : 1400
        } else {
            width = zoom >= 2 ? nil : 2000
        }
        guard let shot = try? await client.screenImage(display: displayArgument, width: width,
                                                       rect: requested,
                                                       quality: requested == nil ? nil : 80)
        else { return }
        apply(jpeg: shot, requested: requested)
    }

    /// Coalesced re-request after the view moved. A pinch fires on every touch frame;
    /// one request per callback would be a queue of stale regions landing after the
    /// fingers stopped, which is exactly the bug the pointer send already avoids.
    func kickFrame(after ms: Int = 120) {
        frameKick?.cancel()
        frameKick = Task { [weak self] in
            if ms > 0 { try? await Task.sleep(for: .milliseconds(ms)) }
            guard !Task.isCancelled else { return }
            await self?.refreshScreen()
        }
    }

    private func apply(jpeg data: Data, requested: CGRect?) {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return }
        let served = Double(image.size.width / image.size.height)
        if let requested, servedLooksLikeCrop(servedAspect: served, requested: requested) {
            frameRect = requested
        } else {
            frameRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            measuredAspect = served
        }
        frame = image
        lastFrameAt = Date()
        stale = false
    }

    /// Did the daemon actually crop?
    ///
    /// meshd answers a region on the same route as a full frame and only says which by
    /// an `x-mesh-rect` response header — which the client hands back as bare bytes, so
    /// the header is not available here. The shape of the picture has to settle it: a
    /// crop of `requested` comes back with that rect's aspect on the display, a full
    /// frame with the display's own. Treat it as a crop only when those two are far
    /// enough apart to be told apart *and* the picture matches the crop — otherwise
    /// assume full frame, which is the reading that stays correct when we are wrong.
    private func servedLooksLikeCrop(servedAspect: Double, requested: CGRect) -> Bool {
        guard cropIsDistinguishable(requested) else { return false }
        let expected = imageAspect * Double(requested.width / requested.height)
        return relativeGap(servedAspect, expected) < 0.03
    }

    /// Would a picture of this region be tellable apart from a picture of the whole
    /// display? Asked before requesting as well as after answering, so the two can
    /// never disagree about which frames are interpretable.
    private func cropIsDistinguishable(_ rect: CGRect) -> Bool {
        let display = imageAspect
        guard display > 0, rect.width > 0, rect.height > 0 else { return false }
        return relativeGap(display * Double(rect.width / rect.height), display) > 0.05
    }

    private func relativeGap(_ a: Double, _ b: Double) -> Double {
        guard a > 0, b > 0 else { return .infinity }
        return abs(a - b) / max(a, b)
    }

    // MARK: Geometry

    /// Where the *whole display* would be drawn at the current zoom and pan: the centre
    /// of that virtual picture, and its size in points. Everything else — the crop's
    /// placement, the cursor, the inverse of a tap — is one line off this pair, which is
    /// what keeps them from ever disagreeing.
    func layout(container: CGSize) -> (centre: CGPoint, scaled: CGSize) {
        let middle = CGPoint(x: container.width / 2, y: container.height / 2)
        let fit = fittedSize(imageAspect: imageAspect, container: container)
        guard fit.width > 0, fit.height > 0 else { return (middle, .zero) }
        let scaled = CGSize(width: fit.width * zoom, height: fit.height * zoom)
        let p = clampedPan(pan, zoom: zoom, containerAspect: aspect(container), imageAspect: imageAspect)
        return (CGPoint(x: middle.x - p.x * scaled.width,
                        y: middle.y - p.y * scaled.height), scaled)
    }

    /// Which point on the remote display a container point refers to. Nil in the
    /// letterbox, which points at nothing.
    func displayPoint(at location: CGPoint, container: CGSize) -> CGPoint? {
        let lay = layout(container: container)
        guard lay.scaled.width > 0, lay.scaled.height > 0 else { return nil }
        let x = (location.x - lay.centre.x) / lay.scaled.width + 0.5
        let y = (location.y - lay.centre.y) / lay.scaled.height + 0.5
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        return CGPoint(x: x, y: y)
    }

    // MARK: Zoom and pan

    /// Set the zoom, optionally keeping one display point pinned under one container
    /// point — the anchor that makes a pinch feel attached to the picture instead of to
    /// the middle of the phone.
    func setZoom(_ target: CGFloat, anchor: CGPoint? = nil, at location: CGPoint? = nil,
                 container: CGSize? = nil, refresh: Bool = true) {
        let box = container ?? containerSize
        let z = clampedZoom(target)
        let fit = fittedSize(imageAspect: imageAspect, container: box)
        if z <= 1 {
            zoom = 1
            pan = .zero
            dragMode = .pointer
        } else if let anchor, let location, fit.width > 0, fit.height > 0 {
            let scaledW = fit.width * z, scaledH = fit.height * z
            let wanted = CGPoint(x: (anchor.x - 0.5) - (location.x - box.width / 2) / scaledW,
                                 y: (anchor.y - 0.5) - (location.y - box.height / 2) / scaledH)
            zoom = z
            pan = clampedPan(wanted, zoom: z, containerAspect: aspect(box), imageAspect: imageAspect)
        } else {
            zoom = z
            pan = clampedPan(pan, zoom: z, containerAspect: aspect(box), imageAspect: imageAspect)
        }
        if refresh { kickFrame() }
    }

    func pinch(scale: CGFloat, at location: CGPoint, container: CGSize) {
        let target = clampedZoom(zoom * scale)
        guard target != zoom else { return }
        setZoom(target, anchor: displayPoint(at: location, container: container),
                at: location, container: container, refresh: false)
    }

    /// Double-tap in pan mode: 2× → 4× → fit, anchored where you tapped. Pointer mode
    /// keeps its double-click, which is how you open anything.
    func cycleZoom(at location: CGPoint, container: CGSize) {
        let next: CGFloat = zoom < 1.5 ? 2 : (zoom < 3 ? 4 : 1)
        setZoom(next, anchor: displayPoint(at: location, container: container),
                at: location, container: container)
    }

    func panView(by delta: CGSize) {
        guard zoom > 1 else { return }
        let box = containerSize
        let fit = fittedSize(imageAspect: imageAspect, container: box)
        guard fit.width > 0, fit.height > 0 else { return }
        let scaled = CGSize(width: fit.width * zoom, height: fit.height * zoom)
        pan = clampedPan(CGPoint(x: pan.x - delta.width / scaled.width,
                                 y: pan.y - delta.height / scaled.height),
                         zoom: zoom, containerAspect: aspect(box), imageAspect: imageAspect)
    }

    /// A gesture finished: whatever the view now shows is what to capture sharply.
    func gestureEnded() { kickFrame() }

    func setDragMode(_ mode: DragMode) {
        dragMode = mode
        if mode == .pan {
            // Panning a fit-to-screen picture moves nothing, so entering the mode is
            // also the request to zoom — otherwise the toggle looks broken.
            if zoom <= 1 { setZoom(2) }
            flash("Pan the view · double-tap to zoom")
        } else {
            flash("Move the pointer")
        }
    }

    func resetZoom() {
        setZoom(1)
        flash("Fit to screen")
    }

    // MARK: Pointer

    func movePointer(by delta: CGSize) {
        guard !inputBlocked else { return }
        pointer = movedPointer(pointer, by: delta, imageAspect: imageAspect,
                               container: containerSize, zoom: zoom)
        followPointer()
        schedulePointerSend()
    }

    func placePointer(at normalized: CGPoint) {
        guard !inputBlocked else { return }
        pointer = normalized
        followPointer()
        schedulePointerSend()
    }

    /// Nudge the view only when the pointer is about to leave it. Hard-centring the
    /// pointer (what this used to do) means the picture slides under every finger
    /// movement; edge-following keeps it still until it has to move, which is also what
    /// stops the region request from changing on every frame.
    private func followPointer() {
        guard zoom > 1 else { pan = .zero; return }
        let box = containerSize
        let containerAspect = aspect(box)
        guard containerAspect > 0 else { return }
        let view = visibleRect(zoom: zoom, pan: pan,
                               containerAspect: containerAspect, imageAspect: imageAspect)
        let marginX = Double(view.width) * 0.12
        let marginY = Double(view.height) * 0.12
        var dx = 0.0, dy = 0.0
        let px = Double(pointer.x), py = Double(pointer.y)
        if px < Double(view.minX) + marginX { dx = px - (Double(view.minX) + marginX) }
        if px > Double(view.maxX) - marginX { dx = px - (Double(view.maxX) - marginX) }
        if py < Double(view.minY) + marginY { dy = py - (Double(view.minY) + marginY) }
        if py > Double(view.maxY) - marginY { dy = py - (Double(view.maxY) - marginY) }
        guard dx != 0 || dy != 0 else { return }
        pan = clampedPan(CGPoint(x: Double(pan.x) + dx, y: Double(pan.y) + dy),
                         zoom: zoom, containerAspect: containerAspect, imageAspect: imageAspect)
        kickFrame(after: 250)
    }

    /// Coalesced: a drag fires far faster than a network round-trip, and one request per
    /// callback turns a smooth swipe into a queue of stale positions landing after the
    /// finger stopped. Absolute positions mean dropping the intermediate ones is free.
    private func schedulePointerSend() {
        pendingPointer = pointer
        guard flush == nil else { return }
        flush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            await self?.flushPointer()
        }
    }

    private func flushPointer() async {
        flush = nil
        guard let p = pendingPointer, !inputBlocked else { pendingPointer = nil; return }
        pendingPointer = nil
        try? await client.input([.moveTo(x: p.x, y: p.y, display: displayArgument)])
    }

    /// Land the pointer where it is drawn before acting, so a click can never fire at a
    /// position the coalescing timer has not sent yet.
    func click(_ button: String = "left", count: Int = 1) {
        guard !inputBlocked else { flash(staleNote); return }
        let p = pointer
        Task {
            try? await client.input([.moveTo(x: p.x, y: p.y, display: displayArgument),
                                     .click(button, count: count)])
        }
        pendingPointer = nil
    }

    func dragBegan() { send([.hold]) }
    func dragEnded() { send([.release]) }

    func scroll(_ delta: CGSize) {
        send([.scroll(dx: Double(-delta.width), dy: Double(-delta.height))])
    }

    func send(_ events: [InputEvent]) {
        guard !inputBlocked else { flash(staleNote); return }
        Task { try? await client.input(events) }
    }

    private var staleNote: String { "No picture from \(machine.host) — reconnect first" }

    // MARK: Keyboard

    func toggleMod(_ mod: String) {
        if mods.contains(mod) { mods.remove(mod) } else { mods.insert(mod) }
    }

    func pressKey(_ key: String) {
        send([.key(key, Array(mods))])
        mods.removeAll()          // sticky until a real key, so ⌘⇧4 works
    }

    func type(_ text: String) {
        guard !text.isEmpty else { return }
        send([.text(text)])
        mods.removeAll()
    }

    // MARK: Clipboard and view

    func recenterPointer() {
        guard !inputBlocked else { flash(staleNote); return }
        pointer = CGPoint(x: 0.5, y: 0.5)
        followPointer()
        schedulePointerSend()
        flash("Pointer recentred")
    }

    /// Paste what is on the phone into whatever has focus on the Mac. Two steps, because
    /// the far side pastes from its own clipboard: put the text there, then press the
    /// paste chord.
    func pasteFromPhone() {
        guard !inputBlocked else { flash(staleNote); return }
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            flash("Nothing on this phone's clipboard"); return
        }
        Task {
            do {
                try await client.setClipboard(text)
                try await client.input([.key("v", [pasteModifier])])
                flash("Pasted \(text.count) characters")
            } catch {
                flash("Could not paste")
            }
        }
    }

    /// Paste straight into the session this screen was opened for, bypassing focus and
    /// the clipboard chord entirely. meshd 0.5.0 ("paste") delivers it as one bracketed
    /// paste, so a TUI receives a single block instead of a submit per newline; an older
    /// daemon silently types it, which is the behavior we already had.
    func pasteIntoSession() {
        guard let session else { flash("This screen isn't attached to a session"); return }
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            flash("Nothing on this phone's clipboard"); return
        }
        Task {
            do {
                try await client.send(agent: session, text: text, pane: pane, paste: true)
                flash("\(supportsPaste ? "Pasted" : "Typed") \(text.count) characters into \(session)")
            } catch {
                flash("Could not paste into \(session)")
            }
        }
    }

    /// The inverse, which is the one you want after an agent prints a URL or a token.
    func copyFromMachine() {
        Task {
            if let text = try? await client.clipboard(), !text.isEmpty {
                // Whatever the Mac had on its clipboard — which, per this screen's own
                // reason for existing, is often a token or a key an agent printed. Do
                // not sync that to every device on the Apple ID; expire it instead.
                UIPasteboard.general.setItems(
                    [[UTType.plainText.identifier: text]],
                    options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
                flash("Copied \(text.count) characters from \(machine.host)")
            } else {
                flash("\(machine.host)'s clipboard is empty")
            }
        }
    }

    func flash(_ message: String) {
        note = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if note == message { note = nil }
        }
    }
}

// MARK: - Gestures

/// Trackpad semantics need UIKit: SwiftUI cannot tell a one-finger drag from a
/// two-finger one, and that difference is move-versus-scroll — the whole gesture
/// vocabulary of a trackpad.
struct TrackpadSurface: UIViewRepresentable {
    var onMove: (CGSize) -> Void            // incremental finger delta, in points
    var onScroll: (CGSize) -> Void
    var onTap: (CGPoint) -> Void            // location in the surface
    var onDoubleTap: (CGPoint) -> Void
    var onSecondaryTap: () -> Void
    var onZoom: (CGFloat, CGPoint) -> Void  // incremental scale factor, pinch centroid
    var onDragBegan: () -> Void
    var onDragEnded: () -> Void
    /// Any pan or pinch finished. The region capture hangs off this: it is the moment
    /// the view has settled on what it wants to be shown sharply.
    var onGestureEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let c = context.coordinator

        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let twoFinger = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.scroll(_:)))
        twoFinger.minimumNumberOfTouches = 2
        twoFinger.maximumNumberOfTouches = 2
        view.addGestureRecognizer(twoFinger)

        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        view.addGestureRecognizer(pinch)
        // Pinch and two-finger pan both start with two fingers down; letting them run
        // together is what makes "zoom in a bit while nudging the view" feel normal.
        pinch.delegate = c
        twoFinger.delegate = c

        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        view.addGestureRecognizer(double)

        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: double)          // or every double-click is also two singles
        view.addGestureRecognizer(tap)

        let twoTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.secondary(_:)))
        twoTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoTap)

        // Press-and-hold then move is a drag on a real trackpad: button down, move,
        // release. Without it you cannot move a window or select text.
        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = .greatestFiniteMagnitude
        view.addGestureRecognizer(hold)

        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TrackpadSurface
        private var lastPan = CGPoint.zero
        private var lastScroll = CGPoint.zero
        private var dragging = false

        init(_ parent: TrackpadSurface) { self.parent = parent }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            if g.state == .began { lastPan = .zero }
            parent.onMove(CGSize(width: t.x - lastPan.x, height: t.y - lastPan.y))
            lastPan = t
            if g.state == .ended || g.state == .cancelled {
                lastPan = .zero
                if dragging { dragging = false; parent.onDragEnded() }
                parent.onGestureEnded()
            }
        }

        @objc func scroll(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            if g.state == .began { lastScroll = .zero }
            parent.onScroll(CGSize(width: t.x - lastScroll.x, height: t.y - lastScroll.y))
            lastScroll = t
            if g.state == .ended || g.state == .cancelled { lastScroll = .zero }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard g.state == .changed || g.state == .ended else { return }
            parent.onZoom(g.scale, g.location(in: g.view))
            g.scale = 1
            if g.state == .ended { parent.onGestureEnded() }
        }

        @objc func tap(_ g: UITapGestureRecognizer) { parent.onTap(g.location(in: g.view)) }
        @objc func doubleTap(_ g: UITapGestureRecognizer) { parent.onDoubleTap(g.location(in: g.view)) }
        @objc func secondary(_ g: UITapGestureRecognizer) { parent.onSecondaryTap() }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            if g.state == .began { dragging = true; parent.onDragBegan() }
            if g.state == .ended || g.state == .cancelled, dragging {
                dragging = false; parent.onDragEnded()
            }
        }
    }
}

// MARK: - The screen

struct RemoteScreenView: View {
    @StateObject private var remote: RemoteScreenModel
    @State private var typing = ""
    @State private var keyboardUp = false
    /// Every overlay gone, leaving the picture. Tapping the picture brings them back —
    /// which is why this mode does not click: it is the "just show me the Mac" mode.
    @State private var chromeHidden = false
    @FocusState private var typingFocused: Bool

    init(machine: Machine, session: String? = nil, pane: String? = nil) {
        _remote = StateObject(wrappedValue: RemoteScreenModel(machine: machine, session: session, pane: pane))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                screenSurface
                if !chromeHidden {
                    if let status = remote.status, status.ok, !status.trusted { notTrustedBanner(status) }
                    controlBar
                    if keyboardUp { keyboardPane }
                }
            }
        }
        .navigationTitle(remote.machine.host)
        .navigationBarTitleDisplayMode(.inline)
        // The tab bar costs ~80 points of a screen whose entire job is showing another
        // screen, and it is the one place in the app you have already arrived at.
        .toolbar(.hidden, for: .tabBar)
        .toolbar(chromeHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar { toolbarContent }
        .statusBarHidden(chromeHidden)
        .overlay(alignment: .top) { toast }
        .animation(.easeInOut(duration: 0.2), value: chromeHidden)
        .onAppear { remote.start() }
        .onDisappear { remote.stop() }
    }

    // MARK: Screen, pointer, gestures

    private var screenSurface: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if let image = remote.frame {
                    picture(image: image, in: size)
                        .opacity(remote.stale ? 0.3 : 1)
                } else if !remote.canSeeScreen {
                    ContentUnavailableView {
                        Label("No screen to show", systemImage: "display.slash")
                    } description: {
                        Text("\(remote.machine.host) runs Linux, where meshd can send keys and clicks but cannot capture the screen. The trackpad and keyboard below still work.")
                    }
                } else if !remote.stale {
                    VStack(spacing: 10) {
                        ProgressView().tint(.secondary)
                        Text("Waiting for \(remote.machine.host)'s screen")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if remote.frame != nil, !remote.stale { pointerCursor(in: size) }

                TrackpadSurface(
                    onMove: { delta in
                        if chromeHidden || remote.dragMode == .pan {
                            remote.panView(by: delta)
                        } else {
                            remote.movePointer(by: delta)
                        }
                    },
                    onScroll: { if !chromeHidden { remote.scroll($0) } },
                    onTap: { location in
                        if chromeHidden {
                            chromeHidden = false
                        } else if remote.dragMode == .pointer {
                            remote.click()
                        } else if let point = remote.displayPoint(at: location, container: size) {
                            // Pan mode aims rather than clicks: pan until the thing is
                            // on screen, tap to put the cursor on it, click deliberately.
                            // A tap that both moved the view and fired a click is how you
                            // lose a window.
                            remote.placePointer(at: point)
                        }
                    },
                    onDoubleTap: { location in
                        if chromeHidden || remote.dragMode == .pan {
                            remote.cycleZoom(at: location, container: size)
                        } else {
                            remote.click(count: 2)
                        }
                    },
                    onSecondaryTap: { if !chromeHidden, remote.dragMode == .pointer { remote.click("right") } },
                    onZoom: { scale, location in remote.pinch(scale: scale, at: location, container: size) },
                    onDragBegan: { if !chromeHidden, remote.dragMode == .pointer { remote.dragBegan() } },
                    onDragEnded: { if !chromeHidden, remote.dragMode == .pointer { remote.dragEnded() } },
                    onGestureEnded: { remote.gestureEnded() },
                )

                if remote.stale { reconnectingOverlay }
                if chromeHidden { showChromeHint }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .onChange(of: size, initial: true) { _, new in remote.containerSize = new }
        }
    }

    /// The picture, wherever on the virtual full-display view it belongs. A whole-screen
    /// frame covers the unit rect and lands exactly where `.scaledToFit().scaleEffect()`
    /// used to put it; a native-resolution crop covers its own rect and lands inside the
    /// same frame — including while it is one gesture out of date, which is what makes a
    /// pinch look continuous rather than snapping when the sharp frame arrives.
    private func picture(image: UIImage, in size: CGSize) -> some View {
        let lay = remote.layout(container: size)
        let rect = remote.frameRect
        return Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: max(1, rect.width * lay.scaled.width),
                   height: max(1, rect.height * lay.scaled.height))
            .position(x: lay.centre.x + (rect.midX - 0.5) * lay.scaled.width,
                      y: lay.centre.y + (rect.midY - 0.5) * lay.scaled.height)
            .animation(.interactiveSpring(duration: 0.18), value: remote.zoom)
    }

    /// The cursor we draw. It is the whole reason this screen is usable: the real
    /// pointer on a 1512-point display is invisible once the picture is 390 points wide,
    /// so aiming has to happen against something you can actually see.
    private func pointerCursor(in size: CGSize) -> some View {
        let lay = remote.layout(container: size)
        let at = CGPoint(x: lay.centre.x + (remote.pointer.x - 0.5) * lay.scaled.width,
                         y: lay.centre.y + (remote.pointer.y - 0.5) * lay.scaled.height)
        return Image(systemName: "cursorarrow")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.9), radius: 1.5)
            .shadow(color: .black.opacity(0.5), radius: 4)
            // The glyph's hotspot is its tip, not its centre.
            .offset(x: 6, y: 8)
            .position(at)
            .allowsHitTesting(false)
    }

    /// Eight seconds without a frame. Say which machine went quiet and offer the one
    /// thing that helps, rather than leaving a photograph of the past looking live.
    private var reconnectingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Reconnecting to \(remote.machine.host)…")
                .font(.headline)
                .foregroundStyle(.white)
            if let last = remote.lastFrameAt {
                Text("last frame \(last.formatted(date: .omitted, time: .standard))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text("Clicks are held back until the picture is live again.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button { remote.retry() } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(22)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(24)
    }

    private var showChromeHint: some View {
        VStack {
            Spacer()
            Label("Tap to show the controls", systemImage: "chevron.up")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.35)))
                .padding(.bottom, 10)
        }
        .allowsHitTesting(false)
    }

    private func notTrustedBanner(_ status: InputStatus) -> some View {
        // Quartz silently drops every event until the helper is trusted, so a UI that
        // stays quiet here looks broken rather than unpermitted.
        Label(status.hint ?? "Allow the mesh helper in System Settings › Privacy › Accessibility",
              systemImage: "hand.raised.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.12))
    }

    // MARK: Control bar

    private var controlBar: some View {
        HStack(spacing: 8) {
            Button { remote.click() } label: { Label("Click", systemImage: "cursorarrow.click") }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(remote.inputBlocked)
            Button { remote.click("right") } label: { Image(systemName: "cursorarrow.click.badge.clock") }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(remote.inputBlocked)
            Button {
                remote.setDragMode(remote.dragMode == .pan ? .pointer : .pan)
            } label: {
                Image(systemName: remote.dragMode == .pan ? "hand.draw" : "cursorarrow.motionlines")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .tint(remote.dragMode == .pan ? .orange : .accentColor)
            .accessibilityLabel(remote.dragMode == .pan ? "Drag pans the view" : "Drag moves the pointer")
            Divider().frame(height: 18)
            Button { remote.setZoom(remote.zoom - 1) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(remote.zoom <= 1)
            Text(String(format: "%.1f×", remote.zoom))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 34)
            Button { remote.setZoom(remote.zoom + 1) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(remote.zoom >= 6)
            Spacer()
            Button {
                chromeHidden = true
                remote.flash("Tap the screen to bring the controls back")
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .accessibilityLabel("Hide the controls")
            Button { keyboardUp.toggle(); typingFocused = keyboardUp } label: {
                Image(systemName: keyboardUp ? "keyboard.chevron.compact.down" : "keyboard")
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Keyboard

    private static let modifiers = [("⇧", "shift"), ("⌃", "ctrl"), ("⌥", "option"), ("⌘", "cmd")]
    private static let specials = [("esc", "escape"), ("tab", "tab"), ("↩", "return"), ("⌫", "delete"),
                                   ("↑", "up"), ("↓", "down"), ("←", "left"), ("→", "right")]

    private var keyboardPane: some View {
        VStack(spacing: 8) {
            // Sticky modifiers, cleared by the next real key — so ⌘⇧4 is two taps and a
            // key, not a chord nobody can perform on a touchscreen.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.modifiers, id: \.1) { label, key in
                        Button(label) { remote.toggleMod(key) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(remote.mods.contains(key) ? .orange : .secondary)
                            .fontWeight(remote.mods.contains(key) ? .bold : .regular)
                    }
                    Divider().frame(height: 18)
                    ForEach(Self.specials, id: \.1) { label, key in
                        Button(label) { remote.pressKey(key) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 8) {
                TextField("Type on \(remote.machine.host)", text: $typing)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($typingFocused)
                    .onSubmit(sendTyping)
                Button("Send", action: sendTyping)
                    .buttonStyle(.borderedProminent)
                    .disabled(typing.isEmpty)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .disabled(remote.inputBlocked)
    }

    private func sendTyping() {
        remote.type(typing)
        typing = ""
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { remote.recenterPointer() } label: {
                    Label("Recenter pointer", systemImage: "scope")
                }
                Button { remote.resetZoom() } label: {
                    Label("Fit to screen", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .disabled(remote.zoom == 1)
                Button {
                    chromeHidden = true
                    remote.flash("Tap the screen to bring the controls back")
                } label: {
                    Label("Hide controls", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Divider()
                Button { remote.pasteFromPhone() } label: {
                    Label("Paste from iPhone", systemImage: "doc.on.clipboard")
                }
                if let session = remote.session {
                    Button { remote.pasteIntoSession() } label: {
                        Label("Paste into \(session)", systemImage: "text.insert")
                    }
                }
                Button { remote.copyFromMachine() } label: {
                    Label("Copy from \(remote.machine.host)", systemImage: "doc.on.doc")
                }
                if remote.displays.count > 1 {
                    Divider()
                    Picker("Display", selection: $remote.activeDisplay) {
                        ForEach(remote.displays) { d in
                            Text(d.label + (d.main == true ? " (main)" : "")).tag(d.index)
                        }
                    }
                }
                Divider()
                Menu {
                    ForEach(["left", "right", "top", "bottom", "center", "full"], id: \.self) { place in
                        Button(place.capitalized) {
                            remote.send([.window(place, display: remote.displays.count > 1 ? remote.activeDisplay : nil)])
                        }
                    }
                } label: {
                    Label("Move window", systemImage: "macwindow.on.rectangle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let note = remote.note {
            Text(note)
                .font(.footnote)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(.top, 8)
                .transition(.opacity)
        }
    }
}

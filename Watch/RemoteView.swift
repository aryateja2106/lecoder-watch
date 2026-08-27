import SwiftUI
import Combine
import WatchKit
import UIKit
import CoreMotion

// Drive the Mac from the wrist: screen preview + trackpad + crown scroll + keys.
// The watch never injects anything itself — it POSTs high-level events to meshd,
// which replays them as real HID events (see install/payload/bin/mesh-input.swift).

// MARK: - Transport

/// Owns the send path for one machine. Coalesces the drag/crown stream into one
/// request every ~40ms instead of one per gesture callback, which is what makes a
/// trackpad over the tailnet feel like a trackpad rather than a telegraph.
@MainActor
final class RemoteControl: ObservableObject {
    private(set) var machine: Machine

    @Published var status: InputStatus?
    @Published var screen: Data?
    /// Which part of the display `screen` actually covers, straight from the daemon's
    /// own header — never guessed. Nil = the whole display, which is what every
    /// pre-0.5.0 daemon serves and what the client still has to zoom for itself.
    @Published var screenRect: CGRect?
    @Published var note: String?
    @Published var dragLocked = false
    @Published var displays: [DisplayInfo] = []
    /// Which screen the preview shows and taps/window snaps target. 1-based.
    @Published var activeDisplay = 1
    /// Crown scrolls sideways instead of up/down — wide timelines, spreadsheets, code.
    @Published var horizontalScroll = false
    /// Point with your arm instead of stroking a 40mm pad.
    @Published private(set) var airMouse = false
    @Published var sticky: Set<String> = []      // modifiers held for the next key

    /// Relay through the phone when the watch can't reach meshd itself — the normal
    /// case on a real watch, which has no Tailscale. Slower, so the flush loop backs
    /// off; WCSession is not built for a 25Hz stream.
    @Published private(set) var viaRelay = false
    /// What this machine's daemon advertised. Fed in by the view from the store's
    /// snapshot, because a `MeshClient` built without it silently refuses every
    /// meshd 0.5.0 addition — region capture and the honest /system result included.
    @Published var capabilities: [String]? = nil
    /// The part of the display currently on screen, for region capture. Nil = whole
    /// frame, which is also what an old daemon always gets.
    @Published var visibleRegion: CGRect? = nil
    private var pendingDX = 0.0
    private var pendingDY = 0.0
    private var pendingScroll = 0.0
    private var pendingScrollX = 0.0
    private var discrete: [InputEvent] = []
    private var inFlight = false
    private let motion = CMMotionManager()

    init(machine: Machine) { self.machine = machine }

    /// Arm as cursor. The wrist's yaw drives x and its pitch drives y; the mapping and
    /// its calibration live in `airMouseDelta`. Deltas join the same coalescing queue
    /// as pad drags, so they ship at the normal flush rate rather than 50 times a second.
    func setAirMouse(_ on: Bool) {
        guard on else {
            motion.stopDeviceMotionUpdates()
            airMouse = false
            return
        }
        guard motion.isDeviceMotionAvailable else {
            note = "no motion sensor"
            return
        }
        airMouse = true
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
            guard let self, let sample else { return }
            guard let delta = airMouseDelta(pitchRate: sample.rotationRate.x,
                                            yawRate: sample.rotationRate.z) else { return }
            self.move(dx: delta.dx, dy: delta.dy)
        }
    }

    func stopMotion() { motion.stopDeviceMotionUpdates() }

    /// Credentials can land after the view opens (the phone relays them on its next
    /// poll). Re-probe on the new config so a relayed session upgrades to direct
    /// instead of staying slow until the user backs out and comes in again.
    func update(machine: Machine) {
        guard machine != self.machine else { return }
        self.machine = machine
        Task { await refreshStatus() }
    }

    private var client: MeshClient {
        var client = MeshClient(machine: machine)
        client.capabilities = capabilities
        return client
    }

    func supports(_ capability: String) -> Bool { capabilities?.contains(capability) ?? false }

    // MARK: queueing

    /// Where we believe the Mac's cursor is, 0…1 of the active display, so the preview
    /// can draw it. A tap sets it exactly; a trackpad drag advances it by the same pixel
    /// delta meshd is about to apply, which stays true unless something else moves the
    /// mouse — and the next tap re-syncs it regardless.
    @Published var pointer = CGPoint(x: 0.5, y: 0.5)
    /// Preview magnification. A 44mm watch showing a 15" display is the most extreme
    /// version of the aiming problem in the whole product.
    @Published var previewZoom: CGFloat = 1
    private var fetchingScreen = false

    private var activeDisplayInfo: DisplayInfo? { displays.first { $0.index == activeDisplay } }

    func move(dx: Double, dy: Double) {
        pendingDX += dx; pendingDY += dy
        guard let d = activeDisplayInfo, d.width > 0, d.height > 0 else { return }
        pointer = CGPoint(x: min(max(pointer.x + dx / Double(d.width), 0), 1),
                          y: min(max(pointer.y + dy / Double(d.height), 0), 1))
    }

    /// Zoom, then go and get a frame that actually holds the extra detail — otherwise
    /// zooming in only magnifies the blur it was meant to resolve.
    func zoomPreview(_ delta: CGFloat) {
        let next = clampedZoom(previewZoom + delta)
        guard next != previewZoom else { return }
        previewZoom = next
        Task { await refreshScreen() }
    }
    func scroll(_ amount: Double) {
        if horizontalScroll { pendingScrollX += amount } else { pendingScroll += amount }
    }

    func perform(_ events: [InputEvent]) {
        discrete.append(contentsOf: events)
        // Confirm at the wrist, not on the Mac: the screen preview is two seconds
        // behind, so without a tap you cannot tell a click from a missed touch.
        WKInterfaceDevice.current().play(events.contains { $0.t == "click" } ? .click : .success)
        Task { await flush() }
    }

    func tap(at point: CGPoint, in size: CGSize, imageAspect: Double?) {
        let aspect = imageAspect ?? (size.height > 0 ? Double(size.width / size.height) : 0)
        // Through the zoom, not around it: at 3x the picture under your finger is not
        // the picture the old mapping assumed, and the cursor would land elsewhere.
        guard let p = normalizedPoint(fromTap: point, pointer: pointer, imageAspect: aspect,
                                      container: size, zoom: previewZoom) else { return }
        pointer = p
        perform([.moveTo(x: p.x, y: p.y, display: activeDisplay), .click()])
    }

    /// Snap on whichever screen the preview is showing.
    func snap(_ place: String) { perform([.window(place, display: activeDisplay)]) }

    func loadDisplays() async {
        if !viaRelay, let list = try? await client.displays(), list.ok {
            displays = list.displays
        } else {
            let reply = await WatchLink.shared.request(
                WatchCommand(kind: .listDisplays, host: machine.host, agent: nil, text: nil, key: nil))
            displays = reply.flatMap { try? JSONDecoder().decode(DisplayList.self, from: $0) }?.displays ?? []
        }
        if !displays.contains(where: { $0.index == activeDisplay }) {
            activeDisplay = displays.first(where: { $0.main == true })?.index ?? displays.first?.index ?? 1
        }
    }

    func key(_ name: String, _ extraMods: [String] = []) {
        let mods = Array(sticky) + extraMods
        sticky.removeAll()
        perform([.key(name, mods)])
    }

    func toggleDragLock() {
        dragLocked.toggle()
        perform([dragLocked ? .hold : .release])
        WKInterfaceDevice.current().play(dragLocked ? .start : .stop)
    }

    /// Everything this screen left running on the Mac, undone. Called when the view
    /// goes away, which is the only moment the wrist stops being able to undo it.
    ///
    /// Drag lock is the dangerous half. `.hold` presses the physical mouse button and
    /// nothing but `.release` lifts it, and `.release` was emitted from exactly one
    /// place — `toggleDragLock`. So walking back out of this screen with drag lock on
    /// left the button held down on the Mac: every later pointer movement, from the
    /// watch or from the Mac's own trackpad, became a drag that selected and dropped
    /// whatever it crossed. There was no screen anywhere offering the button that
    /// would have fixed it.
    ///
    /// Air mouse is the quiet half. `stopMotion()` ends the sensor updates but left
    /// `airMouse` true, so coming back showed an armed mode whose arm moved nothing.
    func relinquish() {
        if dragLocked {
            dragLocked = false
            // Sent directly, never queued. Queueing it was the bug: `perform` hands the
            // event to `flush()`, and `flush()` returns immediately while a request is
            // already in flight — which during a drag is the ordinary state, not a rare
            // one, since a single `client.input` walks every address in turn and the
            // flush interval is 40ms. The `.release` was left sitting in `discrete`, and
            // the only thing that ever drains `discrete` is the view's `.task` loop,
            // which SwiftUI cancels on the very disappear that called this. So nothing
            // drained it, ever: the Mac's button stayed physically down, every later
            // pointer move became a drag, and the one screen with a release button was
            // gone. Retaining the actor was never the binding constraint — the
            // `inFlight` guard was, and it turned that flush into a no-op.
            //
            // Detached so it outlives the view too, and both transports are tried in
            // turn: this is the one event that must not be dropped, so unlike a cursor
            // delta it is queued for the phone if the phone is unreachable right now.
            let client = self.client
            let host = machine.host
            let direct = !viaRelay
            Task.detached {
                if direct, (try? await client.input([.release])) != nil { return }
                WatchLink.shared.send(WatchCommand(kind: .input, host: host, agent: nil,
                                                   text: nil, key: nil, input: [.release]),
                                      queueIfUnreachable: true)
            }
        }
        setAirMouse(false)
    }

    // MARK: loop

    /// Drain accumulated motion + queued actions. Called on a timer by the view.
    func flush() async {
        guard !inFlight else { return }
        var batch = discrete
        discrete = []
        if abs(pendingDX) >= 0.5 || abs(pendingDY) >= 0.5 {
            batch.insert(.move(dx: pendingDX, dy: pendingDY), at: 0)
            pendingDX = 0; pendingDY = 0
        }
        if abs(pendingScroll) >= 1 || abs(pendingScrollX) >= 1 {
            batch.append(.scroll(dx: pendingScrollX, dy: pendingScroll))
            pendingScroll = 0
            pendingScrollX = 0
        }
        guard !batch.isEmpty else { return }

        inFlight = true
        defer { inFlight = false }
        if viaRelay {
            relay(batch)
            return
        }
        do {
            try await client.input(batch)
            note = nil
        } catch {
            // First failure flips us to the phone relay; nothing is retried — a dropped
            // cursor delta is better than a late one. `viaRelay` says so by itself: this
            // used to also write note = "via phone", and because flush() returns early
            // on an empty batch it never reached the `note = nil` above — so the one
            // mode indicator on the screen was permanently occupied and air mouse and
            // drag lock could both be ON with nothing to show it.
            viaRelay = true
            relay(batch)
        }
    }

    private func relay(_ batch: [InputEvent]) {
        WatchLink.shared.send(WatchCommand(kind: .input, host: machine.host, agent: nil,
                                           text: nil, key: nil, input: batch),
                              queueIfUnreachable: false)
    }

    var flushInterval: Duration { viaRelay ? .milliseconds(150) : .milliseconds(40) }

    // MARK: status + screen

    func refreshStatus(prompt: Bool = false) async {
        do {
            status = try await client.inputStatus(prompt: prompt)
            viaRelay = false
            note = nil
        } catch {
            // Probe doubles as the route check: one 3s timeout here beats the first
            // drag stalling while URLSession works through every address.
            viaRelay = true
            // The phone can still answer for us — including raising the Accessibility
            // prompt on the Mac, which is the one thing the user must be told about.
            let reply = await WatchLink.shared.request(
                WatchCommand(kind: .inputStatus, host: machine.host, agent: nil,
                             text: prompt ? "prompt" : nil, key: nil))
            status = reply.flatMap { try? JSONDecoder().decode(InputStatus.self, from: $0) }
        }
    }

    /// How wide a capture to ask for, in pixels of the longest edge.
    ///
    /// meshd defaults to 480, which is fine at fit-to-screen — the watch draws the picture
    /// about 184 points wide — and hopeless the moment you zoom, because zooming magnifies
    /// the frame already received instead of fetching a sharper one. At 6x you are looking
    /// at a sixth of a 480px image stretched across the whole screen: about 80 source
    /// pixels. That is why the Mac was unreadable however far you zoomed in.
    ///
    /// Scaling the request with the zoom keeps source pixels per screen point roughly
    /// constant, so zooming in now reveals detail, while a fit-to-screen view stays cheap.
    /// That matters: this frame is often relayed through the phone, and 2000px is ~500KB
    /// against 480px at ~45KB, so paying for detail only when it can be seen is the point.
    private var requestedWidth: Int { Int((480 * previewZoom).rounded()) }

    /// Why the last frame did not arrive. Shown rather than swallowed: a preview that
    /// stays grey looks identical whether the Mac is asleep, the token was rotated, or
    /// Screen Recording was never granted — three different problems, one blank box.
    @Published var screenError: String?

    func refreshScreen() async {
        // Single flight. Crown zooming fires this repeatedly, and an earlier, softer frame
        // landing after a later, sharper one would undo the zoom the user just asked for.
        guard !fetchingScreen else { return }
        fetchingScreen = true
        defer { fetchingScreen = false }
        do {
            // `rect` is dropped by MeshClient unless the daemon advertises
            // "screenRegion", so an old daemon still gets exactly today's request.
            // The rect that comes BACK is what the daemon says it served, and the only
            // thing allowed to decide whether the view zooms this frame again.
            let frame = try await client.screenFrame(display: displays.count > 1 ? activeDisplay : nil,
                                                     width: requestedWidth,
                                                     rect: supports("screenRegion") ? visibleRegion : nil)
            screen = frame.data
            screenRect = frame.rect
            screenError = nil
        } catch MeshClient.MeshError.http(let code) where code == 401 || code == 403 {
            screenError = "token rejected — re-pair this machine on your iPhone"
        } catch MeshClient.MeshError.http(let code) {
            screenError = "the Mac answered \(code) — check Screen Recording in System Settings"
        } catch {
            screenError = "no answer from \(machine.host)"
        }
    }

    func volume(delta: Int? = nil, muted: Bool? = nil) {
        guard !viaRelay else {
            WatchLink.shared.send(WatchCommand(kind: .volume, host: machine.host, agent: nil,
                                               text: nil, key: nil,
                                               volumeDelta: delta, volumeMuted: muted))
            note = muted == true ? "muted" : "volume sent"
            return
        }
        Task {
            if let state = try? await client.volume(delta: delta, muted: muted) {
                note = state.muted == true ? "muted" : state.level.map { "volume \($0)%" }
            }
        }
    }

    func media(_ key: String) { perform([.media(key)]) }

    func apps() async -> AppList? {
        if !viaRelay, let list = try? await client.apps() { return list }
        let reply = await WatchLink.shared.request(
            WatchCommand(kind: .listApps, host: machine.host, agent: nil, text: nil, key: nil),
            timeout: 8)
        return reply.flatMap { try? JSONDecoder().decode(AppList.self, from: $0) }
    }

    func activate(_ app: String) {
        note = app
        guard !viaRelay else {
            WatchLink.shared.send(WatchCommand(kind: .activateApp, host: machine.host, agent: nil,
                                               text: app, key: nil))
            return
        }
        Task { try? await client.activateApp(app) }
    }

    /// Lock / sleep the display / screensaver / sleep the Mac.
    ///
    /// meshd 0.5.0 runs every action through a checked spawn and answers with the real
    /// exit code and stderr; older daemons said `{ok:true}` whatever happened. So the
    /// success line is no longer written before the request — "Lock screen" used to
    /// print "lock" on the pad while the Mac sat there untouched, and there is no
    /// second screen from which to notice. `SystemResult` decodes both shapes, and
    /// `failureLine` is nil exactly when it worked.
    func system(_ action: String) {
        guard !viaRelay else {
            // The relay reports delivery to the PHONE, not what the Mac did with it —
            // the iOS handler discards /system's body. Say the weaker, true thing.
            WatchLink.shared.send(WatchCommand(kind: .system, host: machine.host, agent: nil,
                                               text: action, key: nil))
            note = "\(action) sent via iPhone"
            return
        }
        Task {
            do {
                let result = try await client.systemAction(action)
                note = result.failureLine.map { "\(action) failed — \($0)" } ?? action
                WKInterfaceDevice.current().play(result.succeeded ? .success : .failure)
            } catch MeshClient.MeshError.unsupported {
                note = "\(action) needs meshd 0.5.0"
                WKInterfaceDevice.current().play(.failure)
            } catch {
                note = "\(action) — no answer from the Mac"
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    func pullClipboard() async -> String? {
        if !viaRelay { return try? await client.clipboard() }
        let reply = await WatchLink.shared.request(
            WatchCommand(kind: .readClipboard, host: machine.host, agent: nil, text: nil, key: nil))
        return reply.flatMap { try? JSONDecoder().decode(String.self, from: $0) }
    }

    func pushClipboard(_ text: String) {
        guard !viaRelay else {
            WatchLink.shared.send(WatchCommand(kind: .clipboard, host: machine.host, agent: nil,
                                               text: text, key: nil))
            note = "copied to Mac"
            return
        }
        Task {
            try? await client.setClipboard(text)
            note = "copied to Mac"
        }
    }
}

// MARK: - Trackpad screen

struct RemoteView: View {
    @EnvironmentObject var store: WatchMeshStore
    @StateObject private var remote: RemoteControl
    @State private var lastTranslation: CGSize = .zero
    @State private var crown: Double = 0
    @State private var moved = false
    @State private var typing = false
    /// Full-pad mode: the preview gives way to a full-height trackpad where a second
    /// tap inside the window right-clicks — built for one-handed approvals (fork in
    /// the right hand, watch on the left wrist).
    @State private var padOnly = false
    @State private var lastTapAt: Date?
    /// Inspect mode: the picture and nothing else. Every other layout on this screen
    /// spends most of its height on the trackpad, which leaves the Mac's screen about
    /// 56 points tall — enough to confirm a click landed, nowhere near enough to READ.
    @State private var inspecting = false
    /// Where the inspect view is looking, as a fraction of the whole image from its
    /// centre. Clamped by `clampedPan`, so it can never scroll off the picture.
    @State private var inspectPan: CGPoint = .zero
    @State private var inspectCrown: Double = 0
    /// The gesture hint, shown for a few seconds on entry and then out of the way —
    /// "chrome hidden" cannot mean "controls unlearnable". Bumping `hintToken` brings
    /// it back, which every side tap does: someone tapping the edges repeatedly is
    /// someone who has not found the way out yet, and hiding the toolbar took the
    /// back button with it.
    @State private var showInspectHint = true
    @State private var hintToken = 0
    /// When this screen started asking for a frame, for the "still trying" line.
    @State private var screenAskedAt = Date()
    @State private var screenSlow = false

    init(machine: Machine) {
        _remote = StateObject(wrappedValue: RemoteControl(machine: machine))
    }

    var body: some View {
        Group {
            if inspecting {
                inspector
            } else {
                VStack(spacing: 4) {
                    if !padOnly {
                        if remote.displays.count > 1 { displayPicker }
                        preview
                    }
                    trackpad
                    controls
                }
                .padding(.horizontal, 2)
            }
        }
        .navigationTitle("Control")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(inspecting ? .hidden : .automatic)
        .sheet(isPresented: $typing) { TypeSheet(remote: remote, presented: $typing) }
        .task {
            await remote.refreshStatus()
            await remote.loadDisplays()
            while !Task.isCancelled {
                await remote.flush()
                try? await Task.sleep(for: remote.flushInterval)
            }
        }
        .task {
            // Slow second loop: the preview is for "did that land?", not a video feed.
            while !Task.isCancelled {
                if remote.viaRelay {
                    // No rect on the relay: the phone hands over bytes and drops the
                    // headers, so nothing here can tell a crop from a whole display.
                    // Asking for one anyway is how Inspect ended up magnifying a frame
                    // that was already magnified. Soft and in the right place beats
                    // sharp and somewhere else.
                    store.requestScreen(host: remote.machine.host,
                                        display: remote.displays.count > 1 ? remote.activeDisplay : nil)
                } else {
                    await remote.refreshScreen()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task {
            // A relayed session is a fallback, not a verdict — retry the direct path so
            // a watch that comes back onto the network stops paying 150ms a batch.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if remote.viaRelay { await remote.refreshStatus() }
            }
        }
        .task(id: screenAskedAt) {
            screenSlow = false
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            if screenShot == nil { screenSlow = true }
        }
        // Every 0.5.0 feature on this screen is off unless the daemon says otherwise,
        // and the daemon says so through the store's snapshot — not through anything
        // RemoteControl can see for itself.
        .onAppear { remote.capabilities = store.capabilities(for: remote.machine.host) }
        .onChange(of: store.snaps) { _, _ in
            remote.capabilities = store.capabilities(for: remote.machine.host)
        }
        .onChange(of: store.machines) { _, updated in
            if let match = updated.first(where: { $0.host == remote.machine.host }) {
                remote.update(machine: match)
            }
        }
        .onDisappear { store.stopScreen(); remote.relinquish() }
    }

    // MARK: Inspect

    /// The Mac's screen, full-bleed, with the chrome gone.
    ///
    /// Crown pans up and down (it is the only precise continuous input a watch has);
    /// the left and right thirds pan sideways one viewport at a time, because a drag
    /// here would fight the trackpad muscle memory from the mode next door. The middle
    /// third leaves — the one control worth reserving the biggest target for.
    private var inspector: some View {
        GeometryReader { geo in
            // Two different shapes, and confusing them is half of the "zoom does not
            // help" bug: `aspect` is the shape of the picture in hand — the CROP, once
            // the daemon starts cutting them — and only lays out the image. Every
            // decision about which region to ask for next belongs to the display.
            let aspect = screenAspect ?? 1.6
            let displayAspect = regionAspect
            let containerAspect = geo.size.height > 0 ? Double(geo.size.width / geo.size.height) : 1.6
            // A served crop already IS the viewport, so it is drawn at 1x and unmoved;
            // a whole-display frame still gets today's client-side zoom and pan.
            let draw = frameTransform(servedRect: servedRect, zoom: remote.previewZoom, pan: inspectPan)
            ZStack {
                Color.black
                if let shot = screenShot {
                    Image(uiImage: shot)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(draw.zoom)
                        .offset(panOffset(pan: draw.pan, zoom: draw.zoom,
                                          in: geo.size, imageAspect: aspect))
                } else if let error = remote.screenError {
                    // Only reachable over an empty frame. When the phone is relaying,
                    // `screenError` can be a leftover from the direct path we already
                    // gave up on, and pasting that across a picture that IS arriving
                    // would be a lie — so it lives in the else branch, not on top.
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                } else {
                    Text(screenSlow ? "No screen yet — still trying" : "Fetching screen…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if showInspectHint {
                    Text("Crown ↕ · sides ↔ · tap middle to exit")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: Capsule())
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                inspectZoomChips(containerAspect: containerAspect, imageAspect: displayAspect)
            }
            .onTapGesture { point in
                let third = geo.size.width / 3
                if point.x < third {
                    pan(-1, containerAspect: containerAspect, imageAspect: displayAspect)
                } else if point.x > geo.size.width - third {
                    pan(1, containerAspect: containerAspect, imageAspect: displayAspect)
                } else {
                    inspecting = false
                }
            }
            .focusable(true)
            .digitalCrownRotation($inspectCrown, from: -100, through: 100, by: 0.5,
                                  sensitivity: .medium, isContinuous: false,
                                  isHapticFeedbackEnabled: true)
            .onChange(of: inspectCrown) { old, new in
                // 40 crown units to cross one screen height: fine enough to read a
                // paragraph, coarse enough to reach the bottom of a long page.
                inspectPan = clampedPan(CGPoint(x: inspectPan.x, y: inspectPan.y + (new - old) / 40),
                                        zoom: remote.previewZoom,
                                        containerAspect: containerAspect, imageAspect: displayAspect)
                syncRegion(zoom: remote.previewZoom,
                           containerAspect: containerAspect, imageAspect: displayAspect)
                fetchRegionNow()
            }
            .onAppear {
                syncRegion(zoom: remote.previewZoom,
                           containerAspect: containerAspect, imageAspect: displayAspect)
            }
            .task(id: hintToken) {
                showInspectHint = true
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation { showInspectHint = false }
            }
        }
        .ignoresSafeArea()
        .onDisappear {
            remote.visibleRegion = nil
            // The frame in hand is a crop of wherever Inspect was looking. Left in
            // place it would be drawn in the preview as if it were the whole display,
            // putting the cursor overlay on the wrong pixels until a full frame lands.
            remote.screen = nil
            remote.screenRect = nil
            Task { await remote.refreshScreen() }
        }
    }

    /// − and + without the crown (it pans) and without a pinch (a 44mm screen has no
    /// room for two fingers). Changing magnification used to mean leaving Inspect,
    /// hitting a 9pt chip and coming back — which resets the pan to the centre, so you
    /// lost your place every time you changed zoom.
    private func inspectZoomChips(containerAspect: Double, imageAspect: Double) -> some View {
        HStack(spacing: 6) {
            Button { inspectZoom(-1, containerAspect: containerAspect, imageAspect: imageAspect) } label: {
                Image(systemName: "minus")
            }
            .disabled(remote.previewZoom <= 1)
            .accessibilityLabel("Zoom out")
            Text("\(Int(remote.previewZoom.rounded()))x")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
            Button { inspectZoom(1, containerAspect: containerAspect, imageAspect: imageAspect) } label: {
                Image(systemName: "plus")
            }
            .disabled(remote.previewZoom >= 6)
            .accessibilityLabel("Zoom in")
        }
        .font(.system(size: 11, weight: .bold))
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(.top, 2)
    }

    private func inspectZoom(_ delta: CGFloat, containerAspect: Double, imageAspect: Double) {
        let next = clampedZoom(remote.previewZoom + delta)
        guard next != remote.previewZoom else { return }
        // Re-clamp and publish the new region BEFORE zoomPreview goes and fetches, or
        // the sharper frame that comes back is a crop of where we were looking one
        // zoom level ago and the picture jumps sideways as it lands.
        inspectPan = clampedPan(inspectPan, zoom: next,
                                containerAspect: containerAspect, imageAspect: imageAspect)
        syncRegion(zoom: next, containerAspect: containerAspect, imageAspect: imageAspect)
        remote.zoomPreview(delta)
        hintToken += 1
    }

    private func pan(_ direction: Double, containerAspect: Double, imageAspect: Double) {
        let step = panStep(zoom: remote.previewZoom, pan: inspectPan,
                           containerAspect: containerAspect, imageAspect: imageAspect)
        let next = clampedPan(CGPoint(x: inspectPan.x + direction * step, y: inspectPan.y),
                              zoom: remote.previewZoom,
                              containerAspect: containerAspect, imageAspect: imageAspect)
        // Already hard against the edge: say so with the failure tick rather than the
        // click that means "moved", and put the hint back — a tap that does nothing is
        // usually a tap aimed at the wrong thing.
        let moved = next != inspectPan
        inspectPan = next
        syncRegion(zoom: remote.previewZoom, containerAspect: containerAspect, imageAspect: imageAspect)
        if moved { fetchRegionNow() }
        WKInterfaceDevice.current().play(moved ? .click : .failure)
        hintToken += 1
    }

    /// Go and get the region we just moved to, instead of waiting out the 2s preview
    /// poll. Once the daemon is cropping, the picture cannot move until the next frame
    /// lands — so without this a side tap or a crown turn buzzes and then shows the
    /// same view for up to two seconds, which reads as "panning does not work". It is
    /// safe to call as fast as the crown fires: `refreshScreen` is single flight, so
    /// the ticks in between cost nothing and the frame rate settles at one per round
    /// trip. Relayed sessions do not need it — they get no crop, so they still pan
    /// client-side and instantly.
    private func fetchRegionNow() {
        guard !remote.viaRelay else { return }
        Task { await remote.refreshScreen() }
    }

    /// Tell the daemon what we are looking at, so the next frame is that region at
    /// native pixels instead of the whole display downsampled and then stretched.
    private func syncRegion(zoom: CGFloat, containerAspect: Double, imageAspect: Double) {
        remote.visibleRegion = visibleRect(zoom: zoom, pan: inspectPan,
                                           containerAspect: containerAspect, imageAspect: imageAspect)
    }

    private func panOffset(pan: CGPoint, zoom: CGFloat, in container: CGSize, imageAspect: Double) -> CGSize {
        let fit = fittedSize(imageAspect: imageAspect, container: container)
        let scaled = CGSize(width: fit.width * zoom, height: fit.height * zoom)
        return CGSize(width: -pan.x * scaled.width, height: -pan.y * scaled.height)
    }

    /// Direct grab when we have one, else whatever the phone last relayed.
    private var screenData: Data? {
        remote.screen ?? (store.screenHost == remote.machine.host ? store.screenJPEGData : nil)
    }

    private var screenShot: UIImage? { screenData.flatMap(UIImage.init(data:)) }

    /// The region the frame being drawn covers — only ever the daemon's own answer for
    /// the frame we fetched ourselves. A relayed frame arrives as bare bytes, so it is
    /// treated as a whole display: old behaviour, never a confident wrong one.
    private var servedRect: CGRect? { remote.screen == nil ? nil : remote.screenRect }

    /// The DISPLAY's shape, which is what decides which region to ask for next.
    ///
    /// `screenAspect` measures the picture in hand, and once the daemon starts cropping
    /// that picture is the crop — feeding its shape back into `visibleRect` computes the
    /// next region from the wrong rectangle, so the view creeps sideways as you scroll
    /// and the pan clamp stops at the wrong place. /displays is authoritative; the image
    /// is the fallback, and only while it is still the whole screen.
    private var regionAspect: Double {
        remote.displays.first { $0.index == remote.activeDisplay }?.aspect
            ?? (servedRect == nil ? screenAspect : nil)
            ?? 1.6
    }

    /// One chip per screen. Switching repoints the preview, taps and window snaps
    /// together, so "the screen I'm looking at" is always the one I'm driving.
    private var displayPicker: some View {
        HStack(spacing: 3) {
            ForEach(remote.displays) { display in
                Button {
                    remote.activeDisplay = display.index
                    remote.screen = nil
                    Task { await remote.refreshScreen() }
                } label: {
                    Text("\(display.index)")
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(remote.activeDisplay == display.index ? .blue : nil)
                .accessibilityLabel(display.label)
            }
        }
        .frame(height: 20)
    }

    // Tap the preview to put the cursor exactly there — far more usable on a 40mm
    // screen than nudging a relative pointer across a 15" display.
    private var preview: some View {
        GeometryReader { geo in
            let aspect = screenAspect ?? 1.6
            ZStack {
                if let shot = screenShot {
                    Image(uiImage: shot)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(remote.previewZoom)
                        .offset(zoomedOffset(pointer: remote.pointer, imageAspect: aspect,
                                             container: geo.size, zoom: remote.previewZoom))
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.2))
                        .overlay(
                            // A grey box is the same picture whether the Mac is asleep,
                            // the token was rotated or Screen Recording was never
                            // granted. Say which, once we know; say "still trying"
                            // before that; and never keep an ellipsis running forever.
                            Text(remote.screenError ?? (screenSlow ? "No screen yet — still trying" : "screen…"))
                                .font(.system(size: 9))
                                .foregroundStyle(remote.screenError == nil ? Color.secondary : Color.orange)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal, 4)
                        )
                }
                // Where the cursor is. On a 44mm watch the Mac's own pointer is well
                // under a pixel, so without this you are aiming at nothing.
                if screenShot != nil {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.9), radius: 1)
                        .offset(x: 3, y: 4)          // the glyph's hotspot is its tip
                        .position(pointerScreenPosition(pointer: remote.pointer, imageAspect: aspect,
                                                        container: geo.size, zoom: remote.previewZoom))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { point in
                remote.tap(at: point, in: geo.size, imageAspect: screenAspect)
            }
            // The way in that people actually find. The chip below is 9pt and third in
            // a row of three, so it read as another zoom button and the screen looked
            // like it could only be zoomed, never moved. A long press is safe here in a
            // way it is not on the trackpad: this view has no minimumDistance-0 drag to
            // fight, only the tap, and a tap still places the cursor.
            .onLongPressGesture(minimumDuration: 0.4) { enterInspect() }
        }
        .frame(height: remote.previewZoom > 1 ? 96 : 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) { zoomChips }
    }

    /// Two chips rather than a pinch: a 44mm screen has no room for two fingers, and
    /// the crown is already spoken for by scroll. Plus the way into inspect mode, which
    /// is where the picture is finally big enough to read rather than merely confirm.
    private var zoomChips: some View {
        HStack(spacing: 2) {
            Button { remote.zoomPreview(-1) } label: { Image(systemName: "minus") }
                .disabled(remote.previewZoom <= 1)
                .accessibilityLabel("Zoom out")
            Button { remote.zoomPreview(1) } label: { Image(systemName: "plus") }
                .disabled(remote.previewZoom >= 6)
                .accessibilityLabel("Zoom in")
            // Words, not a third glyph: as an unlabeled 9pt symbol beside − and + this
            // read as one more zoom step, so the whole read-and-pan mode behind it went
            // undiscovered and the Mac's screen looked like it could only be magnified
            // in place.
            Button { enterInspect() } label: { Text("Read") }
                .accessibilityLabel("Read the screen full size")
        }
        .font(.system(size: 9, weight: .bold))
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .padding(2)
    }

    /// Open Inspect from the chip or from a long press on the picture itself.
    private func enterInspect() {
        inspectPan = .zero
        hintToken += 1
        // Entering at 1x would show the whole display fitted — and then the side zones
        // would pan across nothing, because there is nothing off-screen to pan to.
        // Inspect exists to get closer than that, so it starts closer, and the gesture
        // hint stops being a lie.
        if remote.previewZoom < 2 { remote.zoomPreview(2 - remote.previewZoom) }
        inspecting = true
        WKInterfaceDevice.current().play(.start)
    }

    /// Measured from the screenshot itself, so it is right even before /displays answers.
    private var screenAspect: Double? {
        guard let shot = screenShot, shot.size.height > 0 else {
            return remote.displays.first { $0.index == remote.activeDisplay }?.aspect
        }
        return Double(shot.size.width / shot.size.height)
    }

    private var trackpad: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(remote.dragLocked ? Color.orange.opacity(0.28) : Color.gray.opacity(0.22))
            // Modes first, messages second. A mode is a state of the Mac you are still
            // in when you look away — drag lock is literally holding the mouse button
            // down over there — so it outranks anything transient. The old order put a
            // note on top, and one of those notes ("via phone") was never cleared, so
            // air mouse and drag lock could both be on with nothing to say so.
            .overlay(alignment: .center) {
                if remote.dragLocked {
                    Text("drag held — tap the lock to release").font(.caption2).foregroundStyle(.orange)
                } else if remote.airMouse {
                    Text("air mouse — point your arm").font(.caption2).foregroundStyle(.blue)
                } else if remote.status?.trusted == false {
                    Text("Needs Accessibility").font(.caption2).foregroundStyle(.orange)
                } else if let note = remote.note {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                } else if remote.viaRelay {
                    Text("via iPhone").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("tap · tap-tap right-clicks").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .topTrailing) { padModeChip }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                // Tap detection lives inside the drag: a separate .onTapGesture never
                // fires reliably next to a minimumDistance-0 drag.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.translation.width - lastTranslation.width
                        let dy = value.translation.height - lastTranslation.height
                        lastTranslation = value.translation
                        if abs(dx) > 0 || abs(dy) > 0 { moved = true }
                        let gain = pointerGain(step: hypot(dx, dy))
                        remote.move(dx: dx * gain, dy: dy * gain)
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        if !moved || distance < 5 {
                            // A second tap inside the window right-clicks. This was
                            // gated on full-pad mode while `lastTapAt` was kept in both,
                            // so in the mode people actually start in a double tap sent
                            // a second LEFT click and right click was unreachable.
                            // The first tap's left click already went out — deferring
                            // every tap by the window would tax the quick approvals this
                            // mode exists for, and click-then-right-click is how people
                            // use a real mouse anyway (focus it, then open the menu).
                            // ponytail: eager double-tap; a deferred-click toggle only if
                            // right-clicking links at the wrist ever matters.
                            if isDoubleTap(previous: lastTapAt, now: Date()) {
                                remote.perform([.click("right")])
                                lastTapAt = nil
                            } else {
                                remote.perform([.click()])
                                lastTapAt = Date()
                            }
                        }
                        lastTranslation = .zero
                        moved = false
                    }
            )
            .focusable(true)
            .digitalCrownRotation($crown, from: -100_000, through: 100_000, by: 1,
                                  sensitivity: .medium, isContinuous: true,
                                  isHapticFeedbackEnabled: true)
            .onChange(of: crown) { old, new in remote.scroll((old - new) * 8) }
    }

    /// The five controls that drive the Mac, at a size a finger can actually pick out.
    ///
    /// This row was 30 points tall with 4pt gaps and `.mini` buttons — five targets
    /// across a 40mm screen, each about 24pt, sitting directly under a trackpad that
    /// swallows any touch that misses. Click and Drag lock next to each other at that
    /// size is a coin toss, and one of them holds the mouse button down on a live Mac.
    private var controls: some View {
        HStack(spacing: 6) {
            // Primary action = the Double Tap hand gesture on Series 9 and later, which
            // is the pinch-to-click WowMouse is built around — native, no BLE needed.
            primaryClickButton
            // These two used to be `hand.point.up.braille` and `hand.raised`: two hands,
            // side by side, at caption size on a 40mm screen, distinguished only by
            // fill. Asked what they did, the person who uses this every day said "the
            // hand symbol icon, which I am not able to understand" — and could not say
            // which hand he meant, which is the whole problem in one sentence.
            //
            // Now each glyph says its own name. A gyroscope is the motion sensor that
            // drives the arm-pointing cursor; a padlock is the lock in "drag lock", and
            // it opens when the button is released. Tints stay, because on a screen this
            // size colour is read before shape.
            padButton("gyroscope",
                      remote.airMouse ? "Air mouse on" : "Air mouse",
                      tint: remote.airMouse ? .blue : nil) { remote.setAirMouse(!remote.airMouse) }
            padButton(remote.dragLocked ? "lock.fill" : "lock.open",
                      remote.dragLocked ? "Drag lock on" : "Drag lock",
                      tint: remote.dragLocked ? .orange : nil) { remote.toggleDragLock() }
            padButton("keyboard", "Type") { typing = true }
            NavigationLink {
                RemoteHubView(remote: remote)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
                    .frame(maxWidth: .infinity, minHeight: RemoteTouch.minHeight)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("More Mac controls")
        }
        .frame(height: RemoteTouch.minHeight)
    }

    @ViewBuilder
    private var primaryClickButton: some View {
        let button = Button { remote.perform([.click()]) } label: {
            Image(systemName: "cursorarrow.click")
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: RemoteTouch.minHeight)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Click")

        if #available(watchOS 11.0, *) {
            button.handGestureShortcut(.primaryAction)
        } else {
            button
        }
    }

    /// Lives on the pad itself (like the preview's zoom chips) because the controls
    /// row is already full on a 40mm screen.
    private var padModeChip: some View {
        Button { padOnly.toggle() } label: {
            Image(systemName: padOnly
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
        }
        .font(.system(size: 9, weight: .bold))
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .padding(2)
        .accessibilityLabel(padOnly ? "Show screen preview" : "Full trackpad")
    }

    private func padButton(_ symbol: String, _ label: String, tint: Color? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: RemoteTouch.minHeight)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(tint)
        .accessibilityLabel(label)
    }
}

/// The floor for controls on the remote-control screen. Slightly shorter than a list
/// row's, because five of them share one line above a trackpad that will happily eat
/// anything that misses — but never again the ~24pt `.mini` gives you.
enum RemoteTouch {
    static let minHeight: CGFloat = 38
}

// MARK: - Hub

/// One screen listing what the Mac can be told to do, each area its own short page.
/// The previous single Keys screen had grown to eleven sections — on a 40mm display
/// that is a scroll marathon to reach "lock screen".
struct RemoteHubView: View {
    @ObservedObject var remote: RemoteControl

    /// System-wide chords worth one tap; everything else lives on its own page.
    private let quick: [(String, String, String, [String])] = [
        ("Spotlight", "magnifyingglass", "space", ["cmd"]),
        ("Mission Control", "rectangle.3.group", "up", ["ctrl"]),
        ("App windows", "rectangle.stack", "down", ["ctrl"]),
        ("Screenshot", "camera.viewfinder", "4", ["cmd", "shift"]),
        ("Show desktop", "menubar.dock.rectangle", "f11", []),
        ("Force quit", "xmark.octagon", "escape", ["cmd", "opt"]),
    ]

    var body: some View {
        List {
            Section("Quick") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(quick, id: \.0) { name, symbol, key, mods in
                        Button { remote.perform([.key(key, mods)]) } label: {
                            Image(systemName: symbol).font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel(name)
                    }
                }
            }
            Section {
                NavigationLink { RemoteAppsView(remote: remote) } label: {
                    Label("Apps", systemImage: "square.grid.2x2")
                }
                NavigationLink { RemoteKeysView(remote: remote) } label: {
                    Label("Keyboard", systemImage: "keyboard")
                }
                NavigationLink { RemoteWindowView(remote: remote) } label: {
                    Label("Windows", systemImage: "macwindow")
                }
                NavigationLink { RemoteMediaView(remote: remote) } label: {
                    Label("Media & sound", systemImage: "speaker.wave.2")
                }
                NavigationLink { RemoteSystemView(remote: remote) } label: {
                    Label("System", systemImage: "power")
                }
                NavigationLink { RemoteClipboardView(remote: remote) } label: {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                }
            }
            Section("Mouse") {
                HStack(spacing: 4) {
                    Button { remote.perform([.click(count: 2)]) } label: { Image(systemName: "cursorarrow.click.2") }
                        .accessibilityLabel("Double click")
                    Button { remote.perform([.click("right")]) } label: { Image(systemName: "cursorarrow.rays") }
                        .accessibilityLabel("Right click")
                    Button { remote.perform([.click("middle")]) } label: { Image(systemName: "cursorarrow.motionlines") }
                        .accessibilityLabel("Middle click")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Toggle("Crown scrolls sideways", isOn: $remote.horizontalScroll)
                    .font(.caption2)
            }
            if let status = remote.status, !status.trusted {
                Section("Permission") {
                    Text(status.hint ?? status.error ?? "meshd cannot inject input yet.")
                        .font(.caption2).foregroundStyle(.orange)
                    Button("Ask the Mac now") { Task { await remote.refreshStatus(prompt: true) } }
                }
            }
        }
        .navigationTitle("Mac")
    }
}

// MARK: - Keyboard

struct RemoteKeysView: View {
    @ObservedObject var remote: RemoteControl

    private let shortcuts: [(String, String, [String])] = [
        ("Copy", "c", ["cmd"]),
        ("Paste", "v", ["cmd"]),
        ("Cut", "x", ["cmd"]),
        ("Undo", "z", ["cmd"]),
        ("Save", "s", ["cmd"]),
        ("Select all", "a", ["cmd"]),
        ("Find", "f", ["cmd"]),
        ("Switch app", "tab", ["cmd"]),
        ("Close window", "w", ["cmd"]),
        ("Quit app", "q", ["cmd"]),
    ]

    var body: some View {
        List {
            Section("Keys") {
                HStack(spacing: 4) {
                    keyButton("return", "return")
                    keyButton("escape", "escape")
                    keyButton("delete", "delete.left")
                    keyButton("tab", "arrow.right.to.line")
                }
                HStack(spacing: 4) {
                    keyButton("up", "arrow.up")
                    keyButton("down", "arrow.down")
                    keyButton("left", "arrow.left")
                    keyButton("right", "arrow.right")
                }
            }
            Section("Hold for next key") {
                HStack(spacing: 4) {
                    // The glyphs, not the words. Spelled out, "cmd" and "shift" wrapped
                    // mid-word inside a 40mm chip — the row read "cm d / shi ft / opt /
                    // ctrl", which is unreadable and looks broken. ⌘⇧⌥⌃ are the symbols
                    // already printed on the keyboard these keys live on, they are one
                    // glyph wide so nothing can wrap, and they are what a Mac user is
                    // looking for when reading a shortcut back.
                    ForEach(Self.modifiers, id: \.name) { mod in
                        Button(mod.glyph) {
                            if remote.sticky.contains(mod.name) { remote.sticky.remove(mod.name) }
                            else { remote.sticky.insert(mod.name) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(remote.sticky.contains(mod.name) ? .orange : nil)
                        // The glyph carries no meaning to VoiceOver, so the word does.
                        .accessibilityLabel(mod.spoken)
                        .accessibilityValue(remote.sticky.contains(mod.name) ? "held" : "off")
                    }
                }
            }
            Section {
                NavigationLink { RemoteKeyboardView(remote: remote) } label: {
                    Label("Every key", systemImage: "keyboard.badge.ellipsis")
                }
            }
            Section("Shortcuts") {
                ForEach(shortcuts, id: \.0) { name, key, mods in
                    Button(name) { remote.perform([.key(key, mods)]) }
                }
            }
        }
        .navigationTitle("Keyboard")
    }

    /// The sticky modifiers, as the glyph on the keycap plus the word VoiceOver says.
    ///
    /// `name` is the wire value and must stay one of the strings MODIFIERS accepts in
    /// install/payload/bin/mesh-input.swift — cmd, shift, opt, ctrl, fn. A glyph that
    /// looks right but carries a name the Mac cannot map is a key that silently does
    /// nothing, so check-mesh-input asserts these against the helper's own table.
    ///
    /// fn keeps its letters: Apple prints "fn" on the key itself (the globe is a
    /// different, newer thing), and two characters cannot wrap.
    static let modifiers: [(name: String, glyph: String, spoken: String)] = [
        ("cmd",   "⌘",  "Command"),
        ("shift", "⇧",  "Shift"),
        ("opt",   "⌥",  "Option"),
        ("ctrl",  "⌃",  "Control"),
        ("fn",    "fn", "Function"),
    ]

    private func keyButton(_ key: String, _ symbol: String) -> some View {
        Button { remote.key(key) } label: { Image(systemName: symbol).font(.caption) }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .accessibilityLabel(key)
    }
}

// MARK: - Windows

struct RemoteWindowView: View {
    @ObservedObject var remote: RemoteControl

    var body: some View {
        List {
            Section(remote.displays.count > 1 ? "Snap on display \(remote.activeDisplay)" : "Snap") {
                HStack(spacing: 4) {
                    windowButton("left", "rectangle.lefthalf.filled")
                    windowButton("right", "rectangle.righthalf.filled")
                    windowButton("full", "rectangle.fill")
                }
                HStack(spacing: 4) {
                    windowButton("top", "rectangle.tophalf.filled")
                    windowButton("bottom", "rectangle.bottomhalf.filled")
                    windowButton("center", "rectangle.center.inset.filled")
                }
            }
            if remote.displays.count > 1 {
                Section("Move window to") {
                    ForEach(remote.displays) { display in
                        Button(display.label) {
                            remote.perform([.window("full", display: display.index)])
                            remote.activeDisplay = display.index
                        }
                        .lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("Windows")
    }

    private func windowButton(_ place: String, _ symbol: String) -> some View {
        Button { remote.snap(place) } label: { Image(systemName: symbol).font(.caption) }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .accessibilityLabel("Snap window \(place)")
    }
}

// MARK: - Media & sound

struct RemoteMediaView: View {
    @ObservedObject var remote: RemoteControl

    var body: some View {
        List {
            Section("Playback") {
                HStack(spacing: 4) {
                    mediaButton("previous", "backward.end", "Previous track")
                    mediaButton("playpause", "playpause", "Play or pause")
                    mediaButton("next", "forward.end", "Next track")
                }
                HStack(spacing: 4) {
                    mediaButton("rewind", "backward", "Rewind")
                    mediaButton("fastforward", "forward", "Fast forward")
                }
                // Not "back 10 seconds": these are the NX_KEYTYPE_REWIND / _FAST media
                // keys, and how far they move — if at all — is the playing app's
                // decision. macOS has no system-wide ten-second seek to promise
                // instead, and on Linux xdotool maps them to prev/next track outright.
                Text("Rewind · Fast forward")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Section("Volume") {
                HStack(spacing: 4) {
                    Button { remote.volume(delta: -10) } label: { Image(systemName: "speaker.minus") }
                    Button { remote.volume(delta: 10) } label: { Image(systemName: "speaker.plus") }
                    Button { remote.volume(muted: true) } label: { Image(systemName: "speaker.slash") }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            Section("Brightness") {
                HStack(spacing: 4) {
                    mediaButton("brightnessdown", "sun.min")
                    mediaButton("brightnessup", "sun.max")
                    mediaButton("keyboardbrightnessdown", "keyboard.chevron.compact.down")
                    mediaButton("keyboardbrightnessup", "keyboard")
                }
            }
        }
        .navigationTitle("Media")
    }

    private func mediaButton(_ key: String, _ symbol: String, _ label: String? = nil) -> some View {
        Button { remote.media(key) } label: { Image(systemName: symbol).font(.caption) }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .accessibilityLabel(label ?? key)
    }
}

// MARK: - System

struct RemoteSystemView: View {
    @ObservedObject var remote: RemoteControl
    @State private var armSleep = false

    var body: some View {
        List {
            Button("Lock screen") { remote.system("lock") }
            Button("Sleep display") { remote.system("displaysleep") }
            Button("Screen saver") { remote.system("screensaver") }
            // Two taps: sleeping the Mac cuts the very link being used to send this,
            // and an accidental wrist tap mid-agent-run is expensive.
            Button(armSleep ? "Tap again to sleep Mac" : "Sleep Mac") {
                if armSleep { remote.system("sleep"); armSleep = false } else { armSleep = true }
            }
            .foregroundStyle(armSleep ? .orange : .primary)
        }
        .navigationTitle("System")
    }
}

// MARK: - Clipboard

struct RemoteClipboardView: View {
    @ObservedObject var remote: RemoteControl
    @State private var macClipboard: String?
    @State private var loading = false
    @State private var phoneClipboard: String?
    @State private var phoneProblem: String?
    @State private var loadingPhone = false

    var body: some View {
        List {
            Section("Mac") {
                Button("Read Mac clipboard") {
                    loading = true
                    Task {
                        macClipboard = await remote.pullClipboard() ?? "(unavailable)"
                        loading = false
                    }
                }
                if loading {
                    ProgressView()
                } else if let macClipboard {
                    Text(macClipboard.isEmpty ? "(empty)" : macClipboard)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            // The other direction, which the screen offered no way to ask for even
            // though the phone has answered this exact request since the relay learned
            // `readPhoneClipboard`. Copying a URL or a key on the phone and reading it
            // on the wrist is the common case; there is no scribble surface wide enough
            // to retype either.
            Section("iPhone") {
                Button("Read iPhone clipboard") {
                    loadingPhone = true
                    phoneProblem = nil
                    Task {
                        switch await WatchMeshStore.phoneClipboardText() {
                        case .text(let text): phoneClipboard = text
                        case .problem(let why): phoneProblem = why; phoneClipboard = nil
                        }
                        loadingPhone = false
                    }
                }
                if loadingPhone {
                    ProgressView()
                } else if let phoneProblem {
                    // iOS only hands a pasteboard to a foreground app, so "empty" and
                    // "you're not looking at the phone" are different answers and must
                    // never both render as a blank line.
                    Text(phoneProblem)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if let phoneClipboard {
                    Text(phoneClipboard)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Dictate into the Mac's clipboard from the Type button on the trackpad.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Clipboard")
    }
}

// MARK: - Full keyboard

/// Every key the Mac knows, so a modified keystroke (ctrl-C, cmd-K, alt-F) is
/// reachable — dictation can produce letters but never a chord. Rows are literals so
/// check-mesh-input can prove each one maps to a keycode.
let KEYBOARD_ROWS: [[String]] = [
    ["q", "w", "e", "r", "t", "y"],
    ["u", "i", "o", "p", "a", "s"],
    ["d", "f", "g", "h", "j", "k"],
    ["l", "z", "x", "c", "v", "b"],
    ["n", "m", "-", "=", "[", "]"],
    ["1", "2", "3", "4", "5", "6"],
    ["7", "8", "9", "0", ";", "'"],
    [",", ".", "/", "grave", "space", "tab"],
]

let FUNCTION_ROWS: [[String]] = [
    ["f1", "f2", "f3", "f4", "f5", "f6"],
    ["f7", "f8", "f9", "f10", "f11", "f12"],
    ["home", "end", "pageup", "pagedown", "forwarddelete", "escape"],
]

struct RemoteKeyboardView: View {
    @ObservedObject var remote: RemoteControl

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 6)

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                modifierRow
                grid(KEYBOARD_ROWS)
                Text("Function & navigation").font(.caption2).foregroundStyle(.secondary)
                grid(FUNCTION_ROWS)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Keyboard")
    }

    /// Sticky, so a chord is two taps rather than an impossible simultaneous press.
    private var modifierRow: some View {
        HStack(spacing: 3) {
            ForEach(["cmd", "shift", "opt", "ctrl"], id: \.self) { mod in
                Button(mod) {
                    if remote.sticky.contains(mod) { remote.sticky.remove(mod) } else { remote.sticky.insert(mod) }
                } 
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(remote.sticky.contains(mod) ? .orange : nil)
            }
        }
    }

    private func grid(_ rows: [[String]]) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(rows.flatMap { $0 }, id: \.self) { key in
                Button(label(key)) { remote.key(key) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .font(.system(size: 11))
                    .accessibilityLabel(key)
            }
        }
    }

    private func label(_ key: String) -> String {
        switch key {
        case "grave": return "`"
        case "space": return "␣"
        case "tab": return "⇥"
        case "escape": return "esc"
        case "forwarddelete": return "⌦"
        case "pageup": return "⇞"
        case "pagedown": return "⇟"
        default: return key
        }
    }
}

// MARK: - Apps

/// Switch to what's already running, or launch anything installed. Running first —
/// switching is the common case; launching is the occasional one.
struct RemoteAppsView: View {
    @ObservedObject var remote: RemoteControl
    @State private var list: AppList?
    @State private var loading = true

    var body: some View {
        List {
            if let list {
                Section("Running") {
                    ForEach(list.running) { app in
                        Button {
                            remote.activate(app.name)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: app.front == true ? "largecircle.fill.circle" : "circle")
                                    .font(.caption2)
                                    .foregroundStyle(app.front == true ? .green : .secondary)
                                Text(app.name).lineLimit(1)
                            }
                        }
                    }
                }
                Section("Launch") {
                    ForEach(list.installed.filter { name in
                        !list.running.contains { $0.name == name }
                    }, id: \.self) { name in
                        Button(name) { remote.activate(name) }
                            .lineLimit(1)
                    }
                }
            } else if loading {
                ProgressView("Reading apps…")
            } else {
                Text("Could not read the app list.")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .navigationTitle("Apps")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        list = await remote.apps()
        loading = false
    }
}

// MARK: - Dictate / scribble text into the Mac

private struct TypeSheet: View {
    @ObservedObject var remote: RemoteControl
    @Binding var presented: Bool
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // Every line typed from here goes to a shell or an agent prompt, where
                // the watch keyboard's automatic capital turns `git status` into
                // `Git status` — a command not found, for a reason nothing on screen
                // explains. Never lowercase the text instead: that would mangle paths,
                // flags and proper nouns the user typed deliberately.
                TextField("Type or dictate…", text: $text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                DictateLink(draft: $text)
                HStack(spacing: 6) {
                    Button("Type") { send(withReturn: false) }
                        .buttonStyle(.bordered)
                    Button("Type ⏎") { send(withReturn: true) }
                        .buttonStyle(.borderedProminent)
                }
                .disabled(text.isEmpty)
                Button("Send to Mac clipboard") {
                    remote.pushClipboard(text)
                    text = ""
                    presented = false
                }
                .font(.caption2)
                .disabled(text.isEmpty)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { presented = false } }
            }
        }
    }

    private func send(withReturn: Bool) {
        remote.perform(withReturn ? [.text(text), .key("return")] : [.text(text)])
        text = ""
        presented = false
    }
}

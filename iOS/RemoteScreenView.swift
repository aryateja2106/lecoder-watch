import SwiftUI
import UIKit

/// Drive a Mac from the phone: its live screen, a pointer you can see, and a keyboard
/// with the modifiers that actually matter.
///
/// The thing that makes remote control on a phone usable is not the trackpad, it is
/// being able to *see where you are about to click*. At fit-to-screen a 1512-point
/// display is ~390 points wide, the real cursor is two pixels, and you are aiming
/// blind. So this draws its own pointer, sends absolute positions rather than relative
/// deltas (a drawn cursor and a relative protocol drift apart within seconds), and
/// zooms — with the view following the pointer so there is nothing to pan.
@MainActor
final class RemoteScreenModel: ObservableObject {
    @Published var screen: Data?
    @Published var displays: [DisplayInfo] = []
    @Published var activeDisplay: Int = 1
    @Published var status: InputStatus?
    @Published var platform: String?
    @Published var capabilities: [String] = []
    @Published var note: String?

    /// Normalized 0…1 within the active display. The single source of truth for both
    /// the cursor we draw and the coordinate we send.
    @Published var pointer = CGPoint(x: 0.5, y: 0.5)
    @Published var zoom: CGFloat = 1
    /// Sticky modifiers, cleared by the next non-modifier key — so ⌘⇧4 works.
    @Published var mods: Set<String> = []

    let machine: Machine
    private var client: MeshClient { MeshClient(machine: machine) }
    private var pump: Task<Void, Never>?
    private var flush: Task<Void, Never>?
    private var pendingPointer: CGPoint?

    /// Linux meshd serves input, files and a shell but cannot capture a screen, so the
    /// picture is the one part of this view that legitimately never arrives.
    var canSeeScreen: Bool { capabilities.isEmpty || capabilities.contains("screenPeek") }
    var pasteModifier: String { (platform ?? "darwin").hasPrefix("darwin") ? "cmd" : "ctrl" }

    init(machine: Machine) { self.machine = machine }

    /// Measured from the screenshot rather than from `/displays`, so aiming is right
    /// from the first frame instead of after the second request answers.
    var imageAspect: Double {
        if let screen, let image = UIImage(data: screen), image.size.height > 0 {
            return Double(image.size.width / image.size.height)
        }
        return displays.first { $0.index == activeDisplay }?.aspect ?? 1.6
    }

    private var displayArgument: Int {
        displays.first { $0.index == activeDisplay }?.index ?? displays.first?.index ?? 1
    }

    // MARK: Lifecycle

    func start() {
        Task { await refreshMeta() }
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshScreen()
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    func stop() {
        pump?.cancel(); pump = nil
        flush?.cancel(); flush = nil
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

    private func refreshScreen() async {
        guard canSeeScreen else { return }
        // Always name a display: meshd honours ?width= only on that path, and its
        // 480px default is sized for a watch. Ask for more when zoomed, because that is
        // exactly when the extra detail is the point.
        let width = zoom > 2 ? 2000 : 1400
        if let shot = try? await client.screenImage(display: displayArgument, width: width) { screen = shot }
    }

    // MARK: Pointer

    func movePointer(by delta: CGSize, container: CGSize) {
        pointer = movedPointer(pointer, by: delta, imageAspect: imageAspect,
                               container: container, zoom: zoom)
        schedulePointerSend()
    }

    func placePointer(at normalized: CGPoint) {
        pointer = normalized
        schedulePointerSend()
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
        guard let p = pendingPointer else { return }
        pendingPointer = nil
        try? await client.input([.moveTo(x: p.x, y: p.y, display: displayArgument)])
    }

    /// Land the pointer where it is drawn before acting, so a click can never fire at a
    /// position the coalescing timer has not sent yet.
    func click(_ button: String = "left", count: Int = 1) {
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
        Task { try? await client.input(events) }
    }

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
        pointer = CGPoint(x: 0.5, y: 0.5)
        schedulePointerSend()
        flash("Pointer recentred")
    }

    func resetZoom() { zoom = 1 }

    /// Paste what is on the phone into whatever has focus on the Mac. Two steps, because
    /// the far side pastes from its own clipboard: put the text there, then press the
    /// paste chord.
    func pasteFromPhone() {
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

    /// The inverse, which is the one you want after an agent prints a URL or a token.
    func copyFromMachine() {
        Task {
            if let text = try? await client.clipboard(), !text.isEmpty {
                UIPasteboard.general.string = text
                flash("Copied \(text.count) characters from \(machine.host)")
            } else {
                flash("\(machine.host)'s clipboard is empty")
            }
        }
    }

    private func flash(_ message: String) {
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
    var onDoubleTap: () -> Void
    var onSecondaryTap: () -> Void
    var onZoom: (CGFloat) -> Void           // incremental scale factor
    var onDragBegan: () -> Void
    var onDragEnded: () -> Void

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
            parent.onZoom(g.scale)
            g.scale = 1
        }

        @objc func tap(_ g: UITapGestureRecognizer) { parent.onTap(g.location(in: g.view)) }
        @objc func doubleTap(_ g: UITapGestureRecognizer) { parent.onDoubleTap() }
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
    @FocusState private var typingFocused: Bool

    init(machine: Machine) {
        _remote = StateObject(wrappedValue: RemoteScreenModel(machine: machine))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                screenSurface
                if let status = remote.status, status.ok, !status.trusted { notTrustedBanner(status) }
                controlBar
                if keyboardUp { keyboardPane }
            }
        }
        .navigationTitle(remote.machine.host)
        .navigationBarTitleDisplayMode(.inline)
        // The tab bar costs ~80 points of a screen whose entire job is showing another
        // screen, and it is the one place in the app you have already arrived at.
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarContent }
        .overlay(alignment: .top) { toast }
        .onAppear { remote.start() }
        .onDisappear { remote.stop() }
    }

    // MARK: Screen, pointer, gestures

    private var screenSurface: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if let data = remote.screen, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(remote.zoom)
                        .offset(zoomedOffset(pointer: remote.pointer, imageAspect: remote.imageAspect,
                                             container: size, zoom: remote.zoom))
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .animation(.interactiveSpring(duration: 0.18), value: remote.zoom)
                } else if !remote.canSeeScreen {
                    ContentUnavailableView {
                        Label("No screen to show", systemImage: "display.slash")
                    } description: {
                        Text("\(remote.machine.host) runs Linux, where meshd can send keys and clicks but cannot capture the screen. The trackpad and keyboard below still work.")
                    }
                } else {
                    VStack(spacing: 10) {
                        ProgressView().tint(.secondary)
                        Text("Waiting for \(remote.machine.host)'s screen")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if remote.screen != nil { pointerCursor(in: size) }

                TrackpadSurface(
                    onMove: { remote.movePointer(by: $0, container: size) },
                    onScroll: { remote.scroll($0) },
                    onTap: { _ in remote.click() },
                    onDoubleTap: { remote.click(count: 2) },
                    onSecondaryTap: { remote.click("right") },
                    onZoom: { remote.zoom = clampedZoom(remote.zoom * $0) },
                    onDragBegan: { remote.dragBegan() },
                    onDragEnded: { remote.dragEnded() },
                )
            }
        }
    }

    /// The cursor we draw. It is the whole reason this screen is usable: the real
    /// pointer on a 1512-point display is invisible once the picture is 390 points wide,
    /// so aiming has to happen against something you can actually see.
    private func pointerCursor(in size: CGSize) -> some View {
        let at = pointerScreenPosition(pointer: remote.pointer, imageAspect: remote.imageAspect,
                                       container: size, zoom: remote.zoom)
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
            Button { remote.click("right") } label: { Image(systemName: "cursorarrow.click.badge.clock") }
                .buttonStyle(.bordered).controlSize(.small)
            Divider().frame(height: 18)
            Button { remote.zoom = clampedZoom(remote.zoom - 1) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(remote.zoom <= 1)
            Text(String(format: "%.1f×", remote.zoom))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 34)
            Button { remote.zoom = clampedZoom(remote.zoom + 1) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(remote.zoom >= 6)
            Spacer()
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
                Divider()
                Button { remote.pasteFromPhone() } label: {
                    Label("Paste from iPhone", systemImage: "doc.on.clipboard")
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

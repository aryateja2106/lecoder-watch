import SwiftUI
import UIKit

/// Drive a Mac from the phone: its live screen, a real trackpad, and a keyboard.
///
/// This replaces a `WKWebView` pointed at meshd's own `/desktop` page. The web page
/// works, but a browser cannot give you the two things that make remote control
/// tolerable on a phone — inertia-free relative pointer movement and a two-finger
/// scroll that is not also a page scroll — and it cannot reach the system clipboard.
///
/// Every endpoint used here already existed for the watch (`Watch/RemoteView.swift`);
/// this is the same protocol with a screen big enough to aim at.
@MainActor
final class RemoteScreenModel: ObservableObject {
    @Published var screen: Data?
    @Published var displays: [DisplayInfo] = []
    @Published var activeDisplay: Int = 1
    @Published var status: InputStatus?
    @Published var platform: String?
    @Published var capabilities: [String] = []
    @Published var trackpadMode = true
    @Published var note: String?

    let machine: Machine
    private var client: MeshClient { MeshClient(machine: machine) }
    private var pump: Task<Void, Never>?

    /// Accumulated pointer delta, flushed on a short timer. A drag callback can fire
    /// far faster than the network round-trip, and posting one request per callback
    /// turns a smooth swipe into a queue of stale moves arriving after your finger
    /// stopped. Same reason the watch coalesces.
    private var pendingDX = 0.0
    private var pendingDY = 0.0
    private var flush: Task<Void, Never>?

    /// Linux meshd serves input, files and a shell but cannot capture a screen, so the
    /// picture is the one part of this view that legitimately never arrives. Say that
    /// instead of spinning forever.
    var canSeeScreen: Bool { capabilities.isEmpty || capabilities.contains("screenPeek") }

    /// Whichever modifier means "paste" on the far side.
    var pasteModifier: String { (platform ?? "darwin").hasPrefix("darwin") ? "cmd" : "ctrl" }

    init(machine: Machine) { self.machine = machine }

    var currentAspect: Double? {
        displays.first { $0.index == activeDisplay }?.aspect
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
        // 480px default is sized for a watch — on a phone it is unreadable.
        let display = displays.first { $0.index == activeDisplay }?.index ?? displays.first?.index ?? 1
        if let shot = try? await client.screenImage(display: display, width: 1400) { screen = shot }
    }

    // MARK: Input

    func move(dx: Double, dy: Double) {
        pendingDX += dx
        pendingDY += dy
        guard flush == nil else { return }
        flush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            await self?.flushMove()
        }
    }

    private func flushMove() async {
        flush = nil
        let (dx, dy) = (pendingDX, pendingDY)
        pendingDX = 0; pendingDY = 0
        guard dx != 0 || dy != 0 else { return }
        try? await client.input([.move(dx: dx, dy: dy)])
    }

    func send(_ events: [InputEvent]) {
        Task { try? await client.input(events) }
    }

    /// A tap on the picture itself, in direct mode: put the pointer exactly there and
    /// click. `normalizedPreviewPoint` accounts for the letterboxing, so a tap in the
    /// black bars correctly lands nowhere rather than at the edge of the screen.
    func tap(at point: CGPoint, in size: CGSize) {
        guard let aspect = currentAspect ?? imageAspect,
              let p = normalizedPreviewPoint(tap: point, container: size, imageAspect: aspect) else { return }
        send([.moveTo(x: p.x, y: p.y, display: displays.count > 1 ? activeDisplay : nil), .click()])
    }

    /// Measured from the screenshot itself, so aiming works before `/displays` answers.
    var imageAspect: Double? {
        guard let screen, let image = UIImage(data: screen), image.size.height > 0 else { return nil }
        return Double(image.size.width / image.size.height)
    }

    func recenterPointer() {
        send([.moveTo(x: 0.5, y: 0.5, display: displays.count > 1 ? activeDisplay : nil)])
        flash("Pointer recentred")
    }

    /// Paste what is on the phone into whatever has focus on the Mac. Two steps,
    /// because the far side pastes from its own clipboard: put the text there, then
    /// press the paste chord.
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

    func type(_ text: String) {
        guard !text.isEmpty else { return }
        send([.text(text)])
    }

    private func flash(_ message: String) {
        note = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if note == message { note = nil }
        }
    }
}

// MARK: - The trackpad

/// Trackpad semantics need UIKit: SwiftUI cannot tell a one-finger drag from a
/// two-finger one, and that difference is move-versus-scroll — the whole gesture
/// vocabulary of a trackpad.
struct TrackpadSurface: UIViewRepresentable {
    var onMove: (CGPoint) -> Void          // relative delta, already gained
    var onScroll: (CGPoint) -> Void
    var onTap: (CGPoint) -> Void           // location, for direct mode
    var onSecondaryTap: () -> Void
    var onDragBegan: () -> Void
    var onDragEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let twoFinger = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.scroll(_:)))
        twoFinger.minimumNumberOfTouches = 2
        twoFinger.maximumNumberOfTouches = 2
        view.addGestureRecognizer(twoFinger)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)

        let twoTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.secondary(_:)))
        twoTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoTap)

        // A press-and-hold that then moves is a drag on a real trackpad: hold the
        // button down, move, release. Without it you cannot move a window.
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = .greatestFiniteMagnitude
        view.addGestureRecognizer(hold)

        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject {
        var parent: TrackpadSurface
        private var last = CGPoint.zero
        private var dragging = false

        init(_ parent: TrackpadSurface) { self.parent = parent }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            let step = hypot(t.x - last.x, t.y - last.y)
            let gain = pointerGain(step: Double(step))
            parent.onMove(CGPoint(x: (t.x - last.x) * gain, y: (t.y - last.y) * gain))
            last = t
            if g.state == .ended || g.state == .cancelled {
                last = .zero
                if dragging { dragging = false; parent.onDragEnded() }
            }
        }

        @objc func scroll(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            parent.onScroll(CGPoint(x: t.x - last.x, y: t.y - last.y))
            last = t
            if g.state == .ended || g.state == .cancelled { last = .zero }
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            parent.onTap(g.location(in: g.view))
        }

        @objc func secondary(_ g: UITapGestureRecognizer) {
            parent.onSecondaryTap()
        }

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
                if let status = remote.status, status.ok, !status.trusted {
                    notTrustedBanner(status)
                }
                if keyboardUp { keyboardBar }
            }
        }
        .navigationTitle(remote.machine.host)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { toast }
        .onAppear { remote.start() }
        .onDisappear { remote.stop() }
    }

    // MARK: Screen + gestures

    private var screenSurface: some View {
        GeometryReader { geo in
            ZStack {
                if let data = remote.screen, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
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

                TrackpadSurface(
                    onMove: { d in
                        guard remote.trackpadMode else { return }
                        remote.move(dx: Double(d.x), dy: Double(d.y))
                    },
                    onScroll: { d in
                        // Natural direction: dragging content up scrolls down.
                        remote.send([.scroll(dx: Double(-d.x), dy: Double(-d.y))])
                    },
                    onTap: { point in
                        if remote.trackpadMode {
                            remote.send([.click()])
                        } else {
                            remote.tap(at: point, in: geo.size)
                        }
                    },
                    onSecondaryTap: { remote.send([.click("right")]) },
                    onDragBegan: { remote.send([.hold]) },
                    onDragEnded: { remote.send([.release]) },
                )
            }
        }
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

    // MARK: Keyboard

    private var keyboardBar: some View {
        VStack(spacing: 8) {
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    keyChip("esc", "escape")
                    keyChip("tab", "tab")
                    keyChip("↩", "return")
                    keyChip("⌫", "delete")
                    keyChip("↑", "up"); keyChip("↓", "down")
                    keyChip("←", "left"); keyChip("→", "right")
                    chordChip("⌘C", "c"); chordChip("⌘V", "v")
                    chordChip("⌘S", "s"); chordChip("⌘W", "w")
                    chordChip("⌘Tab", "tab")
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private func keyChip(_ label: String, _ key: String) -> some View {
        Button(label) { remote.send([.key(key)]) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func chordChip(_ label: String, _ key: String) -> some View {
        Button(label) { remote.send([.key(key, [remote.pasteModifier])]) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func sendTyping() {
        remote.type(typing)
        typing = ""
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { keyboardUp.toggle(); typingFocused = keyboardUp } label: {
                Image(systemName: keyboardUp ? "keyboard.chevron.compact.down" : "keyboard")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: $remote.trackpadMode) {
                    Label("Trackpad mode", systemImage: "cursorarrow.motionlines")
                }
                Button { remote.recenterPointer() } label: {
                    Label("Recenter pointer", systemImage: "scope")
                }
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
                .padding(.bottom, 24)
                .transition(.opacity)
        }
    }
}

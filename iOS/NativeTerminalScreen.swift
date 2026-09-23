// NativeTerminalScreen.swift — the phone terminal as a terminal: SwiftTerm paints the
// pane (colour, cursor, alt-screen) and a fixed key bar sits under it, the way a
// mobile terminal is expected to look (docs/product/moshi-parity-2026-09-22.md).
// Two transports behind one screen: on a `pty` daemon the pane is attached over a
// WebSocket and every keystroke is a raw byte (PtyClient); on a `captureAnsi` daemon the
// screen is repainted from `/output?ansi=1` polls and keys go out over `/send`.
import SwiftUI
import SwiftTerm

struct NativeTerminalScreen: View {
    @EnvironmentObject var store: MeshStore
    let machine: Machine
    let session: Agent
    var initialPane: String? = nil
    /// Inside SessionPeekScreen, which owns the title, the mode picker and the tab bar.
    var embedded: Bool = false

    @StateObject private var terminal = TerminalController()
    /// Set once on appear from the daemon's capabilities; nil until then.
    @State private var pty: PtyClient?
    @State private var paneSize = (cols: 80, rows: 24)
    @State private var lastInteraction = Date.distantPast
    @State private var failure: String?
    @State private var refusal: String?
    /// Tap arms a modifier for one key; a second tap while armed locks it until tapped again.
    enum Modifier { case off, once, locked
        var on: Bool { self != .off }
        mutating func tap() { self = self == .off ? .once : self == .once ? .locked : .off }
        mutating func consumed() { if self == .once { self = .off } }
    }
    @State private var ctrl: Modifier = .off
    @State private var alt: Modifier = .off
    @State private var showDpad = false
    @State private var holdOpenedDpad = false
    /// While selecting, the emulator stops reporting taps to the program, which is the only
    /// way its own double-tap-word / drag-extend selection can run.
    @State private var selecting = false
    @AppStorage("terminalTheme") private var themeName: String = TerminalTheme.moshi.name
    @State private var keyboardShown = false
    @State private var showingVoice = false
    @State private var magnifyStart: Double?
    @AppStorage("terminalFontSize") private var fontSize: Double = 12
    private var theme: TerminalTheme { TerminalTheme.named(themeName) }

    private var client: MeshClient { store.client(for: machine) }
    private var agentKind: AgentCLIKind { AgentCLIKind.detect(from: session.name, agentType: session.agentType) }
    private var muxLabel: String {
        if session.isCmux { return "cmux" }
        if session.isHerdr { return "herdr" }
        let platform = snapshotMachineMatching(machine.host, in: store.snapshot?.machines ?? [])?.stats?.platform ?? "darwin"
        return platform.hasPrefix("darwin") ? "rmux" : "tmux"
    }

    var body: some View {
        GeometryReader { geo in
            // SwiftTerm's TerminalView IS a UIScrollView: it owns the vertical pan and that
            // is how scrollback is reached. Wrapping it in a SwiftUI ScrollView gave the
            // outer one the pan and the terminal would not scroll at all on a real phone —
            // so the wrapper exists only on the polling path, where a detached 80-column
            // pane really is wider than the screen. Streaming sizes the pane to the phone,
            // so there is nothing to wrap.
            let cell = TerminalController.cellWidth(fontSize: fontSize)
            let paneWidth = max(geo.size.width, CGFloat(paneSize.cols) * cell + 8)
            if pty == nil, paneWidth > geo.size.width {
                ScrollView(.horizontal, showsIndicators: false) {
                    SwiftTermView(controller: terminal, fontSize: fontSize, theme: theme)
                        .frame(width: paneWidth, height: geo.size.height)
                }
                .defaultScrollAnchor(.leading)
            } else {
                SwiftTermView(controller: terminal, fontSize: fontSize, theme: theme)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(theme.background)
        // simultaneous, not exclusive: an exclusive gesture here swallowed the terminal's
        // own pan, long-press selection and taps.
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = magnifyStart ?? fontSize
                    if magnifyStart == nil { magnifyStart = start }
                    fontSize = min(22, max(8, start * Double(value.magnification)))
                }
                .onEnded { _ in magnifyStart = nil }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if showDpad { dpad }
                keyBar
            }
        }
        .overlay(alignment: .top) {
            if let line = refusal ?? failure {
                Text(line)
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Theme", selection: $themeName) {
                        ForEach(TerminalTheme.all, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    Button { press([0x0c], key: "ctrl-l") } label: { Label("Clear screen", systemImage: "eraser") }
                } label: {
                    Image(systemName: "paintpalette")
                }
            }
            if !embedded {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(session.displayName).font(.headline).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(agentKind.rawValue)
                            Text(muxLabel)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(agentKind.brandColor.opacity(0.25), in: Capsule())
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(theme.chrome, for: .navigationBar)
        .toolbarColorScheme(theme.dark ? .dark : .light, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        // The terminal is the whole screen; the tab bar comes back on pop.
        .toolbar(embedded ? .visible : .hidden, for: .tabBar)
        .sheet(isPresented: $showingVoice) {
            VoiceInputSheet(onSend: { text in
                showingVoice = false
                terminal.enqueue { await send(text: text) }
            }, onCancel: { showingVoice = false })
        }
        .onAppear {
            // One keystroke per POST, and the POSTs must land in order: fired as
            // independent Tasks they overtook each other and "echo" arrived as "ehco".
            terminal.onBytes = { bytes in terminal.enqueue { await route(bytes) } }
            if pty == nil, client.supports("pty"), !session.isMuxGuest {
                let stream = PtyClient(machine: machine, session: session.name, pane: initialPane)
                stream.onBytes = { data in terminal.feed(data) }
                stream.onState = { state in
                    switch state {
                    case .open: failure = nil
                    case .closed(let why?): failure = "Reconnecting — \(why)"
                    default: break
                    }
                }
                terminal.onResize = { cols, rows in stream.resize(cols: cols, rows: rows) }
                pty = stream
                let size = terminal.size
                stream.connect(cols: size.cols, rows: size.rows)
            }
        }
        .onDisappear { pty?.close() }
        .task(id: session.name) {
            // Polling transport only. Same cadence as the peek screen: 500 ms while the
            // user is driving, 2 s idle, nothing in the background.
            while !Task.isCancelled {
                if pty != nil { try? await Task.sleep(for: .seconds(1)); continue }
                let parked = UIApplication.shared.applicationState == .background
                if !parked { await refresh() }
                let fast = !parked && Date().timeIntervalSince(lastInteraction) < 10
                try? await Task.sleep(for: .milliseconds(fast ? 500 : 2000))
            }
        }
    }

    // MARK: - Key bar

    private var keyBar: some View {
        HStack(spacing: 6) {
            modifierKey("Ctrl", state: $ctrl)
            modifierKey("Alt", state: $alt)
            barKey("Esc") { press([0x1b], key: "escape") }
            barKey("Tab") { press([0x09], key: "tab") }
            // Tap is Up; holding opens the d-pad row (arrows, Enter, Backspace, paging).
            // The button still fires on the release that ends a hold, so that one is eaten.
            barKey("↑") {
                if holdOpenedDpad { holdOpenedDpad = false; return }
                press([0x1b, 0x5b, 0x41], key: "up")
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                holdOpenedDpad = true
                withAnimation(.snappy(duration: 0.15)) { showDpad.toggle() }
            })
            Spacer(minLength: 0)
            barButton(systemImage: "mic.fill") { showingVoice = true }
                .accessibilityLabel("Dictate")
            barButton(systemImage: keyboardShown ? "keyboard.chevron.compact.down" : "keyboard") {
                keyboardShown.toggle()
                terminal.focus(keyboardShown)
            }
            .accessibilityLabel(keyboardShown ? "Hide keyboard" : "Show keyboard")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(theme.chrome)
    }

    // Seven keys at 44pt: wider than the screen and SwiftUI centres the overflow, which
    // pushed the whole terminal a column off the left edge.
    private var dpad: some View {
        HStack(spacing: 6) {
            barIcon("arrow.left", "Left") { press([0x1b, 0x5b, 0x44], key: "left") }
            barIcon("arrow.down", "Down") { press([0x1b, 0x5b, 0x42], key: "down") }
            barIcon("arrow.right", "Right") { press([0x1b, 0x5b, 0x43], key: "right") }
            barIcon("return", "Enter") { press([0x0d], key: "enter") }
            barIcon("delete.left", "Backspace") { press([0x7f], key: "backspace") }
            // Scrollback, not keys: these move the emulator's own view, which is what a
            // TUI in the alternate screen (Claude Code, vim) leaves you with — there the
            // pane has no scrollback of its own to page through.
            barIcon("chevron.up.2", "Scroll back") { terminal.pageUp() }
            barIcon("chevron.down.2", "Scroll forward") { terminal.pageDown() }
            barIcon("arrow.down.to.line", "Jump to the newest output") { terminal.scrollToBottom() }
            barIcon(selecting ? "checkmark.rectangle" : "selection.pin.in.out",
                    selecting ? "Stop selecting" : "Select text") {
                selecting.toggle()
                terminal.setSelecting(selecting)
            }
            if selecting {
                barIcon("doc.on.doc", "Copy the selection") {
                    if let text = terminal.copySelection() { refusal = "Copied \(text.count) characters" }
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 8)
        .frame(maxWidth: .infinity)
        .background(theme.chrome)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func barIcon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 44, height: 34)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .background(SwiftUI.Color.white.opacity(0.12), in: Capsule())
        .accessibilityLabel(label)
    }

    // Fixed widths: five keys and two icons must fit a 402pt phone with the bar's own
    // padding, or SwiftUI centres the overflow and clips Ctrl off the left edge.
    private func barKey(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .medium, design: .monospaced))
                .frame(width: 52, height: 36)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .background(SwiftUI.Color.white.opacity(0.12), in: Capsule())
    }

    private func modifierKey(_ title: String, state: Binding<Modifier>) -> some View {
        let m = state.wrappedValue
        return Button { state.wrappedValue.tap() } label: {
            HStack(spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium, design: .monospaced))
                if m == .locked { Image(systemName: "lock.fill").font(.system(size: 9)) }
            }
            .frame(width: 52, height: 36)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(m.on ? .black : .white)
        .background(m.on ? SwiftUI.Color.orange : SwiftUI.Color.white.opacity(0.12), in: Capsule())
        .accessibilityValue(m == .off ? "off" : m == .once ? "armed" : "locked")
    }

    private func barButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 16, weight: .medium)).frame(width: 40, height: 36)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .background(SwiftUI.Color.white.opacity(0.12), in: Capsule())
    }

    // MARK: - Data

    private func refresh() async {
        do {
            let out = try await client.output(agent: session.name, lines: 500, pane: initialPane, ansi: true)
            if let c = out.cursor, c.cols > 0, c.rows > 0 { paneSize = (c.cols, c.rows) }
            terminal.paint(lines: out.lines, cursor: out.cursor)
            failure = nil
        } catch {
            failure = "\(machine.host) isn't answering"
        }
    }

    /// A key-bar key: the raw bytes when streaming, the daemon's key name when polling.
    private func press(_ bytes: [UInt8], key: String) {
        if let pty { lastInteraction = Date(); pty.send(bytes) }
        else { terminal.enqueue { await send(key: key) } }
    }

    /// Text from dictation or the polling router. Streaming sends the bytes as typed.
    private func send(text: String? = nil, key: String? = nil) async {
        lastInteraction = Date()
        if let pty {
            if let text { pty.send(Array(text.utf8)) }
            if key == "enter" { pty.send([0x0d]) }
            return
        }
        do {
            try await client.send(agent: session.name, text: text, key: key, pane: initialPane)
            refusal = nil
        } catch {
            refusal = "Not delivered: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// Bytes SwiftTerm produced from the system keyboard, a hardware keyboard or its own
    /// accessory. Streaming: straight to the pty, with an armed Ctrl/Alt folded into the
    /// first letter. Polling: TerminalKeyRouter turns them into the daemon's `/send`
    /// vocabulary (pure, checked by scripts/check-native-terminal-keys.sh).
    private func route(_ bytes: [UInt8]) async {
        // `CSI <` is a mouse report the emulator generated (a wheel tick, a click in a TUI),
        // not a keystroke: it must reach the pty byte-for-byte, with no modifier folding and
        // no /send vocabulary. Ahead of TerminalKeyRouter on purpose.
        if bytes.count > 3, bytes[0] == 0x1b, bytes[1] == 0x5b, bytes[2] == 0x3c {
            lastInteraction = Date()
            pty?.send(bytes)
            return
        }
        if let pty {
            lastInteraction = Date()
            pty.send(TerminalKeyRouter.applyModifiers(bytes, ctrl: ctrl.on, alt: alt.on))
        } else {
            for step in TerminalKeyRouter.route(bytes, ctrl: ctrl.on, alt: alt.on) {
                switch step {
                case .text(let t): await send(text: t)
                case .key(let k): await send(key: k)
                case .unsupported(let what): refusal = "\(what) needs the streaming terminal"
                }
            }
        }
        ctrl.consumed(); alt.consumed()
    }
}

// MARK: - SwiftTerm bridge

/// One theme recolours the terminal and the chrome around it. Palettes are the 16 ANSI
/// slots as 0xRRGGBB; background/foreground/cursor follow.
struct TerminalTheme {
    let name: String
    let dark: Bool
    let bg: UInt32, fg: UInt32, cursorHex: UInt32, chromeHex: UInt32
    let palette: [UInt32]

    var background: SwiftUI.Color { SwiftUI.Color(hex: bg) }
    var chrome: SwiftUI.Color { SwiftUI.Color(hex: chromeHex) }
    var foreground: UIColor { UIColor(hex: fg) }
    var cursor: UIColor { UIColor(hex: cursorHex) }
    var ansi: [SwiftTerm.Color] {
        palette.map { SwiftTerm.Color(red8: UInt16(($0 >> 16) & 0xff), green8: UInt16(($0 >> 8) & 0xff), blue8: UInt16($0 & 0xff)) }
    }

    static let moshi = TerminalTheme(name: "Moshi", dark: true, bg: 0x171a21, fg: 0xdbdee6, cursorHex: 0x8cf28c, chromeHex: 0x0f1117, palette: [
        0x1a1b26, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xa9b1d6,
        0x414868, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xc0caf5])
    static let dracula = TerminalTheme(name: "Dracula", dark: true, bg: 0x282a36, fg: 0xf8f8f2, cursorHex: 0xf8f8f2, chromeHex: 0x1e1f29, palette: [
        0x21222c, 0xff5555, 0x50fa7b, 0xf1fa8c, 0xbd93f9, 0xff79c6, 0x8be9fd, 0xf8f8f2,
        0x6272a4, 0xff6e6e, 0x69ff94, 0xffffa5, 0xd6acff, 0xff92df, 0xa4ffff, 0xffffff])
    static let nord = TerminalTheme(name: "Nord", dark: true, bg: 0x2e3440, fg: 0xd8dee9, cursorHex: 0xd8dee9, chromeHex: 0x242933, palette: [
        0x3b4252, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x88c0d0, 0xe5e9f0,
        0x4c566a, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x8fbcbb, 0xeceff4])
    static let paper = TerminalTheme(name: "Paper", dark: false, bg: 0xfafafa, fg: 0x383a42, cursorHex: 0x526eff, chromeHex: 0xececec, palette: [
        0x383a42, 0xe45649, 0x50a14f, 0xc18401, 0x4078f2, 0xa626a4, 0x0184bc, 0xa0a1a7,
        0x696c77, 0xe45649, 0x50a14f, 0xc18401, 0x4078f2, 0xa626a4, 0x0184bc, 0x383a42])
    static let all: [TerminalTheme] = [moshi, dracula, nord, paper]
    static func named(_ name: String) -> TerminalTheme { all.first { $0.name == name } ?? moshi }
}

private extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

@MainActor
final class TerminalController: ObservableObject {
    weak var view: SwiftTerm.TerminalView?
    var onBytes: (([UInt8]) -> Void)?
    private var painted: [String] = []
    private var paintedCursor: AgentOutput.Cursor?

    /// Full repaint per poll: home, clear (not `3J`, so scrollback is left alone), the
    /// pane's lines with their own SGR bytes, then the cursor where tmux says it is.
    func paint(lines: [String], cursor: AgentOutput.Cursor?) {
        guard let view, lines != painted || cursor != paintedCursor else { return }
        painted = lines; paintedCursor = cursor
        var s = "\u{1b}[?25l\u{1b}[H\u{1b}[2J"
        s += lines.joined(separator: "\u{1b}[0m\r\n")
        if let c = cursor { s += "\u{1b}[0m\u{1b}[\(c.y + 1);\(c.x + 1)H" }
        s += "\u{1b}[?25h"
        view.feed(text: s)
    }

    /// Serialises the work the key bar and the emulator hand over, in arrival order.
    private var chain: Task<Void, Never>?
    func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = chain
        chain = Task { await previous?.value; await work() }
    }

    /// Streaming transport: pane bytes straight into the emulator.
    func feed(_ data: Data) { view?.feed(byteArray: ArraySlice([UInt8](data))) }

    /// A screenful of scrollback. SwiftTerm's own pageUp/pageDown already know the one
    /// distinction that matters: in the alternate screen (Claude Code, vim, anything
    /// full-screen) there is no local scrollback, so they send PgUp/PgDn to the program
    /// instead of moving a viewport that cannot move.
    /// Selection mode: taps stop going to the program so SwiftTerm's own selection can run.
    func setSelecting(_ on: Bool) {
        view?.allowMouseReporting = !on
        if !on { view?.selectNone() }
    }

    func copySelection() -> String? {
        guard let text = view?.getSelection(), !text.isEmpty else { return nil }
        UIPasteboard.general.string = text
        view?.selectNone()
        return text
    }

    func pageUp() { view?.pageUp() }
    func pageDown() { view?.pageDown() }
    /// Back to the newest output. `scroll(toPosition:)` takes 0…1 over the scrollback, so
    /// 1 is the end whichever buffer is on screen — and the alternate screen has nowhere
    /// else to be anyway.
    func scrollToBottom() { view?.scroll(toPosition: 1) }

    /// The emulator's current grid, for the attach size.
    var size: (cols: Int, rows: Int) {
        guard let t = view?.getTerminal() else { return (80, 24) }
        return (max(20, t.cols), max(5, t.rows))
    }
    var onResize: ((Int, Int) -> Void)?

    func focus(_ on: Bool) {
        if on { _ = view?.becomeFirstResponder() } else { _ = view?.resignFirstResponder() }
    }

    static func cellWidth(fontSize: Double) -> CGFloat {
        ("W" as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)]).width
    }
}

struct SwiftTermView: UIViewRepresentable {
    let controller: TerminalController
    let fontSize: Double
    let theme: TerminalTheme

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let view = SwiftTerm.TerminalView(frame: .zero, font: font, options: TerminalOptions(scrollback: 2000))
        apply(theme, to: view)
        context.coordinator.themeName = theme.name
        // The key bar below the terminal is the one accessory; SwiftTerm's own would
        // stack a second row of Esc/Ctrl/Tab on top of it whenever the keyboard is up.
        view.inputAccessoryView = nil
        view.terminalDelegate = context.coordinator
        // Scrolling a terminal is two different things and SwiftTerm only does one of them.
        // Its UIScrollView scrolls local scrollback — but `tmux attach` puts us on the
        // ALTERNATE buffer, where there is none (canScroll is false by definition), so a
        // drag had nothing to move and the terminal read as frozen. What a real terminal
        // does there is send wheel events to the program, which is what this pan does.
        let wheel = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.wheelPan(_:)))
        wheel.maximumNumberOfTouches = 1
        wheel.delegate = context.coordinator
        view.addGestureRecognizer(wheel)
        controller.view = view
        return view
    }

    func updateUIView(_ view: SwiftTerm.TerminalView, context: Context) {
        if abs(view.font.pointSize - fontSize) > 0.5 {
            view.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        if context.coordinator.themeName != theme.name {
            context.coordinator.themeName = theme.name
            apply(theme, to: view)
        }
    }

    private func apply(_ theme: TerminalTheme, to view: SwiftTerm.TerminalView) {
        view.nativeBackgroundColor = UIColor(hex: theme.bg)
        view.nativeForegroundColor = theme.foreground
        view.caretColor = theme.cursor
        view.installColors(theme.ansi)
        view.keyboardAppearance = theme.dark ? .dark : .light
        view.backgroundColor = UIColor(hex: theme.bg)
    }

    final class Coordinator: NSObject, TerminalViewDelegate, UIGestureRecognizerDelegate {
        let controller: TerminalController
        var themeName = ""

        /// Never take a gesture away from SwiftTerm's own chain (tap, double tap, long-press
        /// selection, and the scroll view itself).
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// One finger, one wheel tick per row travelled. Local scrollback wins when there is
        /// any; a live selection wins always.
        @objc func wheelPan(_ g: UIPanGestureRecognizer) {
            guard let view = controller.view, !view.canScroll, !view.hasActiveSelection else { return }
            let terminal = view.getTerminal()
            let rows = max(1, terminal.rows)
            let cell = max(1, view.getOptimalFrameSize().height / CGFloat(rows))
            let dy = g.translation(in: view).y
            let lines = Int(dy / cell)
            guard lines != 0 else { return }
            g.setTranslation(CGPoint(x: 0, y: dy - CGFloat(lines) * cell), in: view)
            let up = lines > 0
            if terminal.mouseMode != .off {
                // tmux with `mouse on`, and every TUI that asks for mouse reporting, takes
                // buttons 64/65 as wheel up/down and scrolls itself.
                let flags = terminal.encodeButton(button: up ? 4 : 5, release: false, shift: false, meta: false, control: false)
                let row = min(rows - 1, max(0, Int(g.location(in: view).y / cell)))
                for _ in 0..<abs(lines) { terminal.sendEvent(buttonFlags: flags, x: 0, y: row) }
            } else {
                // No mouse reporting: arrow keys are what a wheel means to a shell's history.
                let key: [UInt8] = up ? [0x1b, 0x5b, 0x41] : [0x1b, 0x5b, 0x42]
                for _ in 0..<abs(lines) { controller.onBytes?(key) }
            }
        }
        init(controller: TerminalController) { self.controller = controller }
        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            Task { @MainActor in controller.onBytes?(bytes) }
        }
        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor in controller.onResize?(newCols, newRows) }
        }
        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) { UIApplication.shared.open(url) }
        }
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            UIPasteboard.general.string = String(decoding: content, as: UTF8.self)
        }
    }
}

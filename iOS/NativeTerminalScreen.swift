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

    @StateObject private var terminal = TerminalController()
    /// Set once on appear from the daemon's capabilities; nil until then.
    @State private var pty: PtyClient?
    @State private var paneSize = (cols: 80, rows: 24)
    @State private var lastInteraction = Date.distantPast
    @State private var failure: String?
    @State private var refusal: String?
    @State private var ctrlArmed = false
    @State private var altArmed = false
    @State private var keyboardShown = false
    @State private var showingVoice = false
    @State private var magnifyStart: Double?
    @AppStorage("terminalFontSize") private var fontSize: Double = 12

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
            // Streaming: the pane is sized to the phone, nothing to scroll. Polling: the
            // pane keeps its own width (a detached tmux session is 80 columns) and the
            // phone scrolls sideways rather than wrapping every TUI line into a riddle.
            let cell = TerminalController.cellWidth(fontSize: fontSize)
            let width = pty != nil ? geo.size.width : max(geo.size.width, CGFloat(paneSize.cols) * cell + 8)
            ScrollView(.horizontal, showsIndicators: false) {
                SwiftTermView(controller: terminal, fontSize: fontSize)
                    .frame(width: width, height: geo.size.height)
            }
            .defaultScrollAnchor(.leading)
            .scrollDisabled(width <= geo.size.width)
        }
        .background(TerminalTheme.moshi.background)
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = magnifyStart ?? fontSize
                    if magnifyStart == nil { magnifyStart = start }
                    fontSize = min(22, max(8, start * Double(value.magnification)))
                }
                .onEnded { _ in magnifyStart = nil }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) { keyBar }
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
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(TerminalTheme.moshi.chrome, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        // The terminal is the whole screen; the tab bar comes back on pop.
        .toolbar(.hidden, for: .tabBar)
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
            modifierKey("Ctrl", armed: $ctrlArmed)
            modifierKey("Alt", armed: $altArmed)
            barKey("Esc") { press([0x1b], key: "escape") }
            barKey("Tab") { press([0x09], key: "tab") }
            barKey("↑") { press([0x1b, 0x5b, 0x41], key: "up") }
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
        .background(TerminalTheme.moshi.chrome)
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

    private func modifierKey(_ title: String, armed: Binding<Bool>) -> some View {
        Button { armed.wrappedValue.toggle() } label: {
            Text(title).font(.system(size: 14, weight: .medium, design: .monospaced))
                .frame(width: 52, height: 36)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(armed.wrappedValue ? .black : .white)
        .background(armed.wrappedValue ? SwiftUI.Color.orange : SwiftUI.Color.white.opacity(0.12), in: Capsule())
        .accessibilityValue(armed.wrappedValue ? "armed" : "off")
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
        if let pty {
            lastInteraction = Date()
            pty.send(TerminalKeyRouter.applyModifiers(bytes, ctrl: ctrlArmed, alt: altArmed))
        } else {
            for step in TerminalKeyRouter.route(bytes, ctrl: ctrlArmed, alt: altArmed) {
                switch step {
                case .text(let t): await send(text: t)
                case .key(let k): await send(key: k)
                case .unsupported(let what): refusal = "\(what) needs the streaming terminal"
                }
            }
        }
        if ctrlArmed || altArmed { ctrlArmed = false; altArmed = false }
    }
}

// MARK: - SwiftTerm bridge

struct TerminalTheme {
    let background: SwiftUI.Color
    let chrome: SwiftUI.Color
    let foreground: UIColor
    let cursor: UIColor
    let ansi: [SwiftTerm.Color]

    static let moshi = TerminalTheme(
        background: SwiftUI.Color(red: 0.09, green: 0.10, blue: 0.13),
        chrome: SwiftUI.Color(red: 0.06, green: 0.07, blue: 0.09),
        foreground: UIColor(red: 0.86, green: 0.87, blue: 0.90, alpha: 1),
        cursor: UIColor(red: 0.55, green: 0.95, blue: 0.55, alpha: 1),
        ansi: [
            (0x1a, 0x1b, 0x26), (0xf7, 0x76, 0x8e), (0x9e, 0xce, 0x6a), (0xe0, 0xaf, 0x68),
            (0x7a, 0xa2, 0xf7), (0xbb, 0x9a, 0xf7), (0x7d, 0xcf, 0xff), (0xa9, 0xb1, 0xd6),
            (0x41, 0x48, 0x68), (0xf7, 0x76, 0x8e), (0x9e, 0xce, 0x6a), (0xe0, 0xaf, 0x68),
            (0x7a, 0xa2, 0xf7), (0xbb, 0x9a, 0xf7), (0x7d, 0xcf, 0xff), (0xc0, 0xca, 0xf5),
        ].map { (rgb: (UInt16, UInt16, UInt16)) -> SwiftTerm.Color in SwiftTerm.Color(red8: rgb.0, green8: rgb.1, blue8: rgb.2) }
    )
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

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let view = SwiftTerm.TerminalView(frame: .zero, font: font, options: TerminalOptions(scrollback: 2000))
        let theme = TerminalTheme.moshi
        view.nativeBackgroundColor = UIColor(theme.background)
        view.nativeForegroundColor = theme.foreground
        view.caretColor = theme.cursor
        view.installColors(theme.ansi)
        view.keyboardAppearance = .dark
        // The key bar below the terminal is the one accessory; SwiftTerm's own would
        // stack a second row of Esc/Ctrl/Tab on top of it whenever the keyboard is up.
        view.inputAccessoryView = nil
        view.terminalDelegate = context.coordinator
        controller.view = view
        return view
    }

    func updateUIView(_ view: SwiftTerm.TerminalView, context: Context) {
        if abs(view.font.pointSize - fontSize) > 0.5 {
            view.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let controller: TerminalController
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

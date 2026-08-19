import SwiftUI
import Combine
import WatchKit

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
    @Published var note: String?
    @Published var dragLocked = false
    @Published var displays: [DisplayInfo] = []
    /// Which screen the preview shows and taps/window snaps target. 1-based.
    @Published var activeDisplay = 1
    /// Crown scrolls sideways instead of up/down — wide timelines, spreadsheets, code.
    @Published var horizontalScroll = false
    @Published var sticky: Set<String> = []      // modifiers held for the next key

    /// Relay through the phone when the watch can't reach meshd itself — the normal
    /// case on a real watch, which has no Tailscale. Slower, so the flush loop backs
    /// off; WCSession is not built for a 25Hz stream.
    @Published private(set) var viaRelay = false
    private var pendingDX = 0.0
    private var pendingDY = 0.0
    private var pendingScroll = 0.0
    private var pendingScrollX = 0.0
    private var discrete: [InputEvent] = []
    private var inFlight = false

    init(machine: Machine) { self.machine = machine }

    /// Credentials can land after the view opens (the phone relays them on its next
    /// poll). Re-probe on the new config so a relayed session upgrades to direct
    /// instead of staying slow until the user backs out and comes in again.
    func update(machine: Machine) {
        guard machine != self.machine else { return }
        self.machine = machine
        Task { await refreshStatus() }
    }

    private var client: MeshClient { MeshClient(machine: machine) }

    // MARK: queueing

    func move(dx: Double, dy: Double) { pendingDX += dx; pendingDY += dy }
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

    func tap(at point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        perform([.moveTo(x: point.x / size.width, y: point.y / size.height, display: activeDisplay),
                 .click()])
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
            // cursor delta is better than a late one.
            viaRelay = true
            note = "via phone"
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
            note = "via phone"
            // The phone can still answer for us — including raising the Accessibility
            // prompt on the Mac, which is the one thing the user must be told about.
            let reply = await WatchLink.shared.request(
                WatchCommand(kind: .inputStatus, host: machine.host, agent: nil,
                             text: prompt ? "prompt" : nil, key: nil))
            status = reply.flatMap { try? JSONDecoder().decode(InputStatus.self, from: $0) }
        }
    }

    func refreshScreen() async {
        screen = try? await client.screenImage(display: displays.count > 1 ? activeDisplay : nil)
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

    func system(_ action: String) {
        guard !viaRelay else {
            WatchLink.shared.send(WatchCommand(kind: .system, host: machine.host, agent: nil,
                                               text: action, key: nil))
            note = action
            return
        }
        Task {
            try? await client.system(action)
            note = action
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

    init(machine: Machine) {
        _remote = StateObject(wrappedValue: RemoteControl(machine: machine))
    }

    var body: some View {
        VStack(spacing: 4) {
            if remote.displays.count > 1 { displayPicker }
            preview
            trackpad
            controls
        }
        .padding(.horizontal, 2)
        .navigationTitle("Control")
        .navigationBarTitleDisplayMode(.inline)
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
                    store.requestScreen(host: remote.machine.host,
                                        display: remote.displays.count > 1 ? remote.activeDisplay : nil)
                } else {
                    await remote.refreshScreen()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onChange(of: store.machines) { _, updated in
            if let match = updated.first(where: { $0.host == remote.machine.host }) {
                remote.update(machine: match)
            }
        }
        .onDisappear { store.stopScreen() }
    }

    /// Direct grab when we have one, else whatever the phone last relayed.
    private var screenData: Data? {
        remote.screen ?? (store.screenHost == remote.machine.host ? store.screenJPEGData : nil)
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
            ZStack {
                if let data = screenData, let image = meshImage(from: data) {
                    image.resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.2))
                        .overlay(Text("screen…").font(.caption2).foregroundStyle(.secondary))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { point in remote.tap(at: point, in: geo.size) }
        }
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var trackpad: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(remote.dragLocked ? Color.orange.opacity(0.28) : Color.gray.opacity(0.22))
            .overlay(alignment: .center) {
                if let note = remote.note {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                } else if remote.status?.trusted == false {
                    Text("Needs Accessibility").font(.caption2).foregroundStyle(.orange)
                } else if remote.dragLocked {
                    Text("drag held").font(.caption2).foregroundStyle(.orange)
                }
            }
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
                        remote.move(dx: dx * 2.2, dy: dy * 2.2)   // watch-sized pad, Mac-sized screen
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        if !moved || distance < 5 { remote.perform([.click()]) }
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

    private var controls: some View {
        HStack(spacing: 4) {
            padButton("cursorarrow.click.2", "Double click") { remote.perform([.click(count: 2)]) }
            padButton("cursorarrow.rays", "Right click") { remote.perform([.click("right")]) }
            padButton(remote.dragLocked ? "hand.raised.fill" : "hand.raised", "Drag lock") {
                remote.toggleDragLock()
            }
            padButton("keyboard", "Type") { typing = true }
            NavigationLink {
                RemoteHubView(remote: remote)
            } label: {
                Image(systemName: "ellipsis.circle").font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .frame(height: 30)
    }

    private func padButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.caption) }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .accessibilityLabel(label)
    }
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
                    mediaButton("previous", "backward.end")
                    mediaButton("playpause", "playpause")
                    mediaButton("next", "forward.end")
                }
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

    private func mediaButton(_ key: String, _ symbol: String) -> some View {
        Button { remote.media(key) } label: { Image(systemName: symbol).font(.caption) }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .accessibilityLabel(key)
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

    var body: some View {
        List {
            Section {
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
                TextField("Type or dictate…", text: $text)
                    .autocorrectionDisabled()
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

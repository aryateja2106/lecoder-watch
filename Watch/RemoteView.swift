import SwiftUI
import Combine

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
    @Published var sticky: Set<String> = []      // modifiers held for the next key

    /// Relay through the phone when the watch can't reach meshd itself — the normal
    /// case on a real watch, which has no Tailscale. Slower, so the flush loop backs
    /// off; WCSession is not built for a 25Hz stream.
    @Published private(set) var viaRelay = false
    private var pendingDX = 0.0
    private var pendingDY = 0.0
    private var pendingScroll = 0.0
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
    func scroll(_ dy: Double) { pendingScroll += dy }

    func perform(_ events: [InputEvent]) {
        discrete.append(contentsOf: events)
        Task { await flush() }
    }

    func tap(at point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        perform([.moveTo(x: point.x / size.width, y: point.y / size.height), .click()])
    }

    func key(_ name: String, _ extraMods: [String] = []) {
        let mods = Array(sticky) + extraMods
        sticky.removeAll()
        perform([.key(name, mods)])
    }

    func toggleDragLock() {
        dragLocked.toggle()
        perform([dragLocked ? .hold : .release])
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
        if abs(pendingScroll) >= 1 {
            batch.append(.scroll(dy: pendingScroll))
            pendingScroll = 0
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
        screen = try? await client.screenImage()
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
            while !Task.isCancelled {
                await remote.flush()
                try? await Task.sleep(for: remote.flushInterval)
            }
        }
        .task {
            // Slow second loop: the preview is for "did that land?", not a video feed.
            while !Task.isCancelled {
                if remote.viaRelay {
                    store.requestScreen(host: remote.machine.host)
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
                RemoteAppsView(remote: remote)
            } label: {
                Image(systemName: "square.grid.2x2").font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            NavigationLink {
                RemoteKeysView(remote: remote)
            } label: {
                Image(systemName: "command").font(.caption)
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

// MARK: - Keys, shortcuts, clipboard, volume

struct RemoteKeysView: View {
    @ObservedObject var remote: RemoteControl
    @State private var macClipboard: String?
    @State private var armSleep = false

    private let shortcuts: [(String, String, [String])] = [
        ("Copy", "c", ["cmd"]),
        ("Paste", "v", ["cmd"]),
        ("Cut", "x", ["cmd"]),
        ("Undo", "z", ["cmd"]),
        ("Save", "s", ["cmd"]),
        ("Select all", "a", ["cmd"]),
        ("Spotlight", "space", ["cmd"]),
        ("Switch app", "tab", ["cmd"]),
        ("Close window", "w", ["cmd"]),
        ("Quit app", "q", ["cmd"]),
    ]

    var body: some View {
        List {
            Section("Keys") {
                HStack(spacing: 4) {
                    keyButton("return", "return")
                    keyButton("escape", "esc")
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
            Section("Shortcuts") {
                ForEach(shortcuts, id: \.0) { name, key, mods in
                    Button(name) { remote.perform([.key(key, mods)]) }
                }
            }
            Section("Media") {
                HStack(spacing: 4) {
                    mediaButton("previous", "backward.end")
                    mediaButton("playpause", "playpause")
                    mediaButton("next", "forward.end")
                }
                HStack(spacing: 4) {
                    mediaButton("brightnessdown", "sun.min")
                    mediaButton("brightnessup", "sun.max")
                    mediaButton("keyboardbrightnessdown", "keyboard.chevron.compact.down")
                    mediaButton("keyboardbrightnessup", "keyboard")
                }
            }
            Section("System") {
                Button("Lock screen") { remote.system("lock") }
                Button("Sleep display") { remote.system("displaysleep") }
                Button("Screen saver") { remote.system("screensaver") }
                // Two taps: sleeping the Mac cuts the very link being used to send
                // this, and an accidental wrist tap mid-agent-run is expensive.
                Button(armSleep ? "Tap again to sleep Mac" : "Sleep Mac") {
                    if armSleep { remote.system("sleep"); armSleep = false } else { armSleep = true }
                }
                .foregroundStyle(armSleep ? .orange : .primary)
            }
            Section("Volume") {
                HStack {
                    Button { remote.volume(delta: -10) } label: { Image(systemName: "speaker.minus") }
                    Button { remote.volume(delta: 10) } label: { Image(systemName: "speaker.plus") }
                    Button { remote.volume(muted: true) } label: { Image(systemName: "speaker.slash") }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            Section("Clipboard") {
                Button("Read Mac clipboard") {
                    Task { macClipboard = await remote.pullClipboard() ?? "(unavailable)" }
                }
                if let text = macClipboard {
                    Text(text.isEmpty ? "(empty)" : text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let status = remote.status, !status.trusted {
                Section("Permission") {
                    Text(status.hint ?? status.error ?? "meshd cannot inject input yet.")
                        .font(.caption2).foregroundStyle(.orange)
                    Button("Ask the Mac now") { Task { await remote.refreshStatus(prompt: true) } }
                }
            }
        }
        .navigationTitle("Keys")
    }

    private func mediaButton(_ key: String, _ symbol: String) -> some View {
        Button { remote.media(key) } label: { Image(systemName: symbol).font(.caption) }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .accessibilityLabel(key)
    }

    private func keyButton(_ key: String, _ symbol: String) -> some View {
        Button { remote.key(key) } label: { Image(systemName: symbol).font(.caption) }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .accessibilityLabel(key)
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

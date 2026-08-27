import SwiftUI
import UIKit
import WebKit

// MARK: - Terminal tab

/// First-class rmux terminal on the phone. Lists every machine that has a bridge
/// deployed, shows its live sessions, and opens a real interactive terminal
/// (the proven rmux-bridge xterm) in a WKWebView. "+" creates a new session.
struct TerminalTab: View {
    @EnvironmentObject var store: MeshStore
    @State private var creatingOn: Machine?

    private var machineRows: [MachineSnapshot] {
        let snaps = store.snapshot?.machines.isEmpty == false
            ? store.snapshot?.machines ?? []
            : store.machines.map { MachineSnapshot(host: $0.host, reachable: false, stats: nil, agents: [], error: "not checked yet") }
        return terminalActiveFirst(snaps)
    }

    private func machine(for host: String) -> Machine? {
        store.machines.first(where: { $0.host == host })
    }

    var body: some View {
        NavigationStack {
            List {
                if machineRows.isEmpty {
                    ContentUnavailableView(
                        "No machines",
                        systemImage: "terminal",
                        description: Text("Add a machine in Settings.")
                    )
                }
                ForEach(machineRows) { snap in
                    if let m = machine(for: snap.host) {
                        Section {
                            if !snap.reachable {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(snap.error ?? "meshd unreachable")
                                        .foregroundStyle(.secondary)
                                    Text("meshd \(m.baseURLs.map(\.absoluteString).joined(separator: " or "))")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text("bridge \(m.resolvedBridge ?? "none")")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            } else if let auth = snap.authError {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(auth)
                                        .foregroundStyle(.orange)
                                    Text("Run mesh pair on \(m.host) and pair again — that replaces the saved token in place.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    CopyableCommand(text: "mesh pair")
                                }
                            }
                            ForEach(snap.agents) { agent in
                                NavigationLink {
                                    SessionPeekScreen(machine: m, session: agent)
                                } label: {
                                    HStack {
                                        Image(systemName: "terminal.fill")
                                        VStack(alignment: .leading) {
                                            Text(agent.displayName)
                                            Text([agent.isCmux ? "cmux" : nil, agent.agentType ?? "shell", agent.memLabel].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if agent.attached {
                                            Image(systemName: "dot.radiowaves.left.and.right")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if !agent.isCmux {
                                        Button(role: .destructive) {
                                            Task { await store.kill(on: m, name: agent.name) }
                                        } label: {
                                            Label("Kill", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            if snap.agents.isEmpty {
                                Text(snap.authError != nil ? "token needed to list sessions" : (snap.reachable ? "no sessions" : "start meshd to list sessions"))
                                    .foregroundStyle(.secondary)
                            }
                            if snap.bridgeReachable == true {
                                NavigationLink {
                                    ManualBridgeScreen(machine: m)
                                } label: {
                                    Label("Open known session", systemImage: "rectangle.connected.to.line.below")
                                }
                            }
                            Button {
                                creatingOn = m
                            } label: {
                                Label("New session", systemImage: "plus.circle")
                            }
                            .disabled(!terminalReady(snap))
                        } header: {
                            HStack {
                                Circle().fill(snap.authError != nil ? .orange : (snap.reachable ? .green : .secondary)).frame(width: 7, height: 7)
                                Text(snap.host)
                                Spacer()
                                // Browsing the machine's own filesystem is the fastest
                                // way to answer "where do I start this?" — and the one
                                // question a phone keyboard is worst at.
                                NavigationLink {
                                    FileBrowserView(machine: m, capabilities: snap.capabilities)
                                } label: {
                                    Label("Files", systemImage: "folder")
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .disabled(!terminalReady(snap))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Terminal")
            .toolbar {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .sheet(item: $creatingOn) { m in
                NewSessionSheet(machine: m)
            }
            // Arriving from meshwatch://session/... — the live card, or anything else
            // that wants to put someone in front of one session.
            .navigationDestination(item: $store.deepLinkSession) { target in
                if let m = machineMatching(target.host, in: store.machines) {
                    SessionPeekScreen(machine: m, session: agent(named: target.session, on: target.host))
                } else {
                    ContentUnavailableView(
                        "Machine not paired",
                        systemImage: "questionmark.folder",
                        description: Text("\(target.host) isn't in your list. Pair it from Machines."),
                    )
                }
            }
        }
    }

    /// The live session if we have it, else a stub by name — a card can outlive the
    /// poll that last saw the session, and landing on "kill it / reply to it" is more
    /// use than landing on "not found".
    private func agent(named name: String, on host: String) -> Agent {
        store.snapshot?.machines.first { $0.host == host }?.agents.first { $0.name == name }
            ?? Agent(name: name, windows: 1, attached: false)
    }
}

private func terminalActiveFirst(_ snaps: [MachineSnapshot]) -> [MachineSnapshot] {
    snaps.sorted {
        if $0.reachable != $1.reachable { return $0.reachable && !$1.reachable }
        if $0.agents.count != $1.agents.count { return $0.agents.count > $1.agents.count }
        return $0.host < $1.host
    }
}

private func terminalReady(_ snap: MachineSnapshot) -> Bool {
    snap.reachable && snap.authError == nil
}

private struct ManualBridgeScreen: View {
    let machine: Machine
    @State private var session = ""

    var body: some View {
        Form {
            Section("Session") {
                TextField("pi-shell", text: $session.shellSafe)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                FlowButtons(items: suggestions) { session = $0 }
                NavigationLink {
                    BridgeTerminalScreen(machine: machine, session: sessionName, initialPane: nil)
                } label: {
                    Label("Open terminal", systemImage: "terminal")
                }
                .disabled(sessionName.isEmpty)
            }
        }
        .navigationTitle(machine.host)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sessionName: String {
        session.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestions: [String] {
        let host = machine.host.lowercased()
        if host.contains("pi") { return ["pi-shell", "watch-shell", "mesh-smoke"] }
        if host.contains("mac") { return ["mesh-smoke", "codex", "claude"] }
        return ["shell", "codex", "claude"]
    }
}

// MARK: - New session sheet

struct NewSessionSheet: View {
    @EnvironmentObject var store: MeshStore
    @Environment(\.dismiss) private var dismiss
    let machine: Machine
    /// Pre-filled working directory — how the file browser hands a folder over.
    var initialCwd: String? = nil

    @State private var name = ""
    @State private var command = ""
    @State private var cwd = ""
    @State private var taskAgent = "claude"
    @State private var taskText = ""
    @State private var busy = false
    @State private var browsing = false
    @State private var compact = false

    // Common launchers; "shell" means just a plain rmux session.
    private let presets = ["shell", "claude", "codex", "pi", "agy", "bun", "python3"]
    private let taskAgents = ["claude", "codex", "pi"]

    // A chosen command always wins (so `pi` or any custom CLI keeps its task); only fall
    // back to the task-agent default when no command was picked. The task goes out as
    // initialText and meshd types it into whatever we launched.
    private var launchCommand: String {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cmd.isEmpty { return cmd }
        if !taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return taskAgent }
        return ""
    }

    /// Recent working directories seen across this machine's live panes.
    private var cwdRecents: [String] {
        let agents = store.snapshot?.machines.first(where: { $0.host == machine.host })?.agents ?? []
        let paths = agents.flatMap { $0.panes ?? [] }.compactMap { $0.currentPath }
        var seen = Set<String>()
        var out: [String] = []
        for p in paths where !p.isEmpty && seen.insert(p).inserted { out.append(p) }
        return Array(out.prefix(6))
    }

    private var initialText: String? {
        let task = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        return task.isEmpty ? nil : task + "\n"
    }

    private var sessionName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let prefix = launchCommand.split(separator: " ").first.map(String.init) ?? "shell"
        return "phone-\(prefix)-\(Int(Date().timeIntervalSince1970) % 100000)"
    }

    /// Handed to the file browser so the client it builds is gated like every other.
    private var capabilities: [String]? {
        store.snapshot?.machines.first { $0.host == machine.host }?.capabilities
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session name") {
                    TextField("e.g. build-watch", text: $name.shellSafe)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Launch") {
                    Picker("Command", selection: $command) {
                        ForEach(presets, id: \.self) { p in
                            Text(p).tag(p == "shell" ? "" : p)
                        }
                    }
                    TextField("or custom command", text: $command.shellSafe)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        TextField("Working directory (optional)", text: $cwd.shellSafe)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("Browse…") { browsing = true }
                            .buttonStyle(.borderless)
                            .font(.callout)
                    }
                    if !cwdRecents.isEmpty {
                        FlowButtons(items: cwdRecents) { cwd = $0 }
                    }
                    // 80×24 is what a phone-created session should be when you intend to
                    // read it back on a phone or a watch: meshd's default PTY is sized
                    // for a desktop, and a TUI laid out for 200 columns wraps into
                    // nonsense at 21. Old daemons ignore cols/rows, so this is a
                    // best-effort request rather than a promise.
                    Toggle("Compact (80×24)", isOn: $compact)
                }
                Section("Task") {
                    Picker("Agent", selection: $taskAgent) {
                        ForEach(taskAgents, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Describe the task", text: $taskText.shellSafe, axis: .vertical)
                        .lineLimit(2...5)
                        .autocorrectionDisabled()
                    if !taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("\(launchCommand) + type task")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New on \(machine.host)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(busy)
                }
            }
            .onAppear {
                if cwd.isEmpty, let initialCwd, !initialCwd.isEmpty { cwd = initialCwd }
            }
            .sheet(isPresented: $browsing) {
                NavigationStack {
                    FileBrowserView(machine: machine, capabilities: capabilities) { picked in
                        cwd = picked
                    }
                }
            }
        }
    }

    private func create() async {
        busy = true
        defer { busy = false }
        await store.newSession(on: machine,
                               name: sessionName,
                               cmd: launchCommand,
                               cwd: cwd.trimmingCharacters(in: .whitespacesAndNewlines),
                               initialText: initialText,
                               cols: compact ? 80 : nil,
                               rows: compact ? 24 : nil)
        dismiss()
    }
}

// MARK: - Session peek (read-first, type only on intent)

/// Clean mobile control surface for one rmux session. The default state is read-only:
/// show the latest output and high-signal controls, then open the full terminal only
/// when Arya explicitly taps "Open terminal".
private struct SessionPeekScreen: View {
    @EnvironmentObject var store: MeshStore
    @Environment(\.dismiss) private var dismiss
    let machine: Machine
    let session: Agent

    @State private var output: [String] = []
    @State private var panes: [Pane] = []
    @State private var selectedPane: String?
    @State private var composeText = ""
    @State private var phraseText = ""
    @State private var showingCompose = false
    @State private var showingPhrase = false
    @State private var loading = false
    @State private var lastUpdated: Date?
    /// The last poll came back with nothing at all. Distinct from "no output": one is
    /// a quiet session, the other is a machine that stopped answering, and a screen
    /// that shows the same thing for both is the reason "updated 14:02" used to be a
    /// lie told every two seconds.
    @State private var unreachable = false
    @State private var openingLink: LinkTarget?
    /// Links the session printed — a dev server, a PR, an auth callback. Computed once
    /// per poll rather than per body pass: scanning is cheap, but not once a scroll.
    @State private var links: [URL] = []

    /// The store's constructor, never a bare `MeshClient(machine:)`: one built without
    /// capabilities silently switches every 0.5.0 feature off.
    private var client: MeshClient { store.client(for: machine) }

    private var visibleLines: [String] {
        // Keep interior blank lines so TUI output (tables, code, agent panes) stays
        // vertically aligned; only trim empty lines at the top/bottom of the window.
        var lines = Array(output.suffix(32))
        while let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.removeFirst() }
        while let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.removeLast() }
        return lines
    }

    private var activePane: Pane? {
        guard let selectedPane else { return panes.first(where: { $0.active }) }
        return panes.first { $0.paneId == selectedPane }
    }

    private var state: SessionState { sessionState(lines: output, attached: session.attached) }

    private var sessionKind: String {
        session.isCmux ? "cmux" : "\(session.windows) pane\(session.windows == 1 ? "" : "s")"
    }

    private var continueBlocked: Bool {
        guard let providerId = LimitHelpers.providerId(for: session.agentType),
              let provider = store.snapshot?.usage?.providers.first(where: { $0.id.lowercased() == providerId }) else { return false }
        if let sessionLimit = provider.limits.first(where: { LimitHelpers.isSessionLimit(label: $0.label) }) {
            return LimitHelpers.isBlocked(sessionLimit)
        }
        return false
    }

    private func stateColor(_ s: SessionState) -> Color {
        switch s {
        case .waiting: return .orange
        case .running: return .blue
        case .error:   return .red
        case .idle, .unknown: return .secondary
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                paneCard
                outputCard
                controlsCard
                presetsCard
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { Task { await refresh() } } label: {
                Image(systemName: loading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
        }
        .task(id: session.name) {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .sheet(isPresented: $showingCompose) { composeSheet }
        .sheet(isPresented: $showingPhrase) { phraseSheet }
        .sheet(item: $openingLink) { target in SafariView(url: target.url) }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: session.attached ? "dot.radiowaves.left.and.right" : "terminal.fill")
                    .foregroundStyle(session.attached ? .green : .accentColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.displayName)
                        .font(.title2.bold())
                        .lineLimit(1)
                    Text("\(terminalShortName(machine.host)) · \(session.agentType ?? "shell") · \(sessionKind)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                StatPill(label: "CPU", value: session.cpuPct.map { String(format: "%.0f%%", $0) } ?? "—")
                StatPill(label: "Mem", value: session.memLabel ?? "—")
                StatPill(label: "State", value: state.label, tone: stateColor(state))
            }
            if unreachable {
                Label(lastUpdated == nil
                      ? "\(machine.host) isn't answering — nothing has loaded yet"
                      : "\(machine.host) stopped answering · showing the last output",
                      systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let lastUpdated {
                Text("updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if continueBlocked,
               let providerId = LimitHelpers.providerId(for: session.agentType),
               let limit = store.snapshot?.usage?.providers
                .first(where: { $0.id.lowercased() == providerId })?
                .limits.first(where: { LimitHelpers.isSessionLimit(label: $0.label) }),
               let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) {
                Label("Session limit · \(countdown)", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var paneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(session.isCmux ? "Surface" : "Pane", systemImage: "rectangle.split.2x1")
                    .font(.headline)
                Spacer()
                Text(activePane?.label ?? "session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if panes.isEmpty {
                Text("No pane list yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let path = activePane?.currentPath, !path.isEmpty {
                    Label(path, systemImage: "folder")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                FlowButtons(items: panes.map(\.label)) { label in
                    guard let pane = panes.first(where: { $0.label == label }) else { return }
                    selectedPane = pane.paneId
                    Task { await refresh() }
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Latest output", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            Group {
                if visibleLines.isEmpty {
                    Text("No output yet. Tap refresh or open the terminal.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(visibleLines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
            if !links.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(links, id: \.absoluteString) { link in
                            Button {
                                openingLink = LinkTarget(url: link)
                            } label: {
                                Label(link.host ?? link.absoluteString, systemImage: "safari")
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var controlsCard: some View {
        VStack(spacing: 10) {
            NavigationLink {
                BridgeTerminalScreen(machine: machine, session: session.name, initialPane: selectedPane)
            } label: {
                Label("Open terminal", systemImage: "terminal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isCmux)
            // meshd's own remote desktop, opened knowing which session you came from —
            // which is what lets its paste go into this pane instead of into whatever
            // the Mac happens to have focused. Needs no VNC server installed anywhere.
            NavigationLink {
                RemoteScreenView(machine: machine, session: session.name, pane: selectedPane)
            } label: {
                Label("Control screen", systemImage: "cursorarrow.rays")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            // Watch a computer-use/browser agent live, then Stop/Reply on this same card.
            NavigationLink {
                RemoteWebScreen(title: "\(machine.host) screen", urlString: machine.resolvedVNC)
            } label: {
                Label("Watch screen (VNC)", systemImage: "display")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            HStack {
                Button { showingCompose = true } label: { Label("Reply", systemImage: "square.and.pencil") }
                Button { showingPhrase = true } label: { Label("Command", systemImage: "waveform") }
                // Straight into this pane, as one bracketed paste where the daemon
                // supports it. Typing a multi-line block as keystrokes makes a TUI
                // submit on every newline, which is how a pasted prompt becomes eight
                // half-finished ones.
                Button { Task { await pasteIntoPane() } } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .disabled(!UIPasteboard.general.hasStrings)
                if !session.isCmux {
                    Button { Task { await newPane() } } label: { Label("New pane", systemImage: "rectangle.split.2x1") }
                }
                if activePane != nil && !session.isCmux {
                    Button(role: .destructive) { Task { await killPane() } } label: { Label("Kill pane", systemImage: "rectangle.split.1x2") }
                }
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            HStack {
                Button { Task { await send(key: "enter") } } label: { Label("Enter", systemImage: "return") }
                Button(role: .destructive) { Task { await send(key: "ctrl-c") } } label: { Label("Stop", systemImage: "xmark.octagon") }
                Button { Task { await send(key: "up") } } label: { Label("Up", systemImage: "arrow.up") }
                Button { Task { await send(key: "down") } } label: { Label("Down", systemImage: "arrow.down") }
                Button { Task { await send(key: "left") } } label: { Label("Left", systemImage: "arrow.left") }
                Button { Task { await send(key: "right") } } label: { Label("Right", systemImage: "arrow.right") }
                Button { Task { await send(key: "tab") } } label: { Label("Tab", systemImage: "arrow.right.to.line") }
                Button { Task { await send(key: "escape") } } label: { Label("Esc", systemImage: "escape") }
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            // rmux supports the full key set; cmux surfaces only take the row above.
            if !session.isCmux {
                HStack {
                    Button { Task { await send(key: "page-up") } } label: { Label("Page up", systemImage: "arrow.up.to.line") }
                    Button { Task { await send(key: "page-down") } } label: { Label("Page down", systemImage: "arrow.down.to.line") }
                    Button { Task { await send(key: "home") } } label: { Label("Home", systemImage: "arrow.up.left") }
                    Button { Task { await send(key: "end") } } label: { Label("End", systemImage: "arrow.down.right") }
                    Button { Task { await send(key: "ctrl-d") } } label: { Label("Ctrl-D", systemImage: "d.square") }
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
            }
            if !session.isCmux {
                Button(role: .destructive) {
                    Task {
                        await store.kill(on: machine, name: session.name)
                        dismiss()
                    }
                } label: {
                    Label("Kill session", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick send")
                .font(.headline)
            FlowButtons(items: store.quickCommands, isDisabled: { continueBlocked && LimitHelpers.isContinueCommand($0) }) { cmd in
                Task { await send(text: cmd + "\n") }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var composeSheet: some View {
        NavigationStack {
            Form {
                Section("Send to \(session.displayName)") {
                    TextField("Type, paste, or dictate a command", text: $composeText.shellSafe, axis: .vertical)
                        .lineLimit(3...8)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingCompose = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task {
                            await send(text: composeText + "\n")
                            composeText = ""
                            showingCompose = false
                        }
                    }
                    .disabled(composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var phraseSheet: some View {
        NavigationStack {
            Form {
                Section("Say what you want") {
                    TextField("list files, go to Projects, start codex", text: $phraseText.shellSafe, axis: .vertical)
                        .lineLimit(2...5)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text(shellCommand(from: phraseText).isEmpty ? " " : shellCommand(from: phraseText))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Section("Examples") {
                    Button("list files") { phraseText = "list files" }
                    Button("where am i") { phraseText = "where am i" }
                    Button("git status") { phraseText = "git status" }
                    Button("start codex") { phraseText = "start codex" }
                    Button("check mesh") { phraseText = "check mesh" }
                }
            }
            .navigationTitle("Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingPhrase = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        let command = shellCommand(from: phraseText)
                        Task {
                            await send(text: command + "\n")
                            phraseText = ""
                            showingPhrase = false
                        }
                    }
                    .disabled(shellCommand(from: phraseText).isEmpty)
                }
            }
        }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        // Hoisted: the two concurrent calls then capture plain values instead of the
        // view (and its environment) across a task boundary.
        let mesh = client
        let name = session.name
        let pane = selectedPane
        async let out = try? mesh.output(agent: name, lines: 120, pane: pane)
        async let paneList = try? mesh.panes(agent: name)
        let fetchedOutput = await out
        let fetchedPanes = await paneList
        if let fetchedOutput {
            output = fetchedOutput.lines
            // Scanned off the fetched lines rather than off `visibleLines`, so this
            // never depends on when a @State write becomes readable again.
            links = detectedLinks(in: Array(fetchedOutput.lines.suffix(32)))
        }
        if let fetchedPanes {
            panes = fetchedPanes
            if selectedPane == nil {
                selectedPane = fetchedPanes.first(where: { $0.active })?.paneId ?? fetchedPanes.first?.paneId
            }
        }
        // Only real data moves the clock. Stamping `Date()` unconditionally meant a
        // machine that had been unreachable for an hour still reported itself updated
        // two seconds ago — the timestamp described the poll, not the output.
        if fetchedOutput != nil || fetchedPanes != nil {
            lastUpdated = Date()
            unreachable = false
        } else {
            unreachable = true
        }
    }

    private func send(text: String? = nil, key: String? = nil) async {
        try? await client.send(agent: session.name, text: text, key: key, pane: selectedPane)
        try? await Task.sleep(for: .milliseconds(350))
        await refresh()
    }

    /// Paste the phone's clipboard into the selected pane. `paste: true` only reaches
    /// the wire on a daemon that advertised "paste"; older ones get today's typed-keys
    /// behavior from the same call, so there is nothing to branch on here.
    private func pasteIntoPane() async {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        try? await client.send(agent: session.name, text: text, pane: selectedPane, paste: true)
        try? await Task.sleep(for: .milliseconds(350))
        await refresh()
    }

    private func newPane() async {
        try? await client.newPane(agent: session.name)
        try? await Task.sleep(for: .milliseconds(350))
        selectedPane = nil
        await refresh()
    }

    private func killPane() async {
        guard let pane = activePane else { return }
        try? await client.killPane(agent: session.name, paneId: pane.paneId)
        try? await Task.sleep(for: .milliseconds(350))
        selectedPane = nil
        await refresh()
    }
}

private func terminalShortName(_ host: String) -> String {
    host.replacingOccurrences(of: "arya-", with: "").replacingOccurrences(of: "agents", with: "")
}

private struct FlowButtons: View {
    let items: [String]
    var isDisabled: (String) -> Bool = { _ in false }
    let action: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button(item) { action(item) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isDisabled(item))
                }
            }
        }
    }
}

// MARK: - Terminal screen (WKWebView over the bridge)

private struct BridgeTerminalScreen: View {
    @EnvironmentObject var store: MeshStore
    let machine: Machine
    let session: String
    let initialPane: String?

    @State private var panes: [Pane] = []
    @State private var selectedPane: String?   // nil = whole session (default)
    @State private var phase: WebLoadPhase = .loading
    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            if panes.count > 1 {
                paneSwitcher
            }
            if let url = machine.terminalURL(session: session, pane: selectedPane) {
                ZStack {
                    BridgeWebView(url: url, reloadToken: reloadToken, phase: $phase)
                        .ignoresSafeArea(edges: .bottom)
                    webStatus(url: url)
                }
            } else {
                ContentUnavailableView("No bridge", systemImage: "wifi.exclamationmark")
            }
        }
        .navigationTitle(session)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPanes() }
        // Watching an agent work is a screen you look at without touching, so the auto
        // lock dims it mid-run. Released on disappear, never at app scope: a phone that
        // never sleeps again is a worse bug than the dim.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// A WKWebView that cannot reach its host renders a blank black rectangle — which,
    /// on a terminal page, is indistinguishable from a terminal that has nothing to say.
    /// This is the difference between the two.
    @ViewBuilder
    private func webStatus(url: URL) -> some View {
        switch phase {
        case .ready:
            EmptyView()
        case .loading:
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Connecting to \(machine.host)'s bridge")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .allowsHitTesting(false)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Can't reach the terminal bridge")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                Text(url.absoluteString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Button {
                    phase = .loading
                    reloadToken += 1
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        }
    }

    private var paneSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(panes) { pane in
                    Button {
                        selectedPane = pane.paneId
                    } label: {
                        Text(pane.label)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedPane == pane.paneId ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundStyle(selectedPane == pane.paneId ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.black)
    }

    private func loadPanes() async {
        do {
            let fetched = try await store.client(for: machine).panes(agent: session)
            panes = fetched
            // Default to the active pane so the chip selection matches the bridge's view.
            if selectedPane == nil { selectedPane = initialPane ?? fetched.first(where: { $0.active })?.paneId }
        } catch {
            panes = []
        }
    }
}

/// What a hosted page is doing. Reported by the navigation delegate, because a
/// `WKWebView` tells nobody anything unless you ask it to.
enum WebLoadPhase {
    case loading
    case ready
    case failed(String)
}

/// WKWebView wrapper. The bridge page (xterm + keybar + splits) handles all
/// touch input, scroll/select/copy, and the WebSocket stream itself.
///
/// The delegate exists because the failure looks like success: a bridge that is down,
/// a tailnet that dropped, a wrong port — every one of them paints the same black
/// rectangle a working terminal at a fresh prompt does. `phase` carries the answer back
/// out so the screen above can say which it is and offer a retry.
private struct BridgeWebView: UIViewRepresentable {
    let url: URL
    /// Bumped by the retry button. `url` alone cannot express "same page, try again".
    var reloadToken: Int
    @Binding var phase: WebLoadPhase

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.bounces = false
        web.navigationDelegate = context.coordinator
        context.coordinator.requested = url
        context.coordinator.token = reloadToken
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.requested != url || context.coordinator.token != reloadToken else { return }
        context.coordinator.requested = url
        context.coordinator.token = reloadToken
        web.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: BridgeWebView
        /// What we last asked for, so `updateUIView` reloads on a real change rather
        /// than on every layout pass (`web.url` is nil until the first load lands).
        var requested: URL?
        var token = -1

        init(_ parent: BridgeWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.phase = .loading
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.phase = .ready
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            // -999 is "a newer load replaced this one", which every retry produces and
            // which is not a failure anybody wants to read about.
            let ns = error as NSError
            guard !(ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled) else { return }
            parent.phase = .failed(ns.localizedDescription)
        }
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    var tone: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(tone)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

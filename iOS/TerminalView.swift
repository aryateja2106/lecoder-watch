import SwiftUI

// MARK: - Terminal tab

/// First-class mesh terminal on the phone. Uses meshd's existing output/send
/// endpoints, so it does not need a separate web terminal bridge.
struct TerminalTab: View {
    @EnvironmentObject var store: MeshStore
    @State private var creatingOn: Machine?

    private var snaps: [MachineSnapshot] { store.snapshot?.machines ?? [] }

    private func machine(for host: String) -> Machine? {
        store.machines.first(where: { $0.host == host })
    }

    var body: some View {
        NavigationStack {
            List {
                if snaps.isEmpty {
                    ContentUnavailableView(
                        "No machines",
                        systemImage: "terminal",
                        description: Text("Refresh after meshd is running.")
                    )
                }
                ForEach(snaps) { snap in
                    if let m = machine(for: snap.host) {
                        Section {
                            ForEach(snap.agents) { agent in
                                NavigationLink {
                                    AgentTerminalScreen(machine: m, session: agent.name)
                                } label: {
                                    HStack {
                                        Image(systemName: "terminal.fill")
                                        VStack(alignment: .leading) {
                                            Text(agent.name)
                                            Text(agent.agentType ?? "shell")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if agent.attached {
                                            Image(systemName: "dot.radiowaves.left.and.right")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                            }
                            if snap.agents.isEmpty {
                                Text("no sessions").foregroundStyle(.secondary)
                            }
                            Button {
                                creatingOn = m
                            } label: {
                                Label("New session", systemImage: "plus.circle")
                            }
                        } header: {
                            Text(snap.host)
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
        }
    }
}

// MARK: - New session sheet

private struct NewSessionSheet: View {
    @EnvironmentObject var store: MeshStore
    @Environment(\.dismiss) private var dismiss
    let machine: Machine

    @State private var name = ""
    @State private var command = ""
    @State private var busy = false

    // Common launchers; "shell" means just a plain rmux session.
    private let presets = ["shell", "claude", "codex", "agy", "bun", "python3"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Session name") {
                    TextField("e.g. build-watch", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Launch") {
                    Picker("Command", selection: $command) {
                        ForEach(presets, id: \.self) { p in
                            Text(p).tag(p == "shell" ? "" : p)
                        }
                    }
                    TextField("or custom command", text: $command)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("New on \(machine.host)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        busy = true
                        Task {
                            await store.newSession(on: machine, name: name, cmd: command)
                            busy = false
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
            }
        }
    }
}

// MARK: - Terminal screen

private struct AgentTerminalScreen: View {
    let machine: Machine
    let session: String

    @State private var panes: [Pane] = []
    @State private var selectedPane: String?   // nil = whole session (default)
    @State private var lines: [String] = []
    @State private var command = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var commandFocused: Bool

    private let presets = ["ls", "pwd", "git status", "clear"]

    var body: some View {
        VStack(spacing: 0) {
            if panes.count > 1 {
                paneSwitcher
            }
            outputView
            Divider()
            presetRow
            inputRow
        }
        .background(Color.black)
        .navigationTitle(session)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPanes() }
        .task(id: selectedPane) { await pollOutput() }
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

    private var outputView: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                Text(displayText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(lines.isEmpty ? Color.secondary : Color.green)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
                Color.clear.frame(height: 1).id("bottom")
            }
            .onChange(of: lines) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var displayText: String {
        if !lines.isEmpty { return lines.joined(separator: "\n") }
        if let error { return error }
        return "waiting for output"
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    Button(preset) { send(text: preset + "\n") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button { send(key: "up") } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(role: .destructive) { send(key: "ctrl-c") } label: { Image(systemName: "xmark.octagon") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("command", text: $command)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($commandFocused)
                .onSubmit(sendCommand)
            Button(action: sendCommand) {
                Image(systemName: busy ? "hourglass" : "paperplane.fill")
            }
            .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
        }
        .padding(10)
        .background(.regularMaterial)
    }

    private func loadPanes() async {
        do {
            let fetched = try await MeshClient(machine: machine).panes(agent: session)
            panes = fetched
            // Default to the active pane so the chip selection matches the bridge's view.
            if selectedPane == nil { selectedPane = fetched.first(where: { $0.active })?.paneId }
        } catch {
            panes = []
        }
    }

    private func pollOutput() async {
        while !Task.isCancelled {
            await loadOutput()
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    private func loadOutput() async {
        do {
            let out = try await MeshClient(machine: machine).output(agent: session, lines: 160, pane: selectedPane)
            lines = out.lines
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = "output unavailable"
        }
    }

    private func sendCommand() {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        command = ""
        send(text: text + "\n")
    }

    private func send(text: String? = nil, key: String? = nil) {
        busy = true
        Task {
            do {
                try await MeshClient(machine: machine).send(agent: session, text: text, key: key, pane: selectedPane)
                await loadOutput()
            } catch {
                self.error = "send failed"
            }
            busy = false
        }
    }
}

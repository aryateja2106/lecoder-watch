import SwiftUI
import WebKit

// MARK: - Terminal tab

/// First-class rmux terminal on the phone. Lists every machine that has a bridge
/// deployed, shows its live sessions, and opens a real interactive terminal
/// (the proven rmux-bridge xterm) in a WKWebView. "+" creates a new session.
struct TerminalTab: View {
    @EnvironmentObject var store: MeshStore
    @State private var creatingOn: Machine?

    private var bridged: [MachineSnapshot] {
        let snaps = store.snapshot?.machines ?? []
        return snaps.filter { snap in
            store.machines.first(where: { $0.host == snap.host })?.resolvedBridge != nil
        }
    }

    private func machine(for host: String) -> Machine? {
        store.machines.first(where: { $0.host == host })
    }

    var body: some View {
        NavigationStack {
            List {
                if bridged.isEmpty {
                    ContentUnavailableView(
                        "No terminal bridge",
                        systemImage: "terminal",
                        description: Text("Run rmux-bridge on a machine to open live terminals here.")
                    )
                }
                ForEach(bridged) { snap in
                    if let m = machine(for: snap.host) {
                        Section {
                            ForEach(snap.agents) { agent in
                                NavigationLink {
                                    BridgeTerminalScreen(machine: m, session: agent.name)
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

// MARK: - Terminal screen (WKWebView over the bridge)

private struct BridgeTerminalScreen: View {
    let machine: Machine
    let session: String

    @State private var panes: [Pane] = []
    @State private var selectedPane: String?   // nil = whole session (default)

    var body: some View {
        VStack(spacing: 0) {
            if panes.count > 1 {
                paneSwitcher
            }
            if let url = machine.terminalURL(session: session, pane: selectedPane) {
                BridgeWebView(url: url)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("No bridge", systemImage: "wifi.exclamationmark")
            }
        }
        .navigationTitle(session)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPanes() }
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
            let fetched = try await MeshClient(machine: machine).panes(agent: session)
            panes = fetched
            // Default to the active pane so the chip selection matches the bridge's view.
            if selectedPane == nil { selectedPane = fetched.first(where: { $0.active })?.paneId }
        } catch {
            panes = []
        }
    }
}

/// WKWebView wrapper. The bridge page (xterm + keybar + splits) handles all
/// touch input, scroll/select/copy, and the WebSocket stream itself.
///
/// BRIDGE CHANGE NEEDED (rmux-bridge, owned by another agent): the bridge today
/// reads only `?session=`. To honor pane focus, after reading the session it must
/// also read `pane` and pass it to its rmux target, e.g. add one line:
///   const pane = new URL(req.url, "http://x").searchParams.get("pane");
/// then target `pane ?? session` when attaching/capturing (rmux `-t <pane>`).
private struct BridgeWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.bounces = false
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if web.url != url { web.load(URLRequest(url: url)) }
    }
}

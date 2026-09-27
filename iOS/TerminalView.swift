// TerminalView.swift — the Terminal tab: session list, the session screen (chat or the native terminal), New Session sheet, and the built-apps screen.
import SwiftUI
import UIKit

// MARK: - Terminal tab

/// The Terminal tab: every machine with its live sessions; a row opens the session
/// screen (chat, or the native terminal over the pty stream). "+" creates a new session.
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
                                            Text([agent.isMuxGuest ? agent.kindLabel : nil, agent.agentType ?? "shell", agent.memLabel].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if agent.status == "waiting" {
                                            Label("needs you", systemImage: "hand.raised.fill")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        } else if agent.status == "error" {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.red)
                                        } else if agent.attached {
                                            Image(systemName: "dot.radiowaves.left.and.right")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if !agent.isMuxGuest {
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
                                // meshd 0.6+ ("apps"): an agent on this machine can
                                // publish a PWA or build a native app — this is where
                                // it shows up outside of whatever chat card built it.
                                if snap.capabilities?.contains("apps") == true {
                                    NavigationLink {
                                        MeshAppsScreen(machine: m)
                                    } label: {
                                        Label("Apps", systemImage: "square.grid.2x2")
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .disabled(!terminalReady(snap))
                                }
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
                NavigationLink {
                    ChatSearchView()
                } label: {
                    Label("Search chats", systemImage: "magnifyingglass")
                }
                MonitorBell()
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

private struct MeshAppsScreen: View {
    @EnvironmentObject var store: MeshStore
    let machine: Machine

    @State private var apps: [MeshApp] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var installMessage: String?

    var body: some View {
        List {
            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(.orange)
            } else if apps.isEmpty && !loading {
                ContentUnavailableView(
                    "No apps yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Ask an agent to build one — a native app or a web app — and it appears here.")
                )
            }
            ForEach(apps) { app in
                MeshAppRow(app: app, host: machine.host, install: { await install(app) })
            }
            if let installMessage {
                Text(installMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Apps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if loading { ProgressView().controlSize(.small) }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            apps = try await store.client(for: machine).meshApps()
            loadError = nil
        } catch {
            loadError = "Couldn't reach \(machine.host)."
        }
    }

    private func install(_ app: MeshApp) async -> Bool {
        installMessage = nil
        let result = await MeshAppRow.install(app, on: machine, via: store)
        installMessage = result.message
        return result.ok
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
    /// Set when `create()` fails. The sheet used to dismiss unconditionally on tap,
    /// which made a failed launch look identical to a successful one — this keeps the
    /// form on screen with the reason and a way to try again.
    @State private var errorMessage: String?

    // MARK: - Resume (meshd 0.6+, capability "handoff")

    /// Conversations kept for the typed working directory. Refetched 500ms after
    /// `cwd` settles on an absolute path — see the `onChange` below — so a directory
    /// typed character by character doesn't fire a request per keystroke.
    @State private var resumableItems: [ResumableItem] = []
    @State private var resumableTask: Task<Void, Never>?

    @State private var report: DoctorReport?

    // Common launchers; "shell" means just a plain rmux session.
    private var presets: [String] {
        let list = report?.launchable ?? ["shell", "claude", "codex", "pi", "agy"]
        return list.filter { $0 != "bun" && $0 != "python3" }
    }
    private var taskAgents: [String] {
        let list = report?.launchable ?? ["claude", "codex", "pi"]
        return list.filter { $0 != "shell" && $0 != "bun" && $0 != "python3" }
    }

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
                if let errorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Button("Retry") { Task { await create() } }
                                .buttonStyle(.bordered)
                                .disabled(busy)
                        }
                    }
                }
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
                if !resumableItems.isEmpty {
                    Section("Resume") {
                        ForEach(resumableItems) { item in
                            Button {
                                Task { await resume(item) }
                            } label: {
                                Text("\(kindLabel(item.kind)) · \(item.title.isEmpty ? "(untitled)" : item.title) · \(relativeTime(item.updated))")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Task") {
                    Picker("Agent", selection: $taskAgent) {
                        ForEach(taskAgents, id: \.self) { Text($0).tag($0) }
                    }
                    Text("on \(machine.host)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Button {
                        Task { await create() }
                    } label: {
                        if busy {
                            HStack(spacing: 4) {
                                ProgressView()
                                Text("Starting session…")
                            }
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(busy)
                }
            }
            .onAppear {
                if cwd.isEmpty, let initialCwd, !initialCwd.isEmpty { cwd = initialCwd }
                Task { report = try? await store.client(for: machine).doctor() }
            }
            .onChange(of: cwd) { _, newValue in
                resumableTask?.cancel()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("/") else {
                    resumableItems = []
                    return
                }
                resumableTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    let items = (try? await store.client(for: machine).resumable(cwd: trimmed).items) ?? []
                    guard !Task.isCancelled else { return }
                    resumableItems = items
                }
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
        errorMessage = nil
        let ok = await store.newSession(on: machine,
                               name: sessionName,
                               cmd: launchCommand,
                               cwd: cwd.trimmingCharacters(in: .whitespacesAndNewlines),
                               initialText: initialText,
                               cols: compact ? 80 : nil,
                               rows: compact ? 24 : nil)
        busy = false
        if ok {
            dismiss()
        } else {
            // `store.fail(...)` on the failure path just set this; surfaced here so the
            // sheet says exactly what MeshStore knows, not a generic "something failed".
            errorMessage = store.lastError?.message ?? "Couldn't start the session."
        }
    }

    private func kindLabel(_ kind: String) -> String {
        switch kind {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "cursor": return "Cursor"
        default: return kind.capitalized
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeTime(_ iso: String) -> String {
        guard let date = parseISO(iso) else { return "" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// A tapped Resume row launches through the same path as a manual Create: set
    /// what it would have set by hand, then call it.
    private func resume(_ item: ResumableItem) async {
        command = item.cmd
        name = "resume-\(item.kind)-\(item.id.prefix(6))"
        await create()
    }
}

// MARK: - Session peek (read-first, type only on intent)

/// Clean mobile control surface for one rmux session. The default state is read-only:
/// show the latest output and high-signal controls, then open the full terminal only
/// when Arya explicitly taps "Open terminal".
/// Internal, not private: chat search pushes it from its own detail screen.
struct SessionPeekScreen: View {
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
    /// Why the last poll came back with nothing, told apart. One `unreachable` boolean
    /// used to cover all of these, which printed "HOST isn't answering" over a machine
    /// that was answering fine — it had answered 404, because the session was gone.
    /// A stale Live Activity tap lands here constantly; the sentence must be true.
    enum PeekFailure: Equatable {
        case none
        /// Transport-level nothing: the machine did not answer at all.
        case unreachable
        /// The machine answered 404: the session/pane no longer exists.
        case sessionGone
        /// The machine answered 401/403: the token is bad — "pair again" territory.
        case tokenRejected
    }
    @State private var peekFailure: PeekFailure = .none
    private var unreachable: Bool { peekFailure == .unreachable }
    /// Why the last keystroke did not land, in the daemon's own words. Cleared by the
    /// next send that succeeds, so it describes the present and not a solved problem.
    @State private var inputRefusal: String?
    /// When the user last drove this session (key, text, paste). The poll loop reads
    /// it to decide between the 500ms interactive cadence and the 2s ambient one.
    @State private var lastInteraction = Date.distantPast
    @State private var pushingControl = false
    @State private var pushingVNC = false

    // MARK: - Hand-off (meshd 0.6+, capability "handoff")

    /// Installed CLIs this session can be handed to. Empty hides the toolbar menu —
    /// either the daemon lacks the capability or nothing is installed there.
    @State private var handoffTargets: [String] = []
    @State private var handoffInFlight = false
    @State private var handoffResultMessage: String?
    /// Set the moment a menu row is tapped; the confirmation alert reads it and
    /// clears it on either Cancel or Hand off.
    @State private var confirmingHandoffTo: String?

    private var handoffConfirmPresented: Binding<Bool> {
        Binding(get: { confirmingHandoffTo != nil }, set: { if !$0 { confirmingHandoffTo = nil } })
    }

    enum ViewMode: String, CaseIterable {
        case chat = "Chat"
        case terminal = "Terminal"
    }
    @State private var viewMode: ViewMode = .chat
    /// meshd 0.6+ ("chat"): the structured transcript AgentChatView renders. Owned
    /// here rather than by AgentChatView itself so both view modes share the one
    /// adaptive poll loop below instead of each running their own.
    @State private var chatMessages: [ChatMessage] = []
    @State private var chatCursor: String?
    @State private var chatSource: String = ""

    /// The store's constructor, never a bare `MeshClient(machine:)`: one built without
    /// capabilities silently switches every 0.5.0 feature off.
    private var client: MeshClient { store.client(for: machine) }

    private var activePane: Pane? {
        guard let selectedPane else { return panes.first(where: { $0.active }) }
        return panes.first { $0.paneId == selectedPane }
    }

    private var agentDisplayName: String {
        AgentCLIKind.detect(from: session.name, agentType: session.agentType).rawValue
    }

    /// "Resets in 2h 44m" for the blocking session limit, or nil.
    private var limitResetCountdown: String? {
        guard let providerId = LimitHelpers.providerId(for: session.agentType),
              let provider = store.snapshot?.usage?.providers.first(where: { $0.id.lowercased() == providerId }),
              let limit = provider.limits.first(where: { LimitHelpers.isSessionLimit(label: $0.label) }) else { return nil }
        return LimitHelpers.resetCountdown(from: limit.resetsAtISO)
    }

    private var continueBlocked: Bool {
        guard let providerId = LimitHelpers.providerId(for: session.agentType),
              let provider = store.snapshot?.usage?.providers.first(where: { $0.id.lowercased() == providerId }) else { return false }
        if let sessionLimit = provider.limits.first(where: { LimitHelpers.isSessionLimit(label: $0.label) }) {
            return LimitHelpers.isBlocked(sessionLimit)
        }
        return false
    }

    var body: some View {
        Group {
            if viewMode == .chat {
                AgentChatView(
                    machine: machine,
                    session: session,
                    messages: chatMessages,
                    chatSource: chatSource,
                    rawLines: output,
                    // A trailing newline means "submit". Typed as a byte it is a line feed, and
                    // Claude Code's prompt takes a bare line feed as a new line INSIDE the prompt —
                    // the text sat there unsent. Enter is a key, so it is sent as one.
                    onSendText: { text in
                        Task {
                            if text.hasSuffix("\n") {
                                let body = String(text.dropLast())
                                if !body.isEmpty { await send(text: body) }
                                await send(key: "enter")
                            } else {
                                await send(text: text)
                            }
                        }
                    },
                    onSendPaste: { text in
                        Task { await send(text: text, key: "enter", paste: true) }
                    },
                    onSendKey: { key in Task { await send(key: key) } },
                    onSendKeys: { keys in Task { for key in keys { await send(key: key) } } }
                )
                .disabled(handoffInFlight)
            } else {
                // The terminal is the whole screen: SwiftTerm over the pty stream (or
                // ansi polls on an older daemon), the key bar under it. Everything the
                // old card list offered lives in the ⋯ menu now.
                NativeTerminalScreen(machine: machine, session: session, initialPane: selectedPane, embedded: true)
                    .id(selectedPane ?? "")
            }
        }
        .toolbar(viewMode == .terminal ? .hidden : .visible, for: .tabBar)
        // Watching a session is why the screen must not dim; released when this screen goes.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .navigationDestination(isPresented: $pushingControl) {
            RemoteScreenView(machine: machine, session: session.name, pane: selectedPane)
        }
        .navigationDestination(isPresented: $pushingVNC) {
            RemoteWebScreen(title: "\(machine.host) screen", urlString: machine.resolvedVNC)
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                // A refused keystroke has to say so, in the daemon's words.
                if let inputRefusal, viewMode == .chat {
                    Label("Input refused · \(inputRefusal)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                }
                if let handoffResultMessage {
                    Text(handoffResultMessage)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                }
                // The agent hit its session limit mid-task and another agent on this
                // machine has room: offer the hand-off here, where the task is, instead of
                // leaving a stuck session and a countdown. Same daemon route as the ⋯ menu —
                // HANDOFF.md is written, the new agent is told to read it.
                if continueBlocked, !handoffTargets.isEmpty, !handoffInFlight, handoffResultMessage == nil {
                    LimitHandoffBanner(agent: agentDisplayName, resetIn: limitResetCountdown, targets: handoffTargets) { target in
                        confirmingHandoffTo = target
                    }
                }
            }
        }
        .navigationTitle(session.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if panes.count > 1 {
                        Picker("Pane", selection: $selectedPane) {
                            ForEach(panes) { pane in Text(pane.label).tag(Optional(pane.paneId)) }
                        }
                    }
                    Button { pushingControl = true } label: { Label("Control screen", systemImage: "cursorarrow.rays") }
                    Button { pushingVNC = true } label: { Label("Watch screen (VNC)", systemImage: "display") }
                    Divider()
                    // Straight into this pane, as one bracketed paste where the daemon
                    // supports it: typed as keystrokes a TUI submits on every newline.
                    Button { Task { await pasteIntoPane() } } label: { Label("Paste clipboard", systemImage: "doc.on.clipboard") }
                        .disabled(!UIPasteboard.general.hasStrings)
                    if !session.isMuxGuest {
                        Button { Task { await newPane() } } label: { Label("New pane", systemImage: "rectangle.split.2x1") }
                        if activePane != nil {
                            Button(role: .destructive) { Task { await killPane() } } label: { Label("Kill pane", systemImage: "rectangle.split.1x2") }
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task { await store.kill(on: machine, name: session.name); dismiss() }
                        } label: { Label("Kill session", systemImage: "trash") }
                    }
                    Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            if !handoffTargets.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(handoffTargets, id: \.self) { target in
                            Button(target) { confirmingHandoffTo = target }
                        }
                    } label: {
                        Label("Hand off to…", systemImage: "arrow.triangle.swap")
                    }
                    .disabled(handoffInFlight)
                }
            }
        }
        .task(id: session.name) { await loadHandoffTargets() }
        .task(id: session.name) {
            // Adaptive cadence: 500ms while the user is actively driving this session
            // (a key, a paste, a reply within the last 10s), 2s otherwise, and no
            // fetches at all while the app is backgrounded. The fast lane is what makes
            // a sent keystroke's echo feel attached to the finger; the 10s decay is the
            // battery guard — reading output hands-off is a 2s activity, typing is not.
            while !Task.isCancelled {
                let parked = UIApplication.shared.applicationState == .background
                if !parked {
                    await refresh()
                    await refreshChat()
                }
                let fast = !parked && Date().timeIntervalSince(lastInteraction) < 10
                try? await Task.sleep(for: .milliseconds(fast ? 500 : 2000))
            }
        }
        .sheet(isPresented: $showingCompose) { composeSheet }
        .sheet(isPresented: $showingPhrase) { phraseSheet }
        .alert("Hand off to \(confirmingHandoffTo ?? "")?", isPresented: handoffConfirmPresented,
               presenting: confirmingHandoffTo) { target in
            Button("Cancel", role: .cancel) {}
            Button("Hand off") { Task { await performHandoff(to: target) } }
        } message: { target in
            Text("Interrupt \(agentDisplayName) and continue this task with \(target). The conversation so far is written to HANDOFF.md in the working directory.")
        }
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
        // Task.result, not `try?`: the error IS the data here. A 404 means the machine
        // answered and the session is gone; a transport error means it did not answer;
        // 401/403 means the token died. `try?` melted all three into one wrong banner.
        let outTask = Task { try await mesh.output(agent: name, lines: 120, pane: pane) }
        let panesTask = Task { try await mesh.panes(agent: name) }
        let outResult = await outTask.result
        let panesResult = await panesTask.result
        if case .success(let fetchedOutput) = outResult {
            output = fetchedOutput.lines
        }
        if case .success(let fetchedPanes) = panesResult {
            panes = fetchedPanes
            if selectedPane == nil {
                selectedPane = fetchedPanes.first(where: { $0.active })?.paneId ?? fetchedPanes.first?.paneId
            }
        }
        // Only real data moves the clock. Stamping `Date()` unconditionally meant a
        // machine that had been unreachable for an hour still reported itself updated
        // two seconds ago — the timestamp described the poll, not the output.
        switch (outResult, panesResult) {
        case (.success, _), (_, .success):
            lastUpdated = Date()
            peekFailure = .none
        case (.failure(let outError), .failure):
            peekFailure = Self.classify(outError)
        }
    }

    /// meshd 0.6+ ("chat"): poll the structured transcript alongside `refresh()`'s
    /// output/panes fetch, on the same adaptive cadence. Gated client-side on the
    /// capability string, never on version — an old daemon simply never gets asked.
    /// New messages are appended by `id` rather than replacing the list, matching the
    /// contract's "append by id; pass cursor back"; a transient poll failure leaves
    /// the transcript exactly as it was rather than blanking it.
    private func refreshChat() async {
        guard client.supports("chat") else { return }
        guard let feed = try? await client.chat(agent: session.name, since: chatCursor, limit: 200) else { return }
        chatCursor = feed.cursor
        chatSource = feed.source
        if feed.source == "output" {
            // The daemon found no real transcript either; AgentChatView falls back to
            // rendering `output` (already fetched above) as a terminal block.
            chatMessages = []
        } else {
            let known = Set(chatMessages.map(\.id))
            chatMessages.append(contentsOf: feed.messages.filter { !known.contains($0.id) })
            // Cap stored history — the daemon already caps a single poll at `limit`,
            // this caps the running total for a session left open for hours.
            if chatMessages.count > 500 { chatMessages.removeFirst(chatMessages.count - 500) }
        }
    }

    /// The output fetch's error decides the banner; the panes fetch fails the same way
    /// for the same causes and adds nothing.
    private static func classify(_ error: Error) -> PeekFailure {
        switch (error as? MeshClient.MeshError)?.statusCode {
        case 404: .sessionGone
        case 401, 403: .tokenRejected
        default: .unreachable
        }
    }

    /// A refused keystroke has to say so. `try?` here meant the daemon could answer
    /// "pane not found" and the screen would look exactly like a delivered key — the
    /// half of the dead-terminal report that no daemon fix could have reached.
    private func send(text: String? = nil, key: String? = nil, paste: Bool = false) async {
        lastInteraction = Date()
        do {
            try await client.send(agent: session.name, text: text, key: key, pane: selectedPane, paste: paste)
            inputRefusal = nil
        } catch let error as MeshClient.MeshError {
            inputRefusal = error.reason ?? "the machine refused the input"
        } catch {
            inputRefusal = "the machine could not be reached"
        }
        try? await Task.sleep(for: .milliseconds(350))
        await refresh()
    }

    /// meshd 0.6+ ("handoff"): which installed CLIs this session can be handed to.
    /// `[]` on an unsupported daemon (`resumable(agent:)` throws `.unsupported`) or
    /// one with nothing installed — either way the toolbar menu just doesn't appear.
    private func loadHandoffTargets() async {
        handoffTargets = (try? await client.resumable(agent: session.name).targets) ?? []
    }

    /// Interrupt this session and relaunch it under `target`. The daemon holds the
    /// response open for the whole sequence (two Ctrl-C, a beat, the new command), so
    /// disabling the composer for the `await` below already covers the time it takes.
    private func performHandoff(to target: String) async {
        handoffInFlight = true
        do {
            _ = try await client.handoff(agent: session.name, to: target)
            handoffResultMessage = "Handed off — \(target) is reading HANDOFF.md"
        } catch let error as MeshClient.MeshError {
            handoffResultMessage = error.reason ?? "the hand-off was refused"
        } catch {
            handoffResultMessage = "the machine could not be reached"
        }
        handoffInFlight = false
        let shown = handoffResultMessage
        Task {
            try? await Task.sleep(for: .seconds(6))
            if handoffResultMessage == shown { handoffResultMessage = nil }
        }
    }

    /// Paste the phone's clipboard into the selected pane. `paste: true` only reaches
    /// the wire on a daemon that advertised "paste"; older ones get today's typed-keys
    /// behavior from the same call, so there is nothing to branch on here.
    private func pasteIntoPane() async {
        guard let text = phoneClipboardText() else { return }
        await send(text: text, paste: true)
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

/// One clipboard boundary for both the transcript composer and raw terminal controls.
/// Empty clipboard strings are never useful input and should not enable a send path.
func phoneClipboardText() -> String? {
    guard let text = UIPasteboard.general.string, !text.isEmpty else { return nil }
    return text
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




/// "Claude's session limit is reached — continue this task with…" and one button per agent
/// installed on the machine. Shown only while the limit blocks and a target exists.
private struct LimitHandoffBanner: View {
    let agent: String
    let resetIn: String?
    let targets: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("\(agent) hit its session limit\(resetIn.map { " · resets in \($0)" } ?? ""). Continue this task with another agent?")
                    .font(.footnote)
            } icon: {
                Image(systemName: "flame.fill").foregroundStyle(.red)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(targets, id: \.self) { target in
                        Button {
                            onPick(target)
                        } label: {
                            Label(target, systemImage: "arrow.triangle.swap").font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

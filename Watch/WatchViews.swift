import SwiftUI

// MARK: - Root

struct WatchRootView: View {
    @StateObject private var store = WatchMeshStore()

    var body: some View {
        // Single root NavigationStack (watchOS forbids nested wrapped nav).
        NavigationStack {
            MachinesListView()
                .environmentObject(store)
                .navigationTitle("Mesh")
        }
        .onAppear { store.start() }
    }
}

// MARK: - Machines

struct MachinesListView: View {
    @EnvironmentObject var store: WatchMeshStore

    var body: some View {
        List {
            ForEach(activeFirst(store.snaps)) { m in
                NavigationLink {
                    SessionsView(host: m.host).environmentObject(store)
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(statusColor(m)).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shortName(m.host)).font(.headline)
                            if let auth = m.authError {
                                Text(auth).font(.caption2).foregroundStyle(.orange)
                            } else if let s = m.stats {
                                Text("CPU \(Int(s.cpuPct))% · \(Int(s.mem.pct))% mem · \(m.agents.count) sess · \(store.routeLabel(for: m.host))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else if m.reachable {
                                Text("\(m.agents.count) session\(m.agents.count == 1 ? "" : "s") · \(store.routeLabel(for: m.host))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text(store.routeLabel(for: m.host)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            NavigationLink {
                UsageView().environmentObject(store)
            } label: {
                Label("Usage", systemImage: "gauge.with.dots.needle.67percent")
            }
            NavigationLink {
                EventsView().environmentObject(store)
            } label: {
                Label("Events", systemImage: "bell")
            }
        }
        .overlay {
            if store.snaps.isEmpty {
                ProgressView("Connecting…")
            }
        }
        // ponytail: pull-to-refresh instead of a toolbar button — on watchOS a bare
        // .toolbar Button renders as a full-width top button that covered the first
        // machine and showed no managed spinner. .refreshable self-dismisses.
        .refreshable { await store.refresh() }
    }
}

private func activeFirst(_ snaps: [MachineSnapshot]) -> [MachineSnapshot] {
    snaps.sorted {
        if $0.reachable != $1.reachable { return $0.reachable && !$1.reachable }
        if $0.agents.count != $1.agents.count { return $0.agents.count > $1.agents.count }
        return $0.host < $1.host
    }
}

private func statusColor(_ snap: MachineSnapshot) -> Color {
    if snap.authError != nil { return .orange }
    return snap.reachable ? .green : .secondary
}

private func knownSessions(for host: String) -> [String] {
    let lower = host.lowercased()
    if lower.contains("pi") { return ["pi-shell", "watch-shell-67982", "mesh-smoke"] }
    if lower.contains("mac") { return ["mesh-smoke", "codex", "claude"] }
    return ["shell", "codex", "claude"]
}

struct EventsView: View {
    @EnvironmentObject var store: WatchMeshStore

    var body: some View {
        List(store.events.reversed()) { event in
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.headline).lineLimit(2)
                if let body = event.body {
                    Text(body).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
                Text([event.host, event.source].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Events")
        .overlay { if store.events.isEmpty { Text("No events").foregroundStyle(.secondary) } }
    }
}

// MARK: - Sessions on a machine

struct SessionsView: View {
    @EnvironmentObject var store: WatchMeshStore
    let host: String

    @State private var taskAgent = "claude"
    @State private var taskText = ""
    @State private var showTask = false

    private var snap: MachineSnapshot? { store.snaps.first { $0.host == host } }

    var body: some View {
        List {
            Section("Sessions (\(snap?.agents.count ?? 0))") {
                ForEach(snap?.agents ?? []) { a in
                    NavigationLink {
                        AgentLiveView(host: host, agent: a.name).environmentObject(store)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: a.attached ? "dot.radiowaves.left.and.right" : "terminal")
                                .foregroundStyle(a.attached ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(a.name)
                                Text("\(a.windows) pane\(a.windows == 1 ? "" : "s")\(a.attached ? " · live" : "") · \(store.routeLabel(for: host))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if (snap?.agents ?? []).isEmpty {
                    Text(snap?.authError != nil ? "token needed" : "no sessions").foregroundStyle(.secondary)
                }
            }
            if snap?.authError != nil {
                Section("Fix") {
                    Text("Open Mesh on iPhone and copy the install command for this machine.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Then refresh the watch.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Known") {
                ForEach(knownSessions(for: host), id: \.self) { session in
                    NavigationLink {
                        AgentLiveView(host: host, agent: session).environmentObject(store)
                    } label: {
                        Label(session, systemImage: "terminal")
                    }
                }
            }
            Section("New") {
                Button { store.newSession(host: host, cmd: nil) } label: {
                    Label("Shell", systemImage: "terminal")
                }
                Button { store.newSession(host: host, cmd: "claude") } label: {
                    Label("Claude", systemImage: "sparkles")
                }
                Button { store.newSession(host: host, cmd: "codex") } label: {
                    Label("Codex", systemImage: "curlybraces")
                }
                Button { taskAgent = "claude"; showTask = true } label: {
                    Label("Claude task", systemImage: "text.bubble")
                }
                Button { taskAgent = "codex"; showTask = true } label: {
                    Label("Codex task", systemImage: "text.badge.checkmark")
                }
            }
            .disabled(snap?.reachable != true || snap?.authError != nil)
            if let s = snap?.stats {
                Section("Machine") {
                    Text(store.routeLabel(for: host))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    GaugeRow(label: "CPU", value: s.cpuPct, text: "\(Int(s.cpuPct))%")
                    GaugeRow(label: "Mem", value: s.mem.pct, text: "\(Int(s.mem.usedMB/1024))/\(Int(s.mem.totalMB/1024))G")
                    GaugeRow(label: "Disk", value: s.disk.pct, text: "\(Int(s.disk.usedGB))/\(Int(s.disk.totalGB))G")
                }
            }
        }
        .navigationTitle(shortName(host))
        .toolbar {
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .sheet(isPresented: $showTask) { taskSheet }
    }

    private var taskSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("\(taskAgent.capitalized) task")
                    .font(.headline)
                TextField("Build/fix/check…", text: $taskText)
                    .autocorrectionDisabled()
                Button("Start") {
                    store.newTask(host: host, agent: taskAgent, task: taskText)
                    taskText = ""
                    showTask = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showTask = false } } }
        }
    }
}

// MARK: - Live agent view (see + respond)

struct AgentLiveView: View {
    @EnvironmentObject var store: WatchMeshStore
    let host: String
    let agent: String

    @State private var reply = ""
    @State private var phrase = ""
    @State private var showReply = false
    @State private var showPhrase = false
    @State private var showMore = false
    @State private var fontSize: CGFloat = 13
    @State private var selectedPane: String?

    private var currentAgent: Agent? {
        store.snaps.first { $0.host == host }?.agents.first { $0.name == agent }
    }

    private var panes: [Pane] {
        currentAgent?.panes ?? []
    }

    private var currentPane: Pane? {
        panes.first { $0.paneId == selectedPane }
            ?? panes.first { $0.active }
            ?? panes.first
    }

    private var meaningfulLines: [String] {
        store.output.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var previewLines: [String] {
        Array(meaningfulLines.suffix(8))
    }

    private var statusText: String {
        if store.sending { return "sending…" }
        if meaningfulLines.isEmpty { return "waiting for output" }
        return "live · \(meaningfulLines.count) lines"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(store.sending ? .orange : .green).frame(width: 8, height: 8)
                        Text(shortName(host)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(agent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let pane = currentPane {
                        Text(pane.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let error = store.lastError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("control") {
                HStack(spacing: 6) {
                    Button { store.send(key: "enter") } label: {
                        VStack { Image(systemName: "return"); Text("Enter").font(.caption2) }
                    }
                    Button(role: .destructive) { store.send(key: "ctrl-c") } label: {
                        VStack { Image(systemName: "xmark.octagon"); Text("Stop").font(.caption2) }
                    }
                    Button { store.send(key: "up") } label: {
                        VStack { Image(systemName: "arrow.up"); Text("Prev").font(.caption2) }
                    }
                }
                .buttonStyle(.bordered)
                Button { showReply = true } label: {
                    Label("Reply / dictate", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                Button { showPhrase = true } label: {
                    Label("Voice command", systemImage: "waveform")
                }
                .buttonStyle(.bordered)
                Button { store.newPane(host: host, agent: agent) } label: {
                    Label("New pane", systemImage: "rectangle.split.2x1")
                }
                .buttonStyle(.bordered)
                if let pane = currentPane {
                    Button(role: .destructive) {
                        store.killPane(host: host, agent: agent, pane: pane.paneId)
                        selectedPane = nil
                    } label: {
                        Label("Kill pane", systemImage: "rectangle.split.1x2")
                    }
                    .buttonStyle(.bordered)
                }
                Button(role: .destructive) { store.killSession(host: host, agent: agent) } label: {
                    Label("Kill session", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            Section("quick send") {
                ForEach(store.quickCommands, id: \.self) { command in
                    Button(command) { store.send(text: command + "\n") }
                }
            }

            if !panes.isEmpty {
                Section("pane") {
                    ForEach(panes) { pane in
                        Button {
                            selectedPane = pane.paneId
                            store.watch(host: host, agent: agent, pane: pane.paneId)
                        } label: {
                            HStack {
                                Image(systemName: pane.paneId == currentPane?.paneId ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(pane.label).lineLimit(1)
                                    if let path = pane.currentPath, !path.isEmpty {
                                        Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section("peek") {
                if previewLines.isEmpty {
                    Text("No output yet. Use Reply only when you want the keyboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(previewLines.joined(separator: "\n"))
                        .font(.system(size: fontSize, design: .monospaced))
                        .lineLimit(10)
                        .focusable(false)
                }
                Button { showMore = true } label: {
                    Label("Show more", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectDefaultPaneAndWatch() }
        .onChange(of: panes) { _, _ in
            if selectedPane == nil {
                selectDefaultPaneAndWatch()
            }
        }
        .onDisappear { store.stopWatching() }
        .sheet(isPresented: $showReply) { replySheet }
        .sheet(isPresented: $showPhrase) { phraseSheet }
        .sheet(isPresented: $showMore) { outputSheet }
    }

    private func selectDefaultPaneAndWatch() {
        if selectedPane == nil {
            selectedPane = currentPane?.paneId
        }
        store.watch(host: host, agent: agent, pane: selectedPane)
    }

    private var replySheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Send to \(agent)")
                    .font(.headline)
                    .lineLimit(1)
                TextField("Say, scribble, or type…", text: $reply)
                    .autocorrectionDisabled()
                Button("Send") {
                    if !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        store.send(text: reply + "\n")
                        reply = ""
                        showReply = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showReply = false } } }
        }
    }

    private var phraseSheet: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("Voice command")
                    .font(.headline)
                TextField("list files, go to Projects…", text: $phrase)
                    .autocorrectionDisabled()
                Text(shellCommand(from: phrase).isEmpty ? " " : shellCommand(from: phrase))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("ls") { phrase = "list files" }
                    Button("pwd") { phrase = "where am i" }
                    Button("git") { phrase = "git status" }
                    Button("mesh") { phrase = "check mesh" }
                }
                .buttonStyle(.bordered)
                Button("Send") {
                    let command = shellCommand(from: phrase)
                    if !command.isEmpty {
                        store.send(text: command + "\n")
                        phrase = ""
                        showPhrase = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(shellCommand(from: phrase).isEmpty)
            }
            .padding()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPhrase = false } } }
        }
    }

    private var outputSheet: some View {
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                Text(meaningfulLines.joined(separator: "\n"))
                    .font(.system(size: fontSize + 2, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(8)
            }
            .navigationTitle(agent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { fontSize = max(9, fontSize - 1) } label: { Image(systemName: "textformat.size.smaller") }
                    Text("\(Int(fontSize))pt").font(.caption2).monospacedDigit()
                    Button { fontSize = min(24, fontSize + 1) } label: { Image(systemName: "textformat.size.larger") }
                    Spacer()
                    Button("Done") { showMore = false }
                }
            }
        }
    }
}

// MARK: - Usage

struct UsageView: View {
    @EnvironmentObject var store: WatchMeshStore

    var body: some View {
        List(store.effectiveUsage?.providers ?? []) { p in
            Section("\(p.displayName) \(p.plan ?? "")") {
                ForEach(p.limits) { l in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(l.label).font(.caption)
                            Spacer()
                            Text(l.usedPct.map { "\(Int($0))%" } ?? "—").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let pct = l.usedPct { ProgressView(value: min(max(pct/100, 0), 1)) }
                        if let reset = resetText(l.resetsAtISO) {
                            Text(reset).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Usage")
        .overlay { if (store.effectiveUsage?.providers ?? []).isEmpty { Text("No usage data").foregroundStyle(.secondary) } }
    }
}

// MARK: - Bits

struct GaugeRow: View {
    let label: String
    let value: Double
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(label).font(.caption); Spacer(); Text(text).font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
            ProgressView(value: min(max(value/100, 0), 1))
                .tint(value > 85 ? .red : value > 60 ? .orange : .green)
        }
    }
}

func shortName(_ host: String) -> String {
    host.replacingOccurrences(of: "arya-", with: "").replacingOccurrences(of: "agents", with: "")
}

private func resetText(_ iso: String?) -> String? {
    guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return nil }
    return "resets \(date.formatted(date: .abbreviated, time: .shortened))"
}

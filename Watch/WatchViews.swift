import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
            if let glance = limitsGlance {
                Section {
                    ForEach(glance, id: \.providerId) { row in
                        HStack {
                            Image(systemName: row.blocked ? "flame.fill" : "checkmark.circle")
                                .foregroundStyle(row.blocked ? .red : .green)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title).font(.caption)
                                Text(row.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                            // Resume the pinned session straight from the glance once the
                            // limit clears — the wrist action a mirrored notification tap can't do.
                            if let pin = store.pinnedLimitSessions.first(where: { $0.providerId.lowercased() == row.providerId.lowercased() }) {
                                Spacer()
                                Button("Continue") { store.sendToPinned(pin) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .disabled(row.blocked)
                            }
                        }
                    }
                } header: {
                    Text("Limits")
                }
            }
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

    private struct LimitGlanceRow {
        var providerId: String
        var title: String
        var detail: String
        var blocked: Bool
    }

    private var limitsGlance: [LimitGlanceRow]? {
        guard let providers = store.effectiveUsage?.providers else { return nil }
        let rows = ["claude", "codex"].compactMap { id -> LimitGlanceRow? in
            guard let p = providers.first(where: { $0.id.lowercased() == id }),
                  let limit = p.limits.first(where: { LimitHelpers.isSessionLimit(label: $0.label) }) else { return nil }
            let blocked = LimitHelpers.isBlocked(limit)
            let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) ?? "—"
            let left = LimitHelpers.remainingPct(usedPct: limit.usedPct).map { "\($0)% left" } ?? "—"
            return LimitGlanceRow(providerId: id,
                                  title: "\(p.displayName) session",
                                  detail: blocked ? "Limit reached · \(countdown)" : "\(left) · \(countdown)",
                                  blocked: blocked)
        }
        return rows.isEmpty ? nil : rows
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

private func watchSessionSubtitle(_ agent: Agent, route: String) -> String {
    let kind = agent.isCmux ? "cmux" : "\(agent.windows) pane\(agent.windows == 1 ? "" : "s")"
    return "\(kind)\(agent.attached ? " · live" : "") · \(route)"
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

private struct SessionRoute: Identifiable, Hashable {
    var host: String
    var agent: String
    var id: String { "\(host):\(agent)" }
}

struct SessionsView: View {
    @EnvironmentObject var store: WatchMeshStore
    let host: String

    @State private var taskAgent = "claude"
    @State private var taskText = ""
    @State private var showTask = false
    @State private var openAgent: SessionRoute?

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
                                Text(a.displayName)
                                Text(watchSessionSubtitle(a, route: store.routeLabel(for: host)))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if (snap?.agents ?? []).isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snap?.authError != nil ? "Token needed" : "No sessions")
                        Text(emptySessionHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
            Section("Monitor") {
                NavigationLink {
                    ScreenPeekView(host: host).environmentObject(store)
                } label: {
                    Label("Screen peek", systemImage: "display")
                }
                .disabled(snap?.reachable != true || snap?.authError != nil)
                if let machine = store.machines.first(where: { $0.host == host }), supportsInput {
                    NavigationLink {
                        RemoteView(machine: machine)
                    } label: {
                        Label("Control Mac", systemImage: "cursorarrow.motionlines")
                    }
                    .disabled(snap?.reachable != true || snap?.authError != nil)
                }
            }
            Section("New") {
                Button { openNewSession(cmd: nil) } label: {
                    Label("Shell", systemImage: "terminal")
                }
                Button { openNewSession(cmd: "claude") } label: {
                    Label("Claude", systemImage: "sparkles")
                }
                Button { openNewSession(cmd: "codex") } label: {
                    Label("Codex", systemImage: "curlybraces")
                }
                Button { taskAgent = "claude"; showTask = true } label: {
                    Label("Claude task", systemImage: "text.bubble")
                }
                Button { taskAgent = "codex"; showTask = true } label: {
                    Label("Codex task", systemImage: "text.badge.checkmark")
                }
                Button { taskAgent = "pi"; showTask = true } label: {
                    Label("Pi task", systemImage: "brain")
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
        .navigationDestination(item: $openAgent) { route in
            AgentLiveView(host: route.host, agent: route.agent).environmentObject(store)
        }
        .sheet(isPresented: $showTask) { taskSheet }
    }

    /// meshd advertises "input" only on macOS hosts that ship the injector.
    private var supportsInput: Bool { snap?.capabilities?.contains("input") ?? false }

    private var emptySessionHint: String {
        if snap?.authError != nil { return "Open Mesh on iPhone, fix the token, then refresh." }
        if snap?.reachable == true { return "Start Shell, Claude, or Codex below." }
        return "Open Mesh on iPhone or refresh when the Mac is nearby."
    }

    private func openNewSession(cmd: String?, initialText: String? = nil) {
        let name = store.newSession(host: host, cmd: cmd, initialText: initialText)
        openAgent = SessionRoute(host: host, agent: name)
    }

    private var taskSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("\(taskAgent.capitalized) task")
                    .font(.headline)
                TextField("Build/fix/check…", text: $taskText)
                    .autocorrectionDisabled()
                Button("Start") {
                    if let name = store.newTask(host: host, agent: taskAgent, task: taskText) {
                        openAgent = SessionRoute(host: host, agent: name)
                    }
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
    @Environment(\.dismiss) private var dismiss
    let host: String
    let agent: String

    @State private var reply = ""
    @State private var showReply = false
    @State private var showMore = false
    @State private var confirmInterrupt = false
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

    // Terminal display source: keep interior blank lines so TUI output stays aligned;
    // trim only the empty lines at the top/bottom of the window.
    private var terminalLines: [String] {
        var lines = store.output
        while let f = lines.first, f.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.removeFirst() }
        while let l = lines.last, l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.removeLast() }
        return lines
    }

    private var previewLines: [String] {
        Array(terminalLines.suffix(8))
    }

    private var statusText: String {
        if store.sending { return "sending…" }
        if let providerId = LimitHelpers.providerId(for: currentAgent?.agentType),
           store.isProviderBlocked(providerId) {
            if let limit = sessionLimit(for: providerId),
               let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) {
                return "Limit reached · \(countdown)"
            }
            return "Limit reached · wait for reset"
        }
        if meaningfulLines.isEmpty { return "waiting for output" }
        return "\(sessionState(lines: meaningfulLines, attached: currentAgent?.attached ?? false).label) · \(meaningfulLines.count) lines"
    }

    private var continueBlocked: Bool {
        guard let providerId = LimitHelpers.providerId(for: currentAgent?.agentType) else { return false }
        return store.isProviderBlocked(providerId)
    }

    private func sessionLimit(for providerId: String) -> UsageLimit? {
        store.effectiveUsage?.providers
            .first { $0.id.lowercased() == providerId.lowercased() }?
            .limits.first { $0.label.lowercased().contains("session") }
    }

    var body: some View {
        List {
            if continueBlocked, let providerId = LimitHelpers.providerId(for: currentAgent?.agentType),
               let limit = sessionLimit(for: providerId) {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Session limit reached", systemImage: "flame.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        if let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) {
                            Text(countdown).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Continue is disabled until the limit resets.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Monitor") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(store.sending ? .orange : .green).frame(width: 8, height: 8)
                        Text("\(shortName(host)) · \(store.routeLabel(for: host))").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(currentAgent?.displayName ?? agent)
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

            Section("Actions") {
                Button { store.send(text: "continue\n") } label: {
                    Label("Continue", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(continueBlocked)
                Button { store.send(key: "enter") } label: {
                    Label("Enter", systemImage: "return")
                }
                .buttonStyle(.bordered)
                Button { showReply = true } label: {
                    Label("Reply", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) { confirmInterrupt = true } label: {
                    Label("Interrupt", systemImage: "xmark.octagon")
                }
                .buttonStyle(.bordered)
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

            Section("Output") {
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
                    Label("Open terminal", systemImage: "terminal")
                }
                .accessibilityHint("Full-screen, scrollable output with a key bar")
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Interrupt agent?", isPresented: $confirmInterrupt, titleVisibility: .visible) {
            Button("Send Ctrl-C", role: .destructive) { store.send(key: "ctrl-c") }
            Button("Kill session", role: .destructive) { store.killSession(host: host, agent: agent); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ctrl-C stops the current turn; Kill ends the whole session on \(currentAgent?.displayName ?? agent).")
        }
        .onAppear { selectDefaultPaneAndWatch() }
        .onChange(of: panes) { _, _ in
            if selectedPane == nil {
                selectDefaultPaneAndWatch()
            }
        }
        .onDisappear { store.stopWatching() }
        .sheet(isPresented: $showReply) { replySheet }
        .sheet(isPresented: $showMore) { terminalScreen }
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
                Text("Send to \(currentAgent?.displayName ?? agent)")
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

    // A genuine terminal on the wrist: full-bleed monospaced output that the Digital
    // Crown scrolls and that auto-follows the newest line, with an always-present,
    // horizontally-scrollable key bar (matching the phone accessory bar). Every icon
    // control carries a VoiceOver label.
    private var terminalScreen: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(terminalLines.isEmpty ? "waiting for output…" : terminalLines.joined(separator: "\n"))
                            .font(.system(size: fontSize, design: .monospaced))
                            .foregroundStyle(terminalLines.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Terminal output, \(terminalLines.count) lines")
                        Color.clear.frame(height: 1).id("tail")
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
                .background(Color.black)
                .onAppear { proxy.scrollTo("tail", anchor: .bottom) }
                .onChange(of: store.output) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("tail", anchor: .bottom) }
                }
            }
            .navigationTitle(currentAgent?.displayName ?? agent)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { terminalKeyBar }
        }
    }

    private var terminalKeyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                keyChip("Reply", "text.bubble") { showReply = true }
                keyChip("Enter", "return") { store.send(key: "enter") }
                keyChip("Interrupt", "xmark.octagon", role: .destructive) { store.send(key: "ctrl-c") }
                keyChip("Tab", "arrow.right.to.line") { store.send(key: "tab") }
                keyChip("Escape", "escape") { store.send(key: "escape") }
                keyChip("Up", "arrow.up") { store.send(key: "up") }
                keyChip("Down", "arrow.down") { store.send(key: "down") }
                keyChip("Smaller text", "textformat.size.smaller") { fontSize = max(9, fontSize - 1) }
                keyChip("Larger text", "textformat.size.larger") { fontSize = min(24, fontSize + 1) }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func keyChip(_ label: String, _ icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: icon).frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }
}

// MARK: - Screen peek

struct ScreenPeekView: View {
    @EnvironmentObject var store: WatchMeshStore
    let host: String

    private var imageData: Data? {
        store.screenHost == host ? store.screenJPEGData : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(shortName(host)) · \(store.routeLabel(for: host))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let imageData, let image = meshImage(from: imageData) {
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let error = store.screenError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    ProgressView("Fetching screen…")
                }
                if let updated = resetText(store.screenUpdatedISO) {
                    Text(updated.replacingOccurrences(of: "resets ", with: "updated "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button {
                    store.requestScreen(host: host)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                Text("Read only. Use iPhone for full terminal/VNC.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("Screen")
        .onAppear { store.requestScreen(host: host) }
        .onDisappear { store.stopScreen() }
    }
}

// MARK: - Usage

struct UsageView: View {
    @EnvironmentObject var store: WatchMeshStore

    var body: some View {
        List(store.effectiveUsage?.providers ?? []) { p in
            Section("\(p.displayName) \(p.plan ?? "")") {
                if let today = p.today {
                    Text("Today \(today)").font(.caption)
                }
                if let last30 = p.last30 {
                    Text("30d \(last30)").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(p.limits) { l in
                    WatchLimitRow(limit: l)
                }
                if p.limits.isEmpty {
                    Text("No limit rows yet").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Usage")
        .overlay { if (store.effectiveUsage?.providers ?? []).isEmpty { Text("No usage data").foregroundStyle(.secondary) } }
    }
}

private struct WatchLimitRow: View {
    let limit: UsageLimit
    private var status: LimitStatus { LimitHelpers.status(usedPct: limit.usedPct) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(limit.label).font(.caption)
                Spacer()
                Text(status.label)
                    .font(.caption2)
                    .foregroundStyle(status == .blocked ? .red : (status == .warning ? .orange : .secondary))
            }
            if let pct = limit.usedPct {
                ProgressView(value: min(max(pct/100, 0), 1))
                    .tint(status == .blocked ? .red : .accentColor)
            }
            HStack {
                if let left = LimitHelpers.remainingPct(usedPct: limit.usedPct) {
                    Text(status == .blocked ? "0% left" : "\(left)% left")
                        .font(.caption2.monospacedDigit())
                }
                Spacer()
                if let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) {
                    Text(countdown).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
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

#if canImport(UIKit)
func meshImage(from data: Data) -> Image? {
    guard let image = UIImage(data: data) else { return nil }
    return Image(uiImage: image)
}
#else
func meshImage(from data: Data) -> Image? { nil }
#endif

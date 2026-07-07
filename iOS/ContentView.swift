import SwiftUI
import UIKit
import WebKit

struct ContentView: View {
    @EnvironmentObject var store: MeshStore

    var body: some View {
        TabView {
            MachinesTab().tabItem { Label("Machines", systemImage: "server.rack") }
            TerminalTab().tabItem { Label("Terminal", systemImage: "terminal") }
            RemoteControlTab().tabItem { Label("Remote", systemImage: "display") }
            MonitorTab().tabItem { Label("Monitor", systemImage: "bell.badge") }
            SettingsTab().tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct MonitorTab: View {
    @EnvironmentObject var store: MeshStore
    @ObservedObject private var notifications = NotificationManager.shared

    var body: some View {
        NavigationStack {
            List {
                if notifications.authorizationDenied || store.lastError != nil {
                    Section {
                        if notifications.authorizationDenied {
                            Text("Notifications are off — limit alerts can't be delivered. Enable them in iPhone Settings.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let lastError = store.lastError {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                SessionLimitsBanner()
                Section("Events") {
                    if store.events.isEmpty {
                        Text("No agent events")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.events.reversed()) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(event.title).font(.headline)
                                Spacer()
                                Text(eventTime(event.createdISO))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let body = event.body, !body.isEmpty {
                                Text(body).font(.subheadline)
                            }
                            Text([event.host, event.source, event.session].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
                Section("Usage") {
                    if (store.snapshot?.usage?.providers ?? []).isEmpty {
                        Text("No usage data")
                            .foregroundStyle(.secondary)
                    }
                    UsageRows()
                }
            }
            .navigationTitle("Monitor")
            .toolbar {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}

private struct MachinesTab: View {
    @EnvironmentObject var store: MeshStore

    private var rows: [MachineSnapshot] {
        let machines = store.snapshot?.machines.isEmpty == false
            ? store.snapshot?.machines ?? []
            : store.machines.map { MachineSnapshot(host: $0.host, reachable: false, stats: nil, agents: [], error: "checking...") }
        return activeFirst(machines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    ForEach(rows) { m in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(m.reachable ? .green : .secondary)
                                .frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(machineShortName(m.host))
                                    .font(.headline)
                                Text(machineSummary(m))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(m.authError != nil ? "token" : (m.reachable ? "\(m.agents.count) sess" : "offline"))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(m.authError != nil ? .orange : (m.reachable ? .green : .secondary))
                        }
                    }
                }
                ForEach(rows) { m in
                    Section(header: HStack {
                        Circle().fill(m.reachable ? .green : .secondary).frame(width: 8, height: 8)
                        Text(m.host).font(.headline)
                    }) {
                        if m.reachable {
                            ServiceStatusRow(label: "meshd", ok: true, detail: "active")
                            ServiceStatusRow(label: "auth", ok: m.authError == nil, detail: m.authError ?? "active")
                            if m.authError != nil, let machine = store.machines.first(where: { $0.host == m.host }) {
                                copyableCommand("sh install.sh --token \(machine.token)")
                            }
                            ServiceStatusRow(label: "bridge", ok: m.bridgeReachable, detail: m.bridgeError)
                            ServiceStatusRow(label: "VNC", ok: m.vncReachable, detail: m.vncError)
                            ServiceStatusRow(label: "hooks", ok: hasCap(m, "events"), detail: capDetail(m, "events"))
                            ServiceStatusRow(label: "panes", ok: hasCap(m, "newPane"), detail: capDetail(m, "newPane"))
                            ServiceStatusRow(label: "tailscale", ok: hasCap(m, "tailscale"), detail: capDetail(m, "tailscale"))
                            if let version = m.meshdVersion {
                                StatRow(label: "meshd version", value: version)
                            }
                            if let machine = store.machines.first(where: { $0.host == m.host }) {
                                StatRow(label: "meshd endpoints", value: machine.baseURLs.map(\.absoluteString).joined(separator: " or "))
                            }
                            if let peers = m.tailnetPeers, !peers.isEmpty {
                                SectionLabel("Tailnet peers")
                                ForEach(peers.prefix(10)) { peer in
                                    StatRow(label: peer.host, value: peerDetail(peer))
                                }
                            } else if let tailnetError = m.tailnetError, !tailnetError.isEmpty {
                                StatRow(label: "Tailnet", value: tailnetError)
                            }
                            if let s = m.stats {
                                StatRow(label: "CPU", value: String(format: "%.0f%%", s.cpuPct))
                                StatRow(label: "Memory", value: String(format: "%.0f / %.0f GB (%.0f%%)", s.mem.usedMB/1024, s.mem.totalMB/1024, s.mem.pct))
                                StatRow(label: "Disk", value: String(format: "%.0f / %.0f GB (%.0f%%)", s.disk.usedGB, s.disk.totalGB, s.disk.pct))
                                StatRow(label: "Load", value: s.load.map { String(format: "%.2f", $0) }.joined(separator: " "))
                                StatRow(label: "Sessions", value: "\(s.agentsCount)")
                                if !s.topProcs.isEmpty {
                                    SectionLabel("Top processes")
                                    ForEach(s.topProcs.prefix(4)) { p in
                                        StatRow(label: p.cmd, value: String(format: "%.0f%% · %.0f MB", p.cpuPct, p.memMB))
                                    }
                                }
                            } else {
                                StatRow(label: "Stats", value: "not available")
                            }
                        } else {
                            ServiceStatusRow(label: "meshd", ok: false, detail: m.error ?? "unreachable")
                            ServiceStatusRow(label: "bridge", ok: m.bridgeReachable, detail: m.bridgeError)
                            ServiceStatusRow(label: "VNC", ok: m.vncReachable, detail: m.vncError)
                            ServiceStatusRow(label: "hooks", ok: nil, detail: "unknown")
                            ServiceStatusRow(label: "panes", ok: nil, detail: "unknown")
                            ServiceStatusRow(label: "tailscale", ok: nil, detail: "unknown")
                            Text(m.error ?? "unreachable").foregroundStyle(.secondary)
                            if let machine = store.machines.first(where: { $0.host == m.host }) {
                                Text(machine.baseURLs.map(\.absoluteString).joined(separator: " or "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(m.agents) { a in
                            HStack {
                                Image(systemName: "terminal")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.displayName)
                                    Text(a.isCmux ? "cmux" : "\(a.windows) pane\(a.windows == 1 ? "" : "s")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(a.agentType ?? "shell").font(.caption)
                                    Text(sessionCost(a)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if needsUpdate(m), let machine = store.machines.first(where: { $0.host == m.host }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Update command")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                copyableCommand("sh install.sh --token \(machine.token)")
                                Text("Run from the Mesh installer folder on \(machineShortName(m.host)).")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if needsBridge(m), let machine = store.machines.first(where: { $0.host == m.host }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Terminal bridge")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                copyableCommand("sh install.sh --token \(machine.token)")
                                Text("Starts rmux-bridge on \(machineShortName(m.host)) so phone terminals can open.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if needsSelfCheck(m) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Machine self-check")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                copyableCommand("~/.mesh/bin/mesh-self-check")
                                Text("Checks meshd, sessions, Tailnet, terminal bridge, hooks, and VNC.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mesh")
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView("No machines", systemImage: "server.rack", description: Text("Add one in Settings."))
                }
            }
            .toolbar {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: store.polling ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
            }
        }
    }
}

@ViewBuilder
func copyableCommand(_ command: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(command)
            .font(.caption.monospaced())
            .textSelection(.enabled)
        Spacer()
        Button {
            UIPasteboard.general.string = command
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Copy command")
    }
}

private func sessionCost(_ agent: Agent) -> String {
    let cpu = agent.cpuPct.map { String(format: "%.0f%%", $0) }
    return [cpu, agent.memLabel].compactMap { $0 }.joined(separator: " · ")
}

private func peerDetail(_ peer: TailnetPeer) -> String {
    [peer.online ? "online" : "offline", peer.os, peer.ips.first]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
}

private func activeFirst(_ snaps: [MachineSnapshot]) -> [MachineSnapshot] {
    snaps.sorted {
        if $0.reachable != $1.reachable { return $0.reachable && !$1.reachable }
        if $0.agents.count != $1.agents.count { return $0.agents.count > $1.agents.count }
        return $0.host < $1.host
    }
}

private func machineShortName(_ host: String) -> String {
    host.replacingOccurrences(of: "arya-", with: "").replacingOccurrences(of: "agents", with: "")
}

private func machineSummary(_ machine: MachineSnapshot) -> String {
    guard machine.reachable else { return machine.error ?? "unreachable" }
    let version = machine.meshdVersion.map { "meshd \($0)" } ?? "meshd active"
    if machine.authError != nil { return "\(version) · token needed" }
    let bridge = machine.bridgeReachable == true ? "bridge" : "no bridge"
    let hooks = hasCap(machine, "events") == true ? "hooks" : "needs update"
    return "\(version) · \(bridge) · \(hooks)"
}

private func hasCap(_ machine: MachineSnapshot, _ cap: String) -> Bool? {
    guard let caps = machine.capabilities else { return false }
    return caps.contains(cap)
}

private func capDetail(_ machine: MachineSnapshot, _ cap: String) -> String {
    hasCap(machine, cap) == true ? "active" : "update needed"
}

private func needsUpdate(_ machine: MachineSnapshot) -> Bool {
    machine.reachable && (hasCap(machine, "events") != true || hasCap(machine, "newPane") != true || hasCap(machine, "tailscale") != true)
}

private func needsBridge(_ machine: MachineSnapshot) -> Bool {
    machine.reachable && machine.bridgeReachable != true
}

private func needsSelfCheck(_ machine: MachineSnapshot) -> Bool {
    needsUpdate(machine) || needsBridge(machine) || machine.vncReachable == false || machine.tailnetError != nil
}

private struct SessionLimitsBanner: View {
    @EnvironmentObject var store: MeshStore

    var body: some View {
        if let rows = sessionLimitRows, !rows.isEmpty {
            Section {
                ForEach(rows, id: \.providerId) { row in
                    HStack(spacing: 10) {
                        Image(systemName: row.blocked ? "flame.fill" : "gauge.with.dots.needle.67percent")
                            .foregroundStyle(row.blocked ? .red : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title).font(.subheadline.weight(.semibold))
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.blocked, let pin = store.pinnedLimitSessions.first(where: { $0.providerId == row.providerId }) {
                            Text(pin.sessionName)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } header: {
                Text("Session limits")
            }
        }
    }

    private struct Row {
        var providerId: String
        var title: String
        var detail: String
        var blocked: Bool
    }

    private var sessionLimitRows: [Row]? {
        guard let providers = store.snapshot?.usage?.providers else { return nil }
        let rows = ["claude", "codex"].compactMap { id -> Row? in
            guard let p = providers.first(where: { $0.id.lowercased() == id }),
                  let limit = p.limits.first(where: { LimitHelpers.isSessionLimit(label: $0.label) }) else { return nil }
            let blocked = LimitHelpers.isBlocked(limit)
            let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) ?? "—"
            let left = LimitHelpers.remainingPct(usedPct: limit.usedPct).map { "\($0)% left" } ?? "—"
            return Row(providerId: id,
                       title: "\(p.displayName) session",
                       detail: blocked ? "Limit reached · \(countdown)" : "\(left) · \(countdown)",
                       blocked: blocked)
        }
        return rows.isEmpty ? nil : rows
    }
}

private struct UsageRows: View {
    @EnvironmentObject var store: MeshStore

    var body: some View {
        ForEach(store.snapshot?.usage?.providers ?? []) { p in
            VStack(alignment: .leading, spacing: 8) {
                Text("\(p.displayName) \(p.plan ?? "")")
                    .font(.headline)
                ForEach(p.limits) { l in
                    LimitRow(limit: l)
                }
                if let last30 = p.last30 {
                    StatRow(label: "Last 30d", value: last30)
                }
            }
        }
    }
}

private struct LimitRow: View {
    let limit: UsageLimit

    private var status: LimitStatus { LimitHelpers.status(usedPct: limit.usedPct) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(limit.label, systemImage: statusIcon)
                    .foregroundStyle(statusColor)
                Spacer()
                if let left = LimitHelpers.remainingPct(usedPct: limit.usedPct) {
                    Text(status == .blocked ? "0% left" : "\(left)% left")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(statusColor)
                }
            }
            if let pct = limit.usedPct {
                ProgressView(value: min(max(pct/100, 0), 1))
                    .tint(statusColor)
            }
            HStack {
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                Spacer()
                if let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) {
                    Text(countdown)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: String {
        switch status {
        case .blocked: return "flame.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .available: return "checkmark.circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .blocked: return .red
        case .warning: return .orange
        case .available: return .green
        }
    }
}

private struct SettingsTab: View {
    @EnvironmentObject var store: MeshStore
    @State private var newCommand = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Machines") {
                    ForEach($store.machines) { $m in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("host", text: $m.host)
                                .font(.headline)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            LabeledContent("IP") { TextField("ip", text: $m.ip).multilineTextAlignment(.trailing) }
                            LabeledContent("Port") { TextField("port", value: $m.port, format: .number).multilineTextAlignment(.trailing) }
                            LabeledContent("Bridge") {
                                TextField("http://ip:7820", text: Binding(
                                    get: { m.bridgeURL ?? "" },
                                    set: { m.bridgeURL = $0.isEmpty ? nil : $0 }
                                ))
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            }
                            LabeledContent("VNC") {
                                TextField("http://ip:6080/vnc.html", text: Binding(
                                    get: { m.vncURL ?? "" },
                                    set: { m.vncURL = $0.isEmpty ? nil : $0 }
                                ))
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            }
                            SecureField("token", text: $m.token)
                            HStack {
                                Button {
                                    UIPasteboard.general.string = m.token
                                } label: {
                                    Label("Copy token", systemImage: "key")
                                }
                                Button {
                                    UIPasteboard.general.string = "sh install.sh --token \(m.token)"
                                } label: {
                                    Label("Copy install", systemImage: "doc.on.doc")
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    .onDelete { store.deleteMachines(atOffsets: $0) }
                    Button { store.addMachine() } label: {
                        Label("Add machine", systemImage: "plus.circle")
                    }
                }

                Section("Quick send") {
                    ForEach($store.quickCommands, id: \.self) { $cmd in
                        TextField("command", text: $cmd)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .onDelete { store.quickCommands.remove(atOffsets: $0); store.save() }
                    HStack {
                        TextField("new command", text: $newCommand)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            let trimmed = newCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            store.quickCommands.append(trimmed)
                            newCommand = ""
                            store.save()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section {
                    Text("When a provider session limit resets, tap the alert to send continue to the pinned rmux or cmux session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(["claude", "codex"], id: \.self) { providerId in
                        PinnedLimitEditor(providerId: providerId)
                    }
                } header: {
                    Text("Limit resume pins")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Save") { store.save(); Task { await store.refresh() } } }
        }
    }
}

private struct PinnedLimitEditor: View {
    @EnvironmentObject var store: MeshStore
    let providerId: String

    @State private var host: String = ""
    @State private var sessionName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(providerId.capitalized).font(.headline)
            Picker("Machine", selection: $host) {
                Text("Pick machine").tag("")
                ForEach(store.machines) { m in
                    Text(m.host).tag(m.host)
                }
            }
            TextField("rmux session or cmux:surface:N", text: $sessionName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack {
                Button("Save pin") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(host.isEmpty || sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if store.pinnedLimitSessions.contains(where: { $0.providerId.lowercased() == providerId.lowercased() }) {
                    Button("Clear", role: .destructive) {
                        store.removePinnedLimit(providerId: providerId)
                        sessionName = ""
                    }
                }
            }
            .font(.caption)
        }
        .onAppear { load() }
    }

    private func load() {
        if let pin = store.pinnedLimitSessions.first(where: { $0.providerId.lowercased() == providerId.lowercased() }) {
            host = pin.host
            sessionName = pin.sessionName
        } else if host.isEmpty, let first = store.machines.first {
            host = first.host
        }
    }

    private func save() {
        let trimmed = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !trimmed.isEmpty else { return }
        store.updatePinnedLimit(PinnedLimitSession(providerId: providerId, host: host, sessionName: trimmed))
    }
}

private struct RemoteControlTab: View {
    @EnvironmentObject var store: MeshStore

    private var machines: [Machine] {
        guard let snaps = store.snapshot?.machines, !snaps.isEmpty else { return store.machines }
        let sortedHosts = activeFirst(snaps).map(\.host)
        let seen = Set(sortedHosts)
        return sortedHosts.compactMap { host in store.machines.first { $0.host == host } }
            + store.machines.filter { !seen.contains($0.host) }
    }

    private func snap(for machine: Machine) -> MachineSnapshot? {
        store.snapshot?.machines.first { $0.host == machine.host }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(machines) { machine in
                    Section(machine.host) {
                        NavigationLink {
                            RemoteWebScreen(title: machine.host, urlString: machine.resolvedVNC)
                        } label: {
                            Label("Open VNC", systemImage: "display")
                        }
                        if let snap = snap(for: machine) {
                            ServiceStatusRow(label: "machine", ok: snap.reachable, detail: snap.reachable ? "active" : snap.error)
                            ServiceStatusRow(label: "VNC", ok: snap.vncReachable, detail: snap.vncError)
                        }
                        Text(machine.resolvedVNC)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Remote")
            .overlay {
                if machines.isEmpty {
                    ContentUnavailableView("No machines", systemImage: "display", description: Text("Add a VNC URL in Settings."))
                }
            }
        }
    }
}

struct RemoteWebScreen: View {
    let title: String
    let urlString: String
    @State private var reloadToken = UUID()

    var body: some View {
        Group {
            if let url = URL(string: urlString) {
                ControlWebView(url: url, reloadToken: reloadToken)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("Bad URL", systemImage: "link", description: Text(urlString))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { reloadToken = UUID() } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }
}

private struct ControlWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: UUID

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.minimumZoomScale = 0.25
        web.scrollView.maximumZoomScale = 6
        web.scrollView.bouncesZoom = true
        web.load(URLRequest(url: url))
        context.coordinator.lastReloadToken = reloadToken
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if web.url != url || context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            web.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastReloadToken: UUID?
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct ServiceStatusRow: View {
    let label: String
    let ok: Bool?
    let detail: String?

    var body: some View {
        HStack {
            Label(label, systemImage: ok == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok == true ? .green : .secondary)
            Spacer()
            Text(ok == true ? (detail ?? "active") : (detail ?? "down"))
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private func resetText(_ iso: String?) -> String? {
    guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return nil }
    return "resets \(date.formatted(date: .abbreviated, time: .shortened))"
}

private func eventTime(_ iso: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
    return date.formatted(date: .omitted, time: .shortened)
}

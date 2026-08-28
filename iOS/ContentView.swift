import SwiftUI
import UIKit
import WebKit
import ActivityKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: MeshStore
    #if DEBUG
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-uiRemote") ? Tab.remote : Tab.machines
    #else
    @State private var tab = Tab.machines
    #endif

    enum Tab: Hashable { case machines, terminal, remote, monitor, settings }

    var body: some View {
        TabView(selection: $tab) {
            MachinesTab().tabItem { Label("Machines", systemImage: "server.rack") }.tag(Tab.machines)
            TerminalTab().tabItem { Label("Terminal", systemImage: "terminal") }.tag(Tab.terminal)
            RemoteControlTab().tabItem { Label("Remote", systemImage: "display") }.tag(Tab.remote)
            MonitorTab().tabItem { Label("Monitor", systemImage: "bell.badge") }.tag(Tab.monitor)
            SettingsTab().tabItem { Label("Settings", systemImage: "gearshape") }.tag(Tab.settings)
        }
        // meshwatch://session/<host>/<name> — from the live card, and anywhere else we
        // want to land someone on the session rather than on the app in general.
        .onOpenURL { url in
            if store.open(url: url), store.deepLinkPair == nil { tab = .terminal }
        }
        // Whatever set it — a link, the live card, the Needs-you row — the session
        // screen lives in the Terminal tab's stack. Pushing it without switching tabs
        // put the session on a stack nobody was looking at, and it is also what
        // `MeshStore.currentlyViewing` reports as on screen, so the alert suppression
        // that hangs off it would have been suppressing alerts about an invisible view.
        .onChange(of: store.deepLinkSession) { _, target in
            if target != nil { tab = .terminal }
        }
        // A scanned pairing QR (system Camera → banner → here) opens the pair sheet
        // pre-filled over whatever tab is up; the user confirms the code and taps Pair.
        .sheet(item: $store.deepLinkPair) { target in
            PairMachineView(prefill: target).environmentObject(store)
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
                            // With the time on it. A bare line could be describing the
                            // tap you just made or one from this morning, and reading
                            // it as "right now" is how a resolved failure kept sending
                            // people to debug a mesh that was already fine.
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lastError.message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Text(lastError.at, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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

/// Shown when iOS is silently dropping our traffic. Without this the app just says
/// every machine is offline, which sends you debugging the mesh instead of tapping a
/// toggle. There is no API to read or request this permission once it has been
/// answered, so the only cure is Settings.
private struct LocalNetworkBlockedBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("iOS is blocking the connection", systemImage: "exclamationmark.shield")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Your machines are on addresses iOS treats as a local network — a "
                 + "192.168.x home LAN, or the 100.x range a VPN like Tailscale uses. "
                 + "LeSearch Mesh needs Local Network permission, and every request is "
                 + "being dropped before it leaves the phone until it has one.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings › Local Network", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}

private struct MachinesTab: View {
    @EnvironmentObject var store: MeshStore
    @State private var pairing = false

    private var attention: [LiveSessionPick] {
        store.snapshot.map { sessionsNeedingAttention(from: $0) } ?? []
    }

    private var rows: [MachineSnapshot] {
        let machines = store.snapshot?.machines.isEmpty == false
            ? store.snapshot?.machines ?? []
            : store.machines.map {
                MachineSnapshot(host: $0.host, reachable: false, stats: nil, agents: [],
                                // "checking…" is only true before we have ever looked.
                                error: store.hasEverPolled ? "no answer" : "checking…")
            }
        return activeFirst(machines)
    }

    /// Before the first poll finishes there is nothing to say about any machine, and
    /// the list's fallback rows said "offline" — a claim about a fleet the app had not
    /// contacted once. This is the honest version of that moment, and it lasts until
    /// the first host answers (the poll publishes progressively, so usually well under
    /// a second on a healthy tailnet).
    private var firstPoll: some View {
        VStack(spacing: 12) {
            ProgressView {
                Text(store.machines.count == 1
                     ? "Checking your machine…"
                     : "Checking your \(store.machines.count) machines…")
            }
            .controlSize(.large)
            Text("Nothing has answered yet — this is the first look since launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.machines.isEmpty {
                    NoMachinesView { pairing = true }
                } else if !store.hasEverPolled && store.snapshot == nil {
                    firstPoll
                } else {
                    machineList
                }
            }
            .navigationTitle("Machines")
            .toolbar {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: store.polling ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .disabled(store.machines.isEmpty)
                Button { pairing = true } label: { Label("Pair a machine", systemImage: "plus.circle") }
            }
            .sheet(isPresented: $pairing) { PairMachineView().environmentObject(store) }
        }
    }

    private var machineList: some View {
            List {
                if store.localNetworkBlocked {
                    Section { LocalNetworkBlockedBanner() }
                }
                if !attention.isEmpty {
                    Section {
                        ForEach(attention, id: \.self) { item in
                            AttentionRow(item: item)
                        }
                    } header: {
                        Label("Needs you", systemImage: "exclamationmark.bubble.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    ForEach(rows) { m in
                        NavigationLink {
                            MachineDetailView(host: m.host)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(m.authError != nil ? .orange : (m.reachable ? .green : .secondary))
                                    .frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(machineShortName(m.host)).font(.headline)
                                    Text(machineSummary(m))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(m.authError != nil ? "token"
                                     : m.isStale ? m.statusLabel
                                     : (m.reachable ? "\(m.agents.count) sess" : "offline"))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(m.authError != nil ? .orange : (m.reachable ? .green : .secondary))
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                store.removeMachine(host: m.host)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .refreshable { await store.refresh() }
    }
}

/// Everything about one machine. Split out of the list because the list used to show
/// each machine twice: a compact status row near the top and a full diagnostics
/// section below it, both saying "green", and neither being where you wanted to go.
private struct MachineDetailView: View {
    @EnvironmentObject var store: MeshStore
    @Environment(\.dismiss) private var dismiss
    let host: String
    @State private var repairing = false
    @State private var confirmingRemoval = false

    private var snapshot: MachineSnapshot? {
        store.snapshot?.machines.first { $0.host == host }
    }

    private var config: Machine? {
        store.machines.first { $0.host == host }
    }

    /// The newest event this phone holds for a session on this machine, so a row can
    /// say what the session is doing even when the daemon predates `sessionStatus`.
    private func latestEvent(for session: String) -> AgentEvent? {
        store.events.last { event in
            guard event.session == session else { return false }
            guard let eventHost = event.host, !eventHost.isEmpty else { return true }
            return hostNamesMatch(eventHost, host)
        }
    }

    var body: some View {
        List {
            if let m = snapshot {
                if m.reachable {
                    if let machine = store.machines.first(where: { $0.host == m.host }) {
                        MachineSetupSection(machine: machine)
                    }
                    ServiceStatusRow(label: "meshd", ok: !m.isStale, detail: m.statusLabel)
                    ServiceStatusRow(label: "auth", ok: m.authError == nil, detail: m.authError ?? "active")
                    if m.authError != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This machine rotated its token. Run mesh pair on it, then tap Pair again below and enter the code it prints — that replaces the saved token in place.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            CopyableCommand(text: "mesh pair")
                        }
                    }
                    ServiceStatusRow(label: "bridge", ok: m.bridgeReachable, detail: m.bridgeError)
                    ServiceStatusRow(label: "VNC", ok: m.vncReachable, detail: m.vncError)
                    ServiceStatusRow(label: "hooks", ok: hasCap(m, "events"), detail: capDetail(m, "events"))
                    ServiceStatusRow(label: "panes", ok: hasCap(m, "newPane"), detail: capDetail(m, "newPane"))
                    ServiceStatusRow(label: "tailscale", ok: hasCap(m, "tailscale"), detail: capDetail(m, "tailscale"))
                    if let version = m.meshdVersion {
                        StatRow(label: "meshd version", value: version)
                    }
                    // Everything the app asked this daemon for and did not get. It goes
                    // directly under the version because the version alone never told
                    // anyone anything: "meshd 0.4.1" is only a fact, and the fact that
                    // matters is that seven features are switched off behind it.
                    DaemonUpdateSection(capabilities: m.capabilities)
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
                    if let machine = store.machines.first(where: { $0.host == m.host }) {
                        MachinePowerSection(machine: machine, snapshot: m)
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
                    // Turn the machine on from the couch: an awake peer on its own LAN
                    // broadcasts the magic packet. Everything this needs — the MAC and
                    // the subnet — was cached while the machine was still up.
                    WakeRow(host: m.host)
                }
                ForEach(m.agents) { a in
                    HStack {
                        Image(systemName: "terminal")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.displayName)
                            SessionStateBadge(state: a.displayState(latestEvent: latestEvent(for: a.name)))
                            Text(a.kindLabel)
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
                // The installer keeps the machine's existing token, so neither of these
                // needs one on the command line — and printing a live bearer token into
                // a copyable field was a habit worth breaking.
                if needsUpdate(m) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Update the agent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        CopyableCommand(text: PairMachineView.installCommand)
                        Text("Run on \(machineShortName(m.host)). It keeps the existing token.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if needsBridge(m) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Terminal bridge")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        CopyableCommand(text: PairMachineView.installCommand)
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
            } else {
                Text("No reading for this machine yet.").foregroundStyle(.secondary)
            }
            // Always present, whatever state the machine is in. The screen above
            // diagnoses "token rejected" and used to tell the user to "pair again"
            // while the only pairing UI lived behind a + button two screens away —
            // the diagnosis and the cure have to be in the same place.
            Section {
                Button {
                    repairing = true
                } label: {
                    Label("Pair again", systemImage: "qrcode.viewfinder")
                }
                Button(role: .destructive) {
                    confirmingRemoval = true
                } label: {
                    Label("Remove machine", systemImage: "trash")
                }
            } footer: {
                Text("Pairing the same machine replaces its saved token in place. Removing only forgets it on this phone — and it stays forgotten until you pair it again.")
            }
        }
        .navigationTitle(machineShortName(host))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
        .sheet(isPresented: $repairing) {
            PairMachineView(prefill: config.map {
                MeshStore.PairTarget(address: $0.ip, port: $0.port, code: "")
            })
            .environmentObject(store)
        }
        .confirmationDialog("Remove \(machineShortName(host))?",
                            isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove machine", role: .destructive) {
                store.removeMachine(host: host)
                dismiss()
            }
        } message: {
            Text("The machine itself is untouched. Pair it again any time to bring it back.")
        }
    }
}

/// What one session is doing, in a shape you can read without colour.
///
/// The dot alone was the old version, and a red dot next to a green dot is the same
/// dot to about one man in twelve. The glyph carries the meaning — a question mark, a
/// gear, a tick, a warning triangle — and the word carries it again; the tint is the
/// third copy, not the only one.
private struct SessionStateBadge: View {
    let state: SessionDisplayState

    var body: some View {
        let bridged = state.sessionState
        Label {
            Text(bridged.cardLabel)
                .font(.caption2.weight(.medium))
        } icon: {
            Image(systemName: bridged.symbol)
                .font(.caption2)
        }
        .foregroundStyle(bridged.tint)
        .accessibilityLabel("Session state: \(bridged.cardLabel)")
    }
}

/// Power and session control for a reachable machine.
///
/// Lock, Sleep display and Sleep are one tap: each is reversible from the machine's own
/// keyboard, and asking "are you sure?" about locking a screen trains people to dismiss
/// the dialog that matters. Restart and Shut Down are not reversible from anywhere — a
/// shut-down machine cannot be woken by anything in this app except a Wake-on-LAN that
/// needs a peer on its LAN — so both confirm, and both only appear where the daemon
/// says it can actually do them.
private struct MachinePowerSection: View {
    @EnvironmentObject var store: MeshStore
    let machine: Machine
    let snapshot: MachineSnapshot

    @State private var pending: PowerAction?
    @State private var running: String?
    @State private var failure: String?

    /// One row. `action` is meshd's own vocabulary for `POST /system`, not ours, so
    /// the string that reaches the daemon is the string written here.
    private struct PowerAction: Identifiable, Equatable {
        var id: String { action }
        var action: String
        var label: String
        var symbol: String
        /// Nil for the reversible ones. Present means it confirms first.
        var confirm: (title: String, verb: String, consequence: String)?

        static func == (lhs: PowerAction, rhs: PowerAction) -> Bool { lhs.action == rhs.action }
    }

    /// meshd 0.5.0 added shutdown and restart. Offering them against an older daemon
    /// would be a button that 400s, so they appear only where "power" is advertised.
    private var canPowerOff: Bool { snapshot.capabilities?.contains("power") ?? false }

    /// Reversible from the machine's own keyboard, so no dialog: asking "are you sure?"
    /// about locking a screen is how people learn to dismiss the dialog that matters.
    private let reversible: [PowerAction] = [
        PowerAction(action: "lock", label: "Lock", symbol: "lock.fill", confirm: nil),
        PowerAction(action: "displaysleep", label: "Sleep display", symbol: "display", confirm: nil),
        PowerAction(action: "sleep", label: "Sleep", symbol: "moon.fill", confirm: nil),
    ]

    private var irreversible: [PowerAction] {
        let name = machineShortName(machine.host)
        return [
            PowerAction(action: "restart", label: "Restart…", symbol: "arrow.clockwise.circle",
                        confirm: (title: "Restart \(name)?",
                                  verb: "Restart",
                                  consequence: "Every session on it stops. Anything unsaved there is lost, and agents mid-task will not come back on their own.")),
            PowerAction(action: "shutdown", label: "Shut Down…", symbol: "power",
                        confirm: (title: "Shut down \(name)?",
                                  verb: "Shut Down",
                                  consequence: "Every session stops and the machine goes dark. After that only its own power button, or a wake packet from a machine on the same network, brings it back.")),
        ]
    }

    var body: some View {
        Section("Power") {
            ForEach(reversible) { item in
                Button {
                    run(item)
                } label: {
                    Label(running == item.action ? "\(item.label)…" : item.label, systemImage: item.symbol)
                }
                .disabled(running != nil)
            }
            if canPowerOff {
                ForEach(irreversible) { item in
                    Button(role: .destructive) {
                        pending = item
                    } label: {
                        Label(running == item.action ? "\(item.label)…" : item.label, systemImage: item.symbol)
                    }
                    .disabled(running != nil)
                }
            } else {
                Text("Restart and Shut Down need a newer agent on this machine. Re-run the install command on it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let failure {
                // The daemon's own words, not a shrug. macOS raises a one-time
                // Automation permission prompt for shutdown and restart and refuses
                // with -1743 until someone approves it at the Mac — that answer travels
                // back verbatim, and printing it is the only way anyone would know to
                // go and approve it.
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog(pending?.confirm?.title ?? "",
                            isPresented: Binding(get: { pending != nil },
                                                 set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible,
                            presenting: pending) { item in
            Button(item.confirm?.verb ?? item.label, role: .destructive) { run(item) }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { item in
            Text(item.confirm?.consequence ?? "")
        }
    }

    private func run(_ item: PowerAction) {
        pending = nil
        running = item.action
        failure = nil
        Task { @MainActor in
            failure = await store.systemAction(item.action, on: machine)
            running = nil
        }
    }
}

/// The features this machine's daemon is too old to serve, and the one command that
/// fixes it.
///
/// This is the answer to a real week of confusion: the screen on the watch was
/// unreadable, the app was blamed, and the app was innocent — the daemon on the machine
/// was a version behind and had been silently ignoring every request for a sharp crop.
/// An old daemon does not fail loudly. It answers 200 with the old shape of the answer,
/// which is indistinguishable from the feature simply not working.
///
/// Silent when there is nothing to say, and silent before the machine has been polled:
/// a warning that cries wolf on healthy machines is a warning nobody reads on the one
/// that needs it.
private struct DaemonUpdateSection: View {
    let capabilities: [String]?

    var body: some View {
        let gaps = DaemonCapabilities.gaps(in: capabilities)
        if !gaps.isEmpty, let headline = DaemonCapabilities.headline(gapCount: gaps.count) {
            VStack(alignment: .leading, spacing: 6) {
                Label(headline, systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                ForEach(gaps, id: \.capability) { gap in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gap.feature).font(.caption2.weight(.medium))
                        Text(gap.symptom)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Run this on that machine — it upgrades in place and keeps the token and pairing:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                CopyableCommand(text: DaemonCapabilities.upgradeCommand)
            }
        }
    }
}

/// Wake-on-LAN for a machine that has gone dark.
///
/// The packet is a LAN broadcast, so the phone cannot send it across a tailnet and a
/// peer on the *wrong* network sends one nobody hears. Every state here is a sentence
/// about why, because a greyed-out or missing button teaches nothing: no cached MAC,
/// no online peer on that subnet, or a peer and a button.
private struct WakeRow: View {
    @EnvironmentObject var store: MeshStore
    let host: String

    @State private var sending = false
    @State private var sentVia: String?
    @State private var failure: String?

    private var identity: MachineNetIdentity { store.netIdentity(for: host) }

    var body: some View {
        if identity.mac == nil {
            Text("No hardware address for \(machineShortName(host)) yet. Open it once while it's awake and a Wake button appears here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let peer = store.wakePeer(for: host) {
            Button {
                sending = true
                failure = nil
                Task { @MainActor in
                    if let problem = await store.wake(host: host) {
                        failure = problem
                    } else {
                        sentVia = peer.host
                    }
                    sending = false
                }
            } label: {
                Label(label(peer: peer), systemImage: "power")
            }
            .disabled(sending || sentVia != nil)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } else {
            Text(identity.ipv4 == nil
                 ? "Nothing else is online to broadcast a wake packet for \(machineShortName(host))."
                 : "Can't wake \(machineShortName(host)): no online machine is on its network (\(identity.ipv4 ?? "")).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func label(peer: Machine) -> String {
        if sending { return "Sending…" }
        if let sentVia { return "Magic packet sent via \(machineShortName(sentVia)) — waking takes ~30s" }
        return "Wake via \(machineShortName(peer.host))"
    }
}

/// Setup & permissions for one machine, read from /doctor — which tests each
/// capability by exercising it, so a green row means it actually works, not that it is
/// configured. The two macOS grants (Accessibility, Screen Recording) fail silently and
/// can only be prompted from the process that needs them, so this offers a button that
/// POSTs /doctor/fix to pop the real system dialogs on the Mac itself.
private struct MachineSetupSection: View {
    @EnvironmentObject var store: MeshStore
    let machine: Machine
    @State private var report: DoctorReport?
    @State private var loading = false
    @State private var asking = false
    @State private var error: String?

    private var hasRemoteFix: Bool {
        guard let report else { return false }
        return report.orderedChecks.contains { !$0.check.ok && DoctorReport.isRemotelyFixable($0.name) }
    }
    private var isMac: Bool { report?.platform == "darwin" }

    var body: some View {
        Section("Setup & permissions") {
            if let report {
                ForEach(report.orderedChecks, id: \.name) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        ServiceStatusRow(label: item.name, ok: item.check.ok, detail: item.check.detail)
                        if !item.check.ok, let fix = item.check.fix,
                           !DoctorReport.isRemotelyFixable(item.name) {
                            Text(fix).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if hasRemoteFix && isMac {
                    Button {
                        Task { await run(fix: true) }
                    } label: {
                        Label(asking ? "Asking \(machineShortName(machine.host))…" : "Grant on \(machineShortName(machine.host))",
                              systemImage: "hand.tap")
                    }
                    .disabled(asking)
                    Text("Opens the Accessibility and Screen Recording dialogs on \(machineShortName(machine.host)). Approve them there, then pull to refresh.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if loading {
                HStack { ProgressView(); Text("Checking \(machineShortName(machine.host))…").foregroundStyle(.secondary) }
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await run(fix: false) }
    }

    private func run(fix: Bool) async {
        if fix { asking = true } else { loading = true }
        defer { asking = false; loading = false }
        do {
            // The store's constructor, not a bare `MeshClient(machine:)`. /doctor is not
            // capability-gated today, but a client built without the capability list is
            // the shape of every 0.5.0 feature silently staying off, and one file with
            // one exception in it is how that starts.
            report = try await store.client(for: machine).doctor(fix: fix)
            error = nil
        } catch {
            // An older daemon has no /doctor route; say so instead of showing a raw 404.
            // Matched on the status, not the case: meshd answers an unknown route with
            // `{"error":"not found"}`, which now arrives as .refused.
            if (error as? MeshClient.MeshError)?.statusCode == 404 {
                self.error = "This machine's daemon predates setup checks. Reinstall to update it."
            } else {
                self.error = "Couldn't reach \(machineShortName(machine.host))."
            }
        }
    }
}

/// One blocked agent, on the phone. Continue answers it in place; tapping the row
/// opens the session for anything that needs more than Enter.
/// One blocked agent. Same shape as the watch's row, deliberately: the two surfaces
/// have to agree about what a destructive answer looks like, or the habit you build on
/// one of them gets you on the other.
///
/// The affirmative is not inside a row-wide tap target. It sends Return into a live
/// shell, and Return takes whichever option the agent highlighted — so it is a "yes",
/// and a yes must be its own deliberate control.
private struct AttentionRow: View {
    @EnvironmentObject var store: MeshStore
    let item: LiveSessionPick
    @State private var answered = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: item.state.symbol)
                    .font(.footnote)
                    .foregroundStyle(item.state.tint)
                Text(item.session).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
                Text(machineShortName(item.host)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if let since = item.blockedSince {
                    Text(since, style: .timer)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            if !item.lastLine.isEmpty {
                Text(item.lastLine)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.5)))
            }

            if item.risk.isDestructive, let why = item.risk.consequence {
                Label(why, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if let failure {
                // "Sent" used to appear the instant the button was tapped, whether or
                // not anything reached the machine — which is the one lie a button
                // like this must never tell, because the agent stays blocked and the
                // screen says it was answered.
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button(answered ? "Sent" : item.risk.verb) {
                    answered = true
                    failure = nil
                    Task { @MainActor in
                        if let problem = await store.respondToAgent(
                            host: item.host, session: item.session, text: nil, key: "enter") {
                            failure = problem
                            answered = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(item.risk.isDestructive ? .red : .orange)
                .controlSize(.small)
                .disabled(answered)

                Button("Open session") {
                    store.deepLinkSession = MeshStore.SessionTarget(host: item.host, session: item.session)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(.vertical, 4)
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
    // Just the hostname. The old version stripped "arya-" and "agents", which flattered
    // exactly one person's naming scheme and mangled everyone else's.
    host.split(separator: ".").first.map(String.init) ?? host
}

private func machineSummary(_ machine: MachineSnapshot) -> String {
    guard machine.reachable else { return machine.error ?? "unreachable" }
    let version = machine.meshdVersion.map { "meshd \($0)" } ?? "meshd active"
    if machine.authError != nil { return "\(version) · token rejected — pair again" }
    let bridge = machine.bridgeReachable == true ? "bridge" : "no bridge"
    // An out-of-date daemon earns the last slot ahead of "hooks". The row used to read
    // "meshd 0.4.1 · no bridge · hooks" on a daemon missing seven capabilities, which
    // is a sentence that says everything is fine while nothing is.
    let gaps = DaemonCapabilities.gaps(in: machine.capabilities).count
    if gaps > 0 { return "\(version) · \(bridge) · update available" }
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

/// Whether this machine's daemon is behind what the app needs.
///
/// This used to name three capabilities — events, newPane, tailscale — and it went
/// blind the moment a fourth was added. Every daemon since has had all three, so the
/// function answered "up to date" for a fleet that was a whole minor version behind and
/// missing seven of the features the app was actively calling. Nobody was warned; the
/// symptom people saw instead was an unreadable screen on their watch.
///
/// So the list lives in exactly one place now (Shared/DaemonCapabilities.swift), and a
/// new capability starts warning the day it starts being used.
private func needsUpdate(_ machine: MachineSnapshot) -> Bool {
    machine.reachable && !DaemonCapabilities.gaps(in: machine.capabilities).isEmpty
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
    @EnvironmentObject var lock: AppLock
    @ObservedObject private var notifications = NotificationManager.shared
    @State private var newCommand = ""
    @State private var pairing = false
    /// Read from ActivityKit rather than from our own controller so the row states the
    /// system's answer, not our cache of it, and follows the same stream the controller
    /// does — a permission flipped in Settings updates this without a relaunch.
    @State private var liveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

    /// Alerts, split by what they are about. One switch for all agent notifications is
    /// what made people turn the whole category off — the turn-end chatter and the
    /// blocked agent arrived through the same door, and only one of them was worth a buzz.
    private var alertsSection: some View {
        Section {
            Toggle(isOn: $notifications.alertNeedsAttention) {
                Label("An agent is waiting on you", systemImage: "exclamationmark.bubble.fill")
            }
            Toggle(isOn: $notifications.alertErrors) {
                Label("Something failed", systemImage: "exclamationmark.triangle.fill")
            }
            Toggle(isOn: $notifications.alertTurnEnd) {
                Label("A turn finished", systemImage: "checkmark.circle.fill")
            }
            Text("Turn-finished alerts are off by default: on a busy day they are most of the buzzing, and none of them is a question. Machines on the current agent stop sending them entirely; older ones still send, and this takes their banners back down.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if notifications.authorizationDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Notifications are off for this app — turn them on in Settings",
                          systemImage: "bell.slash")
                }
                .font(.caption)
            }
            if !liveActivitiesEnabled {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Live Activities are off for this app — enable in Settings",
                          systemImage: "rectangle.on.rectangle.slash")
                }
                .font(.caption)
                Text("Without them there is no Lock Screen card and no Dynamic Island for a session that needs you — only the notification.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Alerts")
        }
        .task {
            liveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                liveActivitiesEnabled = enabled
            }
        }
    }

    /// Sideloading several times an hour makes "is this the new build?" a real
    /// question; the timestamp answers it with nothing to remember to bump.
    private var buildRow: some View {
        HStack {
            Label("Build", systemImage: "hammer")
            Spacer()
            Text(BuildInfo.summary)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("App") {
                    buildRow
                }
                Section("Machines") {
                    ForEach($store.machines) { $m in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("host", text: $m.host.shellSafe)
                                .font(.headline)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            LabeledContent("IP") { TextField("ip", text: $m.ip.shellSafe).multilineTextAlignment(.trailing) }
                            LabeledContent("Port") { TextField("port", value: $m.port, format: .number).multilineTextAlignment(.trailing) }
                            LabeledContent("Bridge") {
                                TextField("http://ip:7820", text: Binding(
                                    get: { m.bridgeURL ?? "" },
                                    set: { let v = $0.shellSafePunctuation; m.bridgeURL = v.isEmpty ? nil : v }
                                ))
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            }
                            LabeledContent("VNC") {
                                TextField("http://ip:6080/vnc.html", text: Binding(
                                    get: { m.vncURL ?? "" },
                                    set: { let v = $0.shellSafePunctuation; m.vncURL = v.isEmpty ? nil : v }
                                ))
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            }
                            SecureField("token", text: $m.token)
                            HStack {
                                Button {
                                    // This machine's bearer token. A plain pasteboard write
                                    // syncs to every device on the Apple ID via Universal
                                    // Clipboard and sits there until something replaces it.
                                    // Keep it on this device and let it expire.
                                    UIPasteboard.general.setItems(
                                        [[UTType.plainText.identifier: m.token]],
                                        options: [.localOnly: true,
                                                  .expirationDate: Date().addingTimeInterval(120)])
                                } label: {
                                    Label("Copy token", systemImage: "key")
                                }
                                Button {
                                    UIPasteboard.general.string = PairMachineView.installCommand
                                } label: {
                                    Label("Copy install", systemImage: "doc.on.doc")
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    .onDelete { store.deleteMachines(atOffsets: $0) }
                    Button { pairing = true } label: {
                        Label("Pair a machine", systemImage: "qrcode.viewfinder")
                    }
                    Button { store.addMachine() } label: {
                        Label("Add manually", systemImage: "plus.circle")
                    }
                    .font(.caption)
                }

                alertsSection

                Section("Quick send") {
                    ForEach($store.quickCommands, id: \.self) { $cmd in
                        TextField("command", text: $cmd.shellSafe)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .onDelete { store.quickCommands.remove(atOffsets: $0); store.save() }
                    HStack {
                        TextField("new command", text: $newCommand.shellSafe)
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

                if !store.machines.isEmpty {
                    Section {
                        ForEach(store.machines) { machine in
                            DiagnoseRow(machine: machine)
                        }
                        Text("Tries each address on its own and reports what happened. /health needs no token, so a green address with a red token means the network is fine and only the token is wrong.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Connection diagnosis")
                    }
                }

                Section {
                    Toggle(isOn: $lock.enabled) {
                        Label("Require \(AppLock.methodName)", systemImage: "lock.fill")
                    }
                    .disabled(!AppLock.isAvailable)
                    Text(AppLock.isAvailable
                         ? "Machine tokens are stored in the Keychain. This asks for \(AppLock.methodName) before the app opens."
                         : "Set a device passcode to enable this.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Security")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Save") { store.save(); Task { await store.refresh() } } }
            .sheet(isPresented: $pairing) { PairMachineView().environmentObject(store) }
        }
    }
}

/// One machine's tester: every address probed independently, then the token.
/// On demand, not on appear — six timeouts' worth of requests per machine is
/// too expensive to fire just for scrolling past Settings.
private struct DiagnoseRow: View {
    let machine: Machine
    @State private var results: [MeshStore.AddressDiagnosis] = []
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(machine.host).font(.headline)
                Spacer()
                Button {
                    Task {
                        running = true
                        results = await MeshStore.diagnose(machine)
                        running = false
                    }
                } label: {
                    if running { ProgressView().controlSize(.small) } else { Text("Test") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(running)
            }
            ForEach(results) { r in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(r.ok ? .green : .red)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.address).font(.caption.monospaced())
                        Text(r.outcome).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
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
            TextField("rmux session or cmux:surface:N", text: $sessionName.shellSafe)
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
            #if DEBUG
            // `-uiRemote` opens this screen directly. The remote surface cannot be
            // reached by any deep link and the simulator cannot be tapped from CI or
            // from an agent, so without this the one screen whose whole job is aiming
            // accuracy is the one screen nobody can look at.
            if ProcessInfo.processInfo.arguments.contains("-uiRemote"), let first = machines.first {
                RemoteScreenView(machine: first)
            } else {
                machineList
            }
            #else
            machineList
            #endif
        }
    }

    private var machineList: some View {
            List {
                ForEach(machines) { machine in
                    Section(machine.host) {
                        NavigationLink {
                            RemoteScreenView(machine: machine)
                        } label: {
                            Label("Screen & control", systemImage: "display")
                        }
                        .disabled(snap(for: machine)?.reachable != true)
                        // meshd's own web console, kept because it is the only surface
                        // that works when the native one hits something unexpected —
                        // and because it is the same page on any browser.
                        if let desktop = machine.desktopURL() {
                            NavigationLink {
                                RemoteWebScreen(title: machine.host,
                                                urlString: desktop.absoluteString,
                                                bearer: machine.token)
                            } label: {
                                Label("Web console", systemImage: "safari")
                            }
                            .disabled(snap(for: machine)?.reachable != true)
                        }
                        if let snap = snap(for: machine) {
                            ServiceStatusRow(label: "machine", ok: snap.reachable, detail: snap.statusLabel)
                            ServiceStatusRow(label: "input", ok: snap.capabilities?.contains("input"),
                                             detail: (snap.capabilities?.contains("input") ?? false) ? "ready" : "needs meshd 0.2.2")
                        }
                        // Legacy noVNC bridge: only offered where one is actually up.
                        if snap(for: machine)?.vncReachable == true {
                            NavigationLink {
                                RemoteWebScreen(title: "\(machine.host) VNC", urlString: machine.resolvedVNC)
                            } label: {
                                Label("Open VNC", systemImage: "rectangle.on.rectangle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Remote")
            .overlay {
                if machines.isEmpty {
                    ContentUnavailableView("No machines", systemImage: "display",
                                           description: Text("Pair a machine on the Machines tab. No VNC server needed — meshd captures the screen itself."))
                }
            }
    }
}

struct RemoteWebScreen: View {
    let title: String
    let urlString: String
    /// Sent as an Authorization header and injected as window.MESH_TOKEN — meshd
    /// accepts the header only, so the secret never enters a URL.
    var bearer: String? = nil
    @State private var reloadToken = UUID()

    var body: some View {
        Group {
            if let url = URL(string: urlString) {
                ControlWebView(url: url, bearer: bearer, reloadToken: reloadToken)
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
    var bearer: String? = nil
    let reloadToken: UUID

    private func request() -> URLRequest {
        var req = URLRequest(url: url)
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return req
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        if let bearer {
            // The header only covers the main document; the page's own fetches need
            // the token too, so hand it over before any page script runs. Encoded as
            // JSON rather than by stripping characters — stripping changes the token
            // silently, and a quote that slipped through would be script injection.
            let literal = String(data: (try? JSONSerialization.data(withJSONObject: [bearer], options: []))
                                 ?? Data("[\"\"]".utf8), encoding: .utf8) ?? "[\"\"]"
            config.userContentController.addUserScript(
                WKUserScript(source: "window.MESH_TOKEN = \(literal)[0];",
                             injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: config)
        // This webview carries a bearer token in page scope, so it may only ever be on
        // the daemon that issued it. Without this a link in daemon-served HTML could
        // navigate somewhere else and the token would be injected into that page too.
        context.coordinator.allowedOrigin = ControlWebView.origin(of: url)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.minimumZoomScale = 0.25
        web.scrollView.maximumZoomScale = 6
        web.scrollView.bouncesZoom = true
        web.load(request())
        context.coordinator.lastReloadToken = reloadToken
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if web.url != url || context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            web.load(request())
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// scheme://host:port — what "the same machine" means for this webview.
    static func origin(of url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let port = url.port.map(String.init) ?? ""
        return "\(scheme)://\(host):\(port)"
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastReloadToken: UUID?
        var allowedOrigin: String?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
            // about:blank and the like carry no token risk and are how WebKit bootstraps.
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return decisionHandler(.allow)
            }
            guard ControlWebView.origin(of: url) == allowedOrigin else {
                // Off the daemon: hand it to Safari, where no token of ours exists.
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }
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
    guard let date = parseISO(iso) else { return nil }
    return "resets \(date.formatted(date: .abbreviated, time: .shortened))"
}

private func eventTime(_ iso: String) -> String {
    guard let date = parseISO(iso) else { return "" }
    return date.formatted(date: .omitted, time: .shortened)
}

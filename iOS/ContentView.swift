import SwiftUI
import Network

struct ContentView: View {
    @EnvironmentObject var store: MeshStore

    var body: some View {
        TabView {
            MachinesTab().tabItem { Label("Machines", systemImage: "server.rack") }
            TerminalTab().tabItem { Label("Terminal", systemImage: "terminal") }
            RemoteTab().tabItem { Label("Remote", systemImage: "rectangle.on.rectangle") }
            UsageTab().tabItem { Label("Usage", systemImage: "gauge.with.dots.needle.67percent") }
            SettingsTab().tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct MachinesTab: View {
    @EnvironmentObject var store: MeshStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.snapshot?.machines ?? []) { m in
                    Section(header: HStack {
                        Circle().fill(m.reachable ? .green : .secondary).frame(width: 8, height: 8)
                        Text(m.host).font(.headline)
                    }) {
                        if let s = m.stats {
                            StatRow(label: "CPU", value: String(format: "%.0f%%", s.cpuPct))
                            StatRow(label: "Memory", value: String(format: "%.0f / %.0f GB (%.0f%%)", s.mem.usedMB/1024, s.mem.totalMB/1024, s.mem.pct))
                            StatRow(label: "Disk", value: String(format: "%.0f / %.0f GB (%.0f%%)", s.disk.usedGB, s.disk.totalGB, s.disk.pct))
                            StatRow(label: "Load", value: s.load.map { String(format: "%.2f", $0) }.joined(separator: " "))
                            StatRow(label: "Sessions", value: "\(s.agentsCount)")
                        } else {
                            Text("unreachable").foregroundStyle(.secondary)
                        }
                        ForEach(m.agents) { a in
                            HStack {
                                Image(systemName: "terminal")
                                Text(a.name)
                                Spacer()
                                Text(a.agentType ?? "shell").foregroundStyle(.secondary).font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mesh")
            .toolbar {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: store.polling ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
            }
        }
    }
}

private struct UsageTab: View {
    @EnvironmentObject var store: MeshStore

    var body: some View {
        NavigationStack {
            List(store.snapshot?.usage?.providers ?? []) { p in
                Section(header: Text("\(p.displayName)  \(p.plan ?? "")")) {
                    ForEach(p.limits) { l in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(l.label)
                                Spacer()
                                Text(l.usedPct.map { String(format: "%.0f%% used", $0) } ?? "—")
                                    .foregroundStyle(.secondary)
                            }
                            if let pct = l.usedPct {
                                ProgressView(value: min(max(pct/100, 0), 1))
                            }
                        }
                    }
                    if let last30 = p.last30 {
                        StatRow(label: "Last 30d", value: last30)
                    }
                }
            }
            .navigationTitle("Usage")
        }
    }
}

private struct RemoteTab: View {
    @EnvironmentObject var store: MeshStore
    @Environment(\.openURL) private var openURL
    @State private var reachable: [String: Bool] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section("Machines") {
                    ForEach(store.machines) { machine in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(statusColor(for: machine))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(machine.host).font(.headline)
                                    Text("\(machine.ip):5900").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    if let url = machine.vncURL { openURL(url) }
                                } label: {
                                    Label("Open in RealVNC", systemImage: "arrow.up.forward.app")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                Section("RealVNC") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This opens your existing RealVNC Viewer connection over Tailscale.")
                        Text("Turn on Screen Sharing on the Mac in System Settings > General > Sharing. On Raspberry Pi, enable VNC, then keep Tailscale connected.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Remote")
            .task(id: store.machines) { await refreshReachability() }
            .refreshable { await refreshReachability() }
        }
    }

    private func statusColor(for machine: Machine) -> Color {
        guard let ok = reachable[machine.host] else { return .secondary }
        return ok ? .green : .red
    }

    private func refreshReachability() async {
        let machines = store.machines
        var next: [String: Bool] = [:]
        await withTaskGroup(of: (String, Bool).self) { group in
            for machine in machines {
                group.addTask {
                    (machine.host, await vncReachable(ip: machine.ip))
                }
            }
            for await result in group {
                next[result.0] = result.1
            }
        }
        reachable = next
    }
}

private struct SettingsTab: View {
    @EnvironmentObject var store: MeshStore

    var body: some View {
        NavigationStack {
            List {
                ForEach($store.machines) { $m in
                    Section(header: Text(m.host)) {
                        LabeledContent("IP") { TextField("ip", text: $m.ip).multilineTextAlignment(.trailing) }
                        LabeledContent("Port") { TextField("port", value: $m.port, format: .number).multilineTextAlignment(.trailing) }
                        SecureField("token", text: $m.token)
                    }
                }
            }
            .navigationTitle("Machines")
            .toolbar { Button("Save") { store.save(); Task { await store.refresh() } } }
        }
    }
}

private func vncReachable(ip: String) async -> Bool {
    await withCheckedContinuation { continuation in
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: 5900, using: .tcp)
        let queue = DispatchQueue(label: "vnc-\(ip)")
        let probe = VNCProbe(connection: connection, continuation: continuation)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                probe.finish(true)
            case .failed, .cancelled:
                probe.finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { probe.finish(false) }
    }
}

private final class VNCProbe: @unchecked Sendable {
    let connection: NWConnection
    let continuation: CheckedContinuation<Bool, Never>
    private let lock = NSLock()
    private var done = false

    init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ ok: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        connection.cancel()
        continuation.resume(returning: ok)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
    }
}

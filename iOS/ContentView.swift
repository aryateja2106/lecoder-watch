import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: MeshStore

    var body: some View {
        TabView {
            MachinesTab().tabItem { Label("Machines", systemImage: "server.rack") }
            TerminalTab().tabItem { Label("Terminal", systemImage: "terminal") }
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

struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
    }
}

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
            ForEach(store.snaps) { m in
                NavigationLink {
                    SessionsView(host: m.host).environmentObject(store)
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(m.reachable ? .green : .secondary).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shortName(m.host)).font(.headline)
                            if let s = m.stats {
                                Text("CPU \(Int(s.cpuPct))%  ·  \(Int(s.mem.pct))% mem  ·  \(m.agents.count) agt")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text("unreachable").font(.caption2).foregroundStyle(.secondary)
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
        }
        .overlay {
            if store.snaps.isEmpty {
                ProgressView("Connecting…")
            }
        }
    }
}

// MARK: - Sessions on a machine

struct SessionsView: View {
    @EnvironmentObject var store: WatchMeshStore
    let host: String

    private var snap: MachineSnapshot? { store.snaps.first { $0.host == host } }

    var body: some View {
        List {
            if let s = snap?.stats {
                Section {
                    GaugeRow(label: "CPU", value: s.cpuPct, text: "\(Int(s.cpuPct))%")
                    GaugeRow(label: "Mem", value: s.mem.pct, text: "\(Int(s.mem.usedMB/1024))/\(Int(s.mem.totalMB/1024))G")
                    GaugeRow(label: "Disk", value: s.disk.pct, text: "\(Int(s.disk.usedGB))/\(Int(s.disk.totalGB))G")
                }
            }
            Section("Agents") {
                ForEach(snap?.agents ?? []) { a in
                    NavigationLink {
                        AgentLiveView(host: host, agent: a.name).environmentObject(store)
                    } label: {
                        HStack {
                            Image(systemName: "terminal")
                            Text(a.name)
                            Spacer()
                            if a.attached { Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.green) }
                        }
                    }
                }
                if (snap?.agents ?? []).isEmpty {
                    Text("no sessions").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(shortName(host))
    }
}

// MARK: - Live agent view (see + respond)

struct AgentLiveView: View {
    @EnvironmentObject var store: WatchMeshStore
    let host: String
    let agent: String

    @State private var dictation = ""
    @State private var showType = false

    // Approvals + common nudges, sent as text + Enter.
    private let presets = ["yes", "continue", "1", "list files", "git status"]

    var body: some View {
        VStack(spacing: 4) {
            // Live output
            ScrollViewReader { proxy in
                ScrollView {
                    Text(store.output.joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: store.output) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            // Controls
            HStack(spacing: 6) {
                Button { store.send(key: "enter") } label: { Image(systemName: "return") }
                Button(role: .destructive) { store.send(key: "ctrl-c") } label: { Image(systemName: "xmark.octagon") }
                Button { store.send(key: "up") } label: { Image(systemName: "arrow.up") }
                Button { showType = true } label: { Image(systemName: "keyboard") }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .navigationTitle(agent)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.watch(host: host, agent: agent) }
        .onDisappear { store.stopWatching() }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(presets, id: \.self) { p in
                            Button(p) { store.send(text: p + "\n") }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showType) {
            NavigationStack {
                VStack {
                    TextField("Say or scribble…", text: $dictation)
                        .autocorrectionDisabled()
                    Button("Send") {
                        if !dictation.isEmpty { store.send(text: dictation + "\n"); dictation = ""; showType = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(dictation.isEmpty)
                }
                .padding()
                .navigationTitle("To \(agent)")
                .navigationBarTitleDisplayMode(.inline)
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

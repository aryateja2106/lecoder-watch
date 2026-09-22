// AppsLibraryView.swift — every app an agent built for you, across every machine, in one list.
//
// Each daemon knows only the apps published or registered on its own machine (`/built-apps`).
// Until now the phone showed them one machine at a time, three taps deep in the Terminal tab,
// so the same app built three ways on three boxes looked like three unrelated rows nobody
// compared. This screen asks every paired machine at once, groups rows by app name, and
// reuses the exact Open / Install behaviour of the per-machine screen. Reached from the
// Machines tab's library button.
import SwiftUI

struct AppsLibraryView: View {
    @EnvironmentObject var store: MeshStore

    /// One row per (machine, app). Kept flat so a group is just a filter over it.
    struct Entry: Identifiable, Hashable {
        var machine: Machine
        var app: MeshApp
        var id: String { "\(machine.host)/\(app.slug)" }
    }

    @State private var entries: [Entry] = []
    @State private var unreachable: [String] = []
    @State private var loading = false
    @State private var installMessage: String?

    /// Apps with the same display name on several machines sit under one header, newest
    /// first — the "built three ways" case reads as one app with three builds.
    private var groups: [(name: String, entries: [Entry])] {
        let byName = Dictionary(grouping: entries) { $0.app.name }
        return byName
            .map { (name: $0.key, entries: $0.value.sorted { ($0.app.updated) > ($1.app.updated) }) }
            .sorted { ($0.entries.first?.app.updated ?? "") > ($1.entries.first?.app.updated ?? "") }
    }

    var body: some View {
        List {
            Section {
                Text("Less Search. More Agents.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(entries.count) build\(entries.count == 1 ? "" : "s") of \(groups.count) app\(groups.count == 1 ? "" : "s") across \(reachedCount) machine\(reachedCount == 1 ? "" : "s").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if entries.isEmpty && !loading {
                ContentUnavailableView(
                    "No apps yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Ask an agent on any machine to build one — a native app or a web app — and it appears here.")
                )
            }
            ForEach(groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.entries) { entry in
                        MeshAppRow(app: entry.app, host: entry.machine.host, showHost: true,
                                   install: { await install(entry) })
                    }
                }
            }
            if !unreachable.isEmpty {
                Section {
                    Text("Couldn't reach \(unreachable.joined(separator: ", ")).")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if let installMessage {
                Section { Text(installMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Apps")
        .toolbar { if loading { ProgressView().controlSize(.small) } }
        .task { await load() }
        .refreshable { await load() }
    }

    private var reachedCount: Int { store.machines.count - unreachable.count }

    /// Every machine at once; a machine that does not answer is named, never silently dropped.
    private func load() async {
        loading = true
        defer { loading = false }
        var found: [Entry] = []
        var down: [String] = []
        await withTaskGroup(of: (Machine, [MeshApp]?).self) { group in
            for machine in store.machines {
                group.addTask { [store] in
                    (machine, try? await store.client(for: machine).meshApps())
                }
            }
            for await (machine, apps) in group {
                if let apps { found += apps.map { Entry(machine: machine, app: $0) } }
                else { down.append(machine.host) }
            }
        }
        entries = found
        unreachable = down.sorted()
    }

    private func install(_ entry: Entry) async {
        installMessage = await MeshAppRow.install(entry.app, on: entry.machine, via: store)
    }
}

/// The one row for a built app — shared by the fleet library and the per-machine screen.
struct MeshAppRow: View {
    let app: MeshApp
    let host: String
    var showHost: Bool = false
    let install: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.kind == "native" ? "iphone.badge.play" : "globe")
                .foregroundStyle(app.kind == "native" ? Color.blue : Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                Text([kindLabel, showHost ? host : nil, updatedLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if app.kind == "native" {
                Button("Install") { Task { await install() } }
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button("Open") { Self.open(app) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private var updatedLabel: String {
        guard let date = parseISO(app.updated) else { return app.updated }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Tells the user which install route the button will take before they tap it.
    private var kindLabel: String {
        guard app.kind == "native" else { return "Web" }
        return app.install != nil ? "Native · wireless" : "Native · via \(host)"
    }

    static func open(_ app: MeshApp) {
        guard let raw = app.url, let url = URL(string: raw) else { return }
        // Real Safari, not SFSafariViewController: Add to Home Screen only exists there.
        UIApplication.shared.open(url)
    }

    /// Wireless when the machine serves an .ipa over HTTPS (`install` is the itms-services
    /// URL iOS handles itself); otherwise the machine's own devicectl push, which needs the
    /// phone paired and reachable from it. Returns the one line to show the user.
    static func install(_ app: MeshApp, on machine: Machine, via store: MeshStore) async -> String {
        if let raw = app.install, let url = URL(string: raw) {
            let opened = await UIApplication.shared.open(url)
            return opened ? "iOS is asking to install \(app.name)." : "Couldn't open the installer link."
        }
        do {
            let result = try await store.client(for: machine).installMeshApp(slug: app.slug, target: "device")
            return result.ok ? "\(app.name) installed." : (result.error ?? "Install failed.")
        } catch {
            return "Couldn't reach \(machine.host) to install."
        }
    }
}

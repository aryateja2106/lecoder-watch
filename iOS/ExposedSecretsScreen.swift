import SwiftUI

/// Settings → Exposed secrets. meshd 0.6+ ("redact") replaces a token, key or
/// password in event and output text before it ever leaves the machine — but
/// printing it in the first place still means it was on screen, and possibly in a
/// log upstream. This is the ledger of what got caught, fingerprinted rather than
/// stored, so the person can go rotate it at whatever service issued it.
struct ExposedSecretsScreen: View {
    @EnvironmentObject var store: MeshStore
    @State private var host: String = ""
    @State private var exposures: [SecretExposure] = []
    @State private var loading = false
    @State private var loadError: String?

    private var machine: Machine? { store.machines.first { $0.host == host } }

    private var grouped: [(status: String, items: [SecretExposure])] {
        let order = ["open", "rotated", "ignored"]
        let byStatus = Dictionary(grouping: exposures, by: \.status)
        // Newest first within a group — `last` is an ISO8601 string, and that format
        // sorts lexicographically the same as chronologically.
        return order.compactMap { status in
            guard let items = byStatus[status], !items.isEmpty else { return nil }
            return (status, items.sorted { $0.last > $1.last })
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Machine", selection: $host) {
                    Text("Pick a machine").tag("")
                    ForEach(store.machines) { m in
                        Text(m.host).tag(m.host)
                    }
                }
                Text("A secret an agent or terminal printed gets replaced before it leaves this machine, but it was still exposed once — rotate it at whatever service issued it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let machine {
                if !store.client(for: machine).supports("redact") {
                    Section {
                        Text("\(machine.host) runs an agent without secret redaction yet. Re-run the install command on it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let loadError {
                    Section { Text(loadError).font(.caption).foregroundStyle(.orange) }
                } else if exposures.isEmpty && !loading {
                    Section { Text("No secrets caught on this machine.").font(.caption).foregroundStyle(.secondary) }
                }
            }

            ForEach(grouped, id: \.status) { group in
                Section(group.status.capitalized) {
                    ForEach(group.items) { item in
                        ExposureRow(item: item)
                            .swipeActions(edge: .trailing) {
                                if item.status != "ignored" {
                                    Button("Ignore") { Task { await setStatus(item, "ignored") } }
                                        .tint(.gray)
                                }
                                if item.status != "rotated" {
                                    Button("Rotated") { Task { await setStatus(item, "rotated") } }
                                        .tint(.green)
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Exposed secrets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if loading { ProgressView().controlSize(.small) }
        }
        .onAppear { if host.isEmpty { host = store.machines.first?.host ?? "" } }
        .task(id: host) { await load() }
    }

    private func load() async {
        guard let machine, store.client(for: machine).supports("redact") else {
            exposures = []
            return
        }
        loading = true
        defer { loading = false }
        do {
            exposures = try await store.client(for: machine).exposures().items
            loadError = nil
        } catch {
            loadError = "Couldn't reach \(machine.host)."
        }
    }

    private func setStatus(_ item: SecretExposure, _ status: String) async {
        guard let machine else { return }
        if let updated = try? await store.client(for: machine).setExposureStatus(item.fp, status: status),
           let idx = exposures.firstIndex(where: { $0.fp == updated.fp }) {
            exposures[idx] = updated
        }
    }
}

private struct ExposureRow: View {
    let item: SecretExposure

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.kind.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("×\(item.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(item.hint)••••••[\(item.fp)]")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let lastSeen = parseISO(item.last) {
                    Text(lastSeen, format: .relative(presentation: .named))
                } else {
                    Text(item.last)
                }
                if !item.channels.isEmpty {
                    Text("·")
                    Text(item.channels.joined(separator: ", "))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

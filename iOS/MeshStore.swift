import Foundation
import Combine

/// iPhone-side brain: persists the machine list, polls every machine's meshd
/// concurrently, builds the snapshot for the UI, and relays it to the watch.
@MainActor
final class MeshStore: ObservableObject {
    @Published var machines: [Machine] = []
    @Published var snapshot: MeshSnapshot?
    @Published var lastError: String?
    @Published var polling = false

    private var timer: Timer?
    private let defaultsKey = "mesh.machines.v1"
    // The agent the watch asked us to relay live output for.
    private var watchedHost: String?
    private var watchedAgent: String?

    init() {
        load()
        PhoneConnectivity.shared.commandHandler = { [weak self] cmd in
            await self?.handle(cmd)
        }
    }

    // MARK: Persistence

    func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Machine].self, from: data),
           !decoded.isEmpty {
            machines = decoded
        } else {
            machines = Machine.defaults
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(machines) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func update(_ machine: Machine) {
        if let idx = machines.firstIndex(where: { $0.id == machine.id }) {
            machines[idx] = machine
        } else {
            machines.append(machine)
        }
        save()
    }

    // MARK: Polling

    func start() {
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        polling = true
        defer { polling = false }
        let targets = machines
        var results: [MachineSnapshot] = []
        await withTaskGroup(of: MachineSnapshot.self) { group in
            for machine in targets {
                group.addTask {
                    let client = MeshClient(machine: machine)
                    async let statsResult = try? await client.stats()
                    async let agentsResult = try? await client.agents()
                    let stats = await statsResult
                    let agents = await agentsResult ?? []
                    return MachineSnapshot(host: machine.host,
                                           reachable: stats != nil,
                                           stats: stats,
                                           agents: agents)
                }
            }
            for await snap in group { results.append(snap) }
        }
        // Stable order matching the machine list.
        let ordered = targets.compactMap { m in results.first { $0.host == m.host } }

        var usage: UsageSnapshot?
        if let mac = targets.first(where: { $0.host.contains("macbook") }) {
            usage = try? await MeshClient(machine: mac).usage()
        }

        // Relay live output for whatever agent the watch is watching.
        var watchedOutput: [String]?
        if let host = watchedHost, let agent = watchedAgent,
           let m = targets.first(where: { $0.host == host }) {
            watchedOutput = (try? await MeshClient(machine: m).output(agent: agent, lines: 60))?.lines
        }

        let snap = MeshSnapshot(updatedISO: ISO8601DateFormatter().string(from: Date()),
                                machines: ordered,
                                usage: usage,
                                watchedHost: watchedHost,
                                watchedAgent: watchedAgent,
                                watchedOutput: watchedOutput)
        snapshot = snap
        PhoneConnectivity.shared.push(snap)
        NotificationManager.shared.evaluate(snap)
    }

    // MARK: Sessions

    /// Create a new rmux session on a machine, then refresh so it appears in the list.
    func newSession(on machine: Machine, name: String, cmd: String?) async {
        do {
            try await MeshClient(machine: machine).newSession(name: name, cmd: cmd)
            await refresh()
        } catch {
            lastError = "create session failed: \(error)"
        }
    }

    // MARK: Watch commands

    func handle(_ command: WatchCommand) async {
        switch command.kind {
        case .refresh:
            await refresh()
        case .agentSend:
            guard let host = command.host, let agent = command.agent,
                  let machine = machines.first(where: { $0.host == host }) else { return }
            try? await MeshClient(machine: machine).send(agent: agent, text: command.text, key: command.key)
        case .agentOutput:
            // Watch asked to watch (or stop watching) an agent's live output.
            watchedHost = command.host
            watchedAgent = command.agent
            await refresh()
        case .newAgent:
            break
        }
    }
}

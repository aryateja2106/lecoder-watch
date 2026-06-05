import Foundation
import Combine

/// Watch brain. Two private paths to the mesh:
///  1. DIRECT — talk to each machine's meshd over the tailnet. Works in the
///     simulator and whenever the watch can reach the host. Fast (1.5s output).
///  2. RELAY — when a machine isn't directly reachable (a real watch off the
///     tailnet), fall back to the paired iPhone, which polls meshd (incl. the
///     watched agent's output) and pushes snapshots over WatchConnectivity.
/// The UI reads merged state, so it just works whichever path is live.
@MainActor
final class WatchMeshStore: ObservableObject {
    @Published var machines: [Machine] = Machine.defaults
    @Published private var directSnaps: [MachineSnapshot] = []
    @Published private var relayed: MeshSnapshot?
    @Published var usage: UsageSnapshot?
    @Published var watching: WatchTarget?
    @Published private var directOutput: [String] = []
    @Published var sending = false
    @Published var phoneReachable = false

    struct WatchTarget: Equatable { let host: String; let agent: String }

    /// Merged machines: prefer direct when reachable, else the relayed snapshot.
    var snaps: [MachineSnapshot] {
        machines.map { m in
            if let d = directSnaps.first(where: { $0.host == m.host }), d.reachable { return d }
            if let r = relayed?.machines.first(where: { $0.host == m.host }) { return r }
            return directSnaps.first(where: { $0.host == m.host })
                ?? MachineSnapshot(host: m.host, reachable: false, stats: nil, agents: [])
        }
    }

    /// Effective usage (direct mac poll, else relayed).
    var effectiveUsage: UsageSnapshot? { usage ?? relayed?.usage }

    /// Watched agent output: direct if its host is directly reachable, else relayed.
    var output: [String] {
        guard let w = watching else { return [] }
        if directReachable(w.host) { return directOutput }
        if relayed?.watchedHost == w.host, relayed?.watchedAgent == w.agent {
            return relayed?.watchedOutput ?? []
        }
        return directOutput
    }

    private func directReachable(_ host: String) -> Bool {
        directSnaps.first(where: { $0.host == host })?.reachable == true
    }

    private var pollTask: Task<Void, Never>?
    private var outputTask: Task<Void, Never>?

    func start() {
        // Wire the relay.
        WatchLink.shared.onSnapshot = { [weak self] snap in
            Task { @MainActor in self?.relayed = snap }
        }
        WatchLink.shared.onReachable = { [weak self] r in
            Task { @MainActor in self?.phoneReachable = r }
        }
        WatchLink.shared.activate()

        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }

    func refresh() async {
        let targets = machines
        var results: [MachineSnapshot] = []
        await withTaskGroup(of: MachineSnapshot.self) { group in
            for m in targets {
                group.addTask {
                    let c = MeshClient(machine: m)
                    let stats = try? await c.stats()
                    let agents = (try? await c.agents()) ?? []
                    return MachineSnapshot(host: m.host, reachable: stats != nil, stats: stats, agents: agents)
                }
            }
            for await s in group { results.append(s) }
        }
        directSnaps = targets.compactMap { m in results.first { $0.host == m.host } }
        if let mac = targets.first(where: { $0.host.contains("macbook") }) {
            usage = try? await MeshClient(machine: mac).usage()
        }
    }

    // MARK: Watch a single agent

    func watch(host: String, agent: String) {
        watching = WatchTarget(host: host, agent: agent)
        directOutput = []
        // Ask the phone to relay this agent's output too (used if direct fails).
        WatchLink.shared.send(WatchCommand(kind: .agentOutput, host: host, agent: agent, text: nil, key: nil))
        outputTask?.cancel()
        outputTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOutput()
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    func stopWatching() {
        outputTask?.cancel(); outputTask = nil
        WatchLink.shared.send(WatchCommand(kind: .agentOutput, host: nil, agent: nil, text: nil, key: nil))
        watching = nil
    }

    private func pollOutput() async {
        guard let w = watching, directReachable(w.host),
              let m = machines.first(where: { $0.host == w.host }) else { return }
        if let out = try? await MeshClient(machine: m).output(agent: w.agent, lines: 60) {
            directOutput = out.lines
        }
    }

    // MARK: Send — direct if reachable, else via the phone relay.

    func send(text: String? = nil, key: String? = nil) {
        guard let w = watching else { return }
        if directReachable(w.host), let m = machines.first(where: { $0.host == w.host }) {
            sending = true
            Task {
                try? await MeshClient(machine: m).send(agent: w.agent, text: text, key: key)
                try? await Task.sleep(for: .milliseconds(300))
                await pollOutput()
                sending = false
            }
        } else {
            WatchLink.shared.send(WatchCommand(kind: .agentSend, host: w.host, agent: w.agent, text: text, key: key))
        }
    }
}

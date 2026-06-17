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
    @Published var lastError: String?

    struct WatchTarget: Equatable { let host: String; let agent: String; let pane: String? }
    static let defaultQuickCommands = ["continue", "git status", "pwd", "ls", "cd ..", "clear", "~/.mesh/bin/mesh-self-check"]

    /// Merged machines: prefer direct when reachable, else the relayed snapshot.
    var snaps: [MachineSnapshot] {
        machines.map { m in
            if let d = directSnaps.first(where: { $0.host == m.host }), d.reachable, d.authError == nil { return d }
            if let r = relayed?.machines.first(where: { $0.host == m.host }) { return r }
            return directSnaps.first(where: { $0.host == m.host })
                ?? MachineSnapshot(host: m.host, reachable: false, stats: nil, agents: [])
        }
    }

    /// Effective usage (direct mac poll, else relayed).
    var effectiveUsage: UsageSnapshot? { usage ?? relayed?.usage }

    var events: [AgentEvent] { relayed?.events ?? [] }

    var quickCommands: [String] {
        let commands = relayed?.quickCommands ?? []
        return commands.isEmpty ? Self.defaultQuickCommands : commands
    }

    /// Watched agent output: direct if its host is directly reachable, else relayed.
    var output: [String] {
        guard let w = watching else { return [] }
        if directReachable(w.host) { return directOutput }
        if relayed?.watchedHost == w.host, relayed?.watchedAgent == w.agent, relayed?.watchedPane == w.pane {
            return relayed?.watchedOutput ?? []
        }
        return directOutput
    }

    private func directReachable(_ host: String) -> Bool {
        guard let snap = directSnaps.first(where: { $0.host == host }) else { return false }
        return snap.reachable && snap.authError == nil
    }

    private nonisolated static func isAuthError(_ error: Error) -> Bool {
        if case MeshClient.MeshError.http(let code) = error {
            return code == 401 || code == 403
        }
        return false
    }

    func routeLabel(for host: String) -> String {
        if directReachable(host) { return "direct" }
        if relayed?.machines.contains(where: { $0.host == host && $0.reachable }) == true {
            return phoneReachable ? "phone relay" : "phone snapshot"
        }
        return phoneReachable ? "phone ready" : "offline"
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
                    let health = try? await c.healthInfo()
                    var authError: String?
                    var stats: Stats?
                    do {
                        stats = try await c.stats()
                    } catch {
                        if Self.isAuthError(error) { authError = "token rejected" }
                    }
                    var agents: [Agent] = []
                    do {
                        agents = try await c.agents()
                    } catch {
                        if Self.isAuthError(error) { authError = "token rejected" }
                    }
                    for idx in agents.indices {
                        agents[idx].panes = try? await c.panes(agent: agents[idx].name)
                    }
                    return MachineSnapshot(host: m.host,
                                           reachable: stats != nil || health?.ok == true,
                                           stats: stats,
                                           agents: agents,
                                           authError: authError,
                                           meshdVersion: health?.meshdVersion,
                                           capabilities: health?.capabilities)
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

    func watch(host: String, agent: String, pane: String? = nil) {
        watching = WatchTarget(host: host, agent: agent, pane: pane)
        directOutput = []
        // Ask the phone to relay this agent's output too (used if direct fails).
        WatchLink.shared.send(WatchCommand(kind: .agentOutput, host: host, agent: agent, text: nil, key: nil, pane: pane))
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
        if let out = try? await MeshClient(machine: m).output(agent: w.agent, lines: 60, pane: w.pane) {
            directOutput = out.lines
        }
    }

    // MARK: Send — direct if reachable, else via the phone relay.

    func send(text: String? = nil, key: String? = nil) {
        guard let w = watching else { return }
        if directReachable(w.host), let m = machines.first(where: { $0.host == w.host }) {
            sending = true
            lastError = nil
            Task {
                do {
                    try await MeshClient(machine: m).send(agent: w.agent, text: text, key: key, pane: w.pane)
                } catch {
                    lastError = "send failed"
                }
                try? await Task.sleep(for: .milliseconds(300))
                await pollOutput()
                sending = false
            }
        } else {
            WatchLink.shared.send(WatchCommand(kind: .agentSend, host: w.host, agent: w.agent, text: text, key: key, pane: w.pane))
        }
    }

    func newSession(host: String, cmd: String?, initialText: String? = nil) {
        let name = watchSessionName(cmd)
        if directReachable(host), let m = machines.first(where: { $0.host == host }) {
            lastError = nil
            Task {
                do {
                    try await MeshClient(machine: m).newSession(name: name, cmd: cmd, initialText: initialText)
                } catch {
                    lastError = "new session failed"
                }
                await refresh()
            }
        } else {
            WatchLink.shared.send(WatchCommand(kind: .newAgent, host: host, agent: nil, text: name, key: nil, cmd: cmd, initialText: initialText))
        }
    }

    func newTask(host: String, agent: String, task: String) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newSession(host: host, cmd: agent, initialText: trimmed + "\n")
    }

    func newPane(host: String, agent: String) {
        if directReachable(host), let m = machines.first(where: { $0.host == host }) {
            lastError = nil
            Task {
                do {
                    try await MeshClient(machine: m).newPane(agent: agent)
                } catch {
                    lastError = "new pane failed"
                }
                await refresh()
            }
        } else {
            WatchLink.shared.send(WatchCommand(kind: .newPane, host: host, agent: agent, text: nil, key: nil))
        }
    }

    func killSession(host: String, agent: String) {
        stopWatching()
        if directReachable(host), let m = machines.first(where: { $0.host == host }) {
            lastError = nil
            Task {
                do {
                    try await MeshClient(machine: m).kill(agent: agent)
                } catch {
                    lastError = "kill failed"
                }
                await refresh()
            }
        } else {
            WatchLink.shared.send(WatchCommand(kind: .killAgent, host: host, agent: agent, text: nil, key: nil))
        }
    }

    func killPane(host: String, agent: String, pane: String) {
        if watching?.pane == pane {
            watching = WatchTarget(host: host, agent: agent, pane: nil)
        }
        if directReachable(host), let m = machines.first(where: { $0.host == host }) {
            lastError = nil
            Task {
                do {
                    try await MeshClient(machine: m).killPane(agent: agent, paneId: pane)
                } catch {
                    lastError = "kill pane failed"
                }
                await refresh()
            }
        } else {
            WatchLink.shared.send(WatchCommand(kind: .killPane, host: host, agent: agent, text: nil, key: nil, pane: pane))
        }
    }

    private func watchSessionName(_ cmd: String?) -> String {
        let raw = cmd?.split(separator: " ").first.map(String.init) ?? "shell"
        let prefix = raw.replacingOccurrences(of: " ", with: "-").lowercased()
        return "watch-\(prefix)-\(Int(Date().timeIntervalSince1970) % 100000)"
    }
}

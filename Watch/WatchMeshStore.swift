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
    @Published var machines: [Machine] = []   // filled from the phone, or the cache
    @Published private var directSnaps: [MachineSnapshot] = []
    @Published private var relayed: MeshSnapshot?
    @Published var usage: UsageSnapshot?
    @Published var watching: WatchTarget?
    @Published private var directOutput: [String] = []
    @Published var sending = false
    @Published var phoneReachable = false
    @Published var lastError: String?
    @Published var screenHost: String?
    @Published var screenJPEGData: Data?
    @Published var screenUpdatedISO: String?
    @Published var screenError: String?

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

    var pinnedLimitSessions: [PinnedLimitSession] {
        relayed?.pinnedLimitSessions ?? []
    }

    func isProviderBlocked(_ providerId: String) -> Bool {
        guard let provider = effectiveUsage?.providers.first(where: { $0.id.lowercased() == providerId.lowercased() }) else { return false }
        if let sessionLimit = provider.limits.first(where: { LimitHelpers.isSessionLimit(label: $0.label) }) {
            return LimitHelpers.isBlocked(sessionLimit)
        }
        return provider.limits.contains { LimitHelpers.isBlocked($0) }
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
        if !shouldTryDirect(host), relayed?.machines.contains(where: { $0.host == host && $0.reachable }) == true {
            return "via phone"
        }
        if relayed?.machines.contains(where: { $0.host == host && $0.reachable }) == true {
            return phoneReachable ? "phone relay" : "phone snapshot"
        }
        return phoneReachable ? "phone ready" : "offline"
    }

    private var pollTask: Task<Void, Never>?
    private var outputTask: Task<Void, Never>?
    /// A watch off the tailnet can never reach these hosts, and finding that out costs
    /// a timeout per address per poll. Once a host fails, stop asking for a while.
    private var directBlockedUntil: [String: Date] = [:]
    private static let directBackoff: TimeInterval = 60

    private func shouldTryDirect(_ host: String) -> Bool {
        guard let until = directBlockedUntil[host] else { return true }
        return Date() >= until
    }

    private func noteDirect(host: String, ok: Bool) {
        if ok {
            directBlockedUntil[host] = nil
        } else {
            directBlockedUntil[host] = Date().addingTimeInterval(Self.directBackoff)
        }
    }

    /// Adopt the phone's machine list — addresses, ports and, critically, current
    /// tokens. The watch's compiled-in defaults go stale the moment a token is
    /// rotated on the Mac, and a 401 quietly demotes every screen to the slow relay.
    private func adoptConfigs(from snap: MeshSnapshot) {
        let configs = snap.machines.compactMap(\.config)
        guard !configs.isEmpty else { return }
        var merged = machines
        var changed = false
        for config in configs {
            if let idx = merged.firstIndex(where: { $0.host == config.host }) {
                if merged[idx] != config { merged[idx] = config; changed = true }
            } else {
                merged.append(config); changed = true
            }
        }
        guard changed else { return }
        machines = merged
        if let data = try? JSONEncoder().encode(merged) {
            // Survive relaunch: the watch app often opens before the phone answers.
            UserDefaults.standard.set(data, forKey: Self.machinesKey)
        }
        Task { await refresh() }
    }

    private static let machinesKey = "watch.machines.v1"

    private func loadCachedMachines() {
        guard let data = UserDefaults.standard.data(forKey: Self.machinesKey),
              let cached = try? JSONDecoder().decode([Machine].self, from: data),
              !cached.isEmpty else { return }
        machines = cached
    }

    func start() {
        loadCachedMachines()
        // Wire the relay.
        WatchLink.shared.onSnapshot = { [weak self] snap in
            Task { @MainActor in
                self?.relayed = snap
                self?.adoptConfigs(from: snap)
            }
            Task { @MainActor in
                guard let self, snap.screenHost == self.screenHost else { return }
                self.screenJPEGData = snap.screenJPEGData
                self.screenUpdatedISO = snap.screenFetchedISO
                self.screenError = snap.screenError
            }
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

    /// Ask the phone for a fresh snapshot and apply its reply.
    ///
    /// This is the watch's real route to the mesh: it has no Tailscale of its own, and
    /// iOS suspends the phone app within seconds of it leaving the foreground, so
    /// nothing arrives unless the watch asks. sendMessage relaunches the phone app in
    /// the background, and the reply carries the snapshot — more reliable than waiting
    /// on updateApplicationContext, which is best-effort and rate-limited.
    private func pullFromPhone() async {
        let command = WatchCommand(kind: .refresh, host: nil, agent: nil, text: nil, key: nil)
        guard let data = await WatchLink.shared.request(command, timeout: 10),
              let snap = try? JSONDecoder().decode(MeshSnapshot.self, from: data) else {
            WatchLink.shared.send(command)   // queue it; the phone answers next time
            return
        }
        relayed = snap
        adoptConfigs(from: snap)
    }

    func refresh() async {
        // Run both routes at once so a slow phone does not delay a direct poll, and a
        // dead direct path does not delay the phone.
        async let phone: Void = pullFromPhone()

        let targets = machines
        let skip = Set(targets.map(\.host).filter { !shouldTryDirect($0) })
        var results: [MachineSnapshot] = []
        await withTaskGroup(of: MachineSnapshot.self) { group in
            for m in targets where !skip.contains(m.host) {
                group.addTask {
                    let c = MeshClient(machine: m)
                    let health = try? await c.healthInfo()
                    guard health?.ok == true else {
                        return MachineSnapshot(host: m.host, reachable: false, stats: nil, agents: [], error: "unreachable")
                    }
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
        for snap in results {
            noteDirect(host: snap.host, ok: snap.reachable && snap.authError == nil)
        }
        // Hosts we skipped keep their last direct result rather than flapping to
        // "unreachable" — the relayed snapshot is what the UI shows for them anyway.
        directSnaps = targets.compactMap { m in
            results.first { $0.host == m.host } ?? directSnaps.first { $0.host == m.host }
        }
        if let mac = targets.first(where: { $0.host.contains("macbook") }), shouldTryDirect(mac.host) {
            usage = try? await MeshClient(machine: mac).usage()
        }
        await phone
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

    /// Answer an agent from a notification button. The host comes from the APNs
    /// payload, so it is the name the *daemon* uses; our stored name may be the key
    /// from another machine's hosts.json, hence the tolerant match.
    func respondToAgent(host: String, session: String, text: String?, key: String?) {
        let match = machineMatching(host, in: machines)
        if let m = match, directReachable(m.host) {
            lastError = nil
            Task {
                do { try await MeshClient(machine: m).send(agent: session, text: text, key: key) }
                catch { lastError = "reply failed" }
                await refresh()
            }
        } else {
            // Off the tailnet, or the machine is not in our list yet: the phone has both.
            WatchLink.shared.send(WatchCommand(kind: .agentSend, host: match?.host ?? host,
                                               agent: session, text: text, key: key))
        }
    }

    /// Send `continue` to a limit-pinned session (resume-at-reset from the wrist).
    func sendToPinned(_ pin: PinnedLimitSession) {
        if directReachable(pin.host), let m = machines.first(where: { $0.host == pin.host }) {
            lastError = nil
            Task {
                do {
                    try await MeshClient(machine: m).send(agent: pin.sessionName, text: "continue\n")
                } catch {
                    lastError = "resume failed"
                }
            }
        } else {
            WatchLink.shared.send(WatchCommand(kind: .agentSend, host: pin.host, agent: pin.sessionName, text: "continue\n", key: nil))
        }
    }

    @discardableResult
    func newSession(host: String, cmd: String?, initialText: String? = nil) -> String {
        let name = watchSessionName(cmd)
        if directReachable(host), let m = machines.first(where: { $0.host == host }) {
            lastError = nil
            Task {
                do {
                    try await MeshClient(machine: m).newSession(name: name, cmd: cmd, initialText: initialText)
                    watch(host: host, agent: name)
                } catch {
                    lastError = "new session failed"
                }
                await refresh()
            }
        } else {
            WatchLink.shared.send(WatchCommand(kind: .newAgent, host: host, agent: nil, text: name, key: nil, cmd: cmd, initialText: initialText))
            watch(host: host, agent: name)
        }
        return name
    }

    @discardableResult
    func newTask(host: String, agent: String, task: String) -> String? {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return newSession(host: host, cmd: agent, initialText: trimmed + "\n")
    }

    func requestScreen(host: String, display: Int? = nil) {
        screenHost = host
        screenError = nil
        if directReachable(host), let m = machines.first(where: { $0.host == host }) {
            Task {
                do {
                    screenJPEGData = try await MeshClient(machine: m).screenImage(display: display)
                    screenUpdatedISO = ISO8601DateFormatter().string(from: Date())
                } catch {
                    screenError = "screen unavailable"
                    WatchLink.shared.send(WatchCommand(kind: .screenPeek, host: host, agent: nil, text: nil, key: nil, display: display))
                }
            }
        } else {
            screenJPEGData = nil
            WatchLink.shared.send(WatchCommand(kind: .screenPeek, host: host, agent: nil, text: nil, key: nil, display: display))
        }
    }

    func stopScreen() {
        if screenHost != nil {
            WatchLink.shared.send(WatchCommand(kind: .screenPeek, host: nil, agent: nil, text: nil, key: nil))
        }
        screenHost = nil
        screenJPEGData = nil
        screenUpdatedISO = nil
        screenError = nil
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

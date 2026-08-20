import Foundation
import Combine

/// iPhone-side brain: persists the machine list, polls every machine's meshd
/// concurrently, builds the snapshot for the UI, and relays it to the watch.
@MainActor
final class MeshStore: ObservableObject {
    @Published var machines: [Machine] = []
    @Published var quickCommands: [String] = MeshStore.defaultQuickCommands
    @Published var pinnedLimitSessions: [PinnedLimitSession] = []
    @Published var snapshot: MeshSnapshot?
    @Published var events: [AgentEvent] = []
    @Published var lastError: String?
    @Published var polling = false

    private var timer: Timer?
    private let defaultsKey = "mesh.machines.v1"
    private let installTokenKey = "mesh.installToken.v1"
    private let quickCommandsKey = "mesh.quickCommands.v1"
    private let pinnedLimitsKey = "mesh.pinnedLimits.v1"
    private let tombstonesKey = "mesh.deletedDefaults.v1"
    static let defaultQuickCommands = ["continue", "git status", "pwd", "ls", "cd ..", "clear", "~/.mesh/bin/mesh-self-check"]
    // The agent the watch asked us to relay live output for.
    private var watchedHost: String?
    private var watchedAgent: String?
    private var watchedPane: String?
    private var watchedScreenHost: String?
    private var watchedScreenDisplay: Int?
    /// Last poll where a host actually answered, so a missed poll degrades to "last
    /// seen 12s ago" instead of wiping the machine — including the buttons that let
    /// you do anything about it, which are disabled while it reads unreachable.
    private var lastGood: [String: (snapshot: MachineSnapshot, at: Date)] = [:]
    private var missesByHost: [String: Int] = [:]
    private static let missesBeforeOffline = 3
    private var lastEventISOByHost: [String: String] = [:]
    private var initializedEventHosts = Set<String>()

    init() {
        load()
        PhoneConnectivity.shared.commandHandler = { [weak self] cmd in
            await self?.handle(cmd)
        }
    }

    // MARK: Persistence

    func load() {
        var changed = false
        let tombstoned = Set(UserDefaults.standard.stringArray(forKey: tombstonesKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Machine].self, from: data),
           !decoded.isEmpty {
            machines = Self.mergedDefaultMachines(decoded, tombstoned: tombstoned)
            changed = machines != decoded
        } else {
            machines = Machine.defaults.filter { !tombstoned.contains($0.host) }
        }
        // (Removed: the old code reset the three default hosts back to the shared
        // "testtoken" whenever their token matched the generated install token. That
        // shared secret is retired — resurrecting it would undo a rotation.)
        if changed { save() }
        if let decoded = UserDefaults.standard.stringArray(forKey: quickCommandsKey), !decoded.isEmpty {
            quickCommands = Self.mergedQuickCommands(decoded)
            UserDefaults.standard.set(quickCommands, forKey: quickCommandsKey)
        }
        if let data = UserDefaults.standard.data(forKey: pinnedLimitsKey),
           let decoded = try? JSONDecoder().decode([PinnedLimitSession].self, from: data) {
            pinnedLimitSessions = decoded
        }
    }

    private static func mergedDefaultMachines(_ saved: [Machine], tombstoned: Set<String>) -> [Machine] {
        var machines = Machine.defaults
            .filter { !tombstoned.contains($0.host) }
            .map { fallback in saved.first { $0.host == fallback.host } ?? fallback }
        for machine in saved where !machines.contains(where: { $0.host == machine.host }) {
            machines.append(machine)
        }
        return machines
    }

    /// Delete machines and, for dogfood defaults, tombstone the host so the merge on the
    /// next launch does not resurrect it.
    func deleteMachines(atOffsets offsets: IndexSet) {
        let defaultHosts = Set(Machine.defaults.map { $0.host })
        var tombstoned = Set(UserDefaults.standard.stringArray(forKey: tombstonesKey) ?? [])
        for idx in offsets where defaultHosts.contains(machines[idx].host) {
            tombstoned.insert(machines[idx].host)
        }
        UserDefaults.standard.set(Array(tombstoned), forKey: tombstonesKey)
        machines.remove(atOffsets: offsets)
        save()
    }

    func installToken() -> String {
        if let saved = UserDefaults.standard.string(forKey: installTokenKey), !saved.isEmpty {
            return saved
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(token, forKey: installTokenKey)
        return token
    }

    private static func mergedQuickCommands(_ saved: [String]) -> [String] {
        var commands = saved
        for command in defaultQuickCommands where !commands.contains(command) {
            commands.append(command)
        }
        return commands
    }

    func save() {
        if let data = try? JSONEncoder().encode(machines) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        UserDefaults.standard.set(quickCommands, forKey: quickCommandsKey)
        if let data = try? JSONEncoder().encode(pinnedLimitSessions) {
            UserDefaults.standard.set(data, forKey: pinnedLimitsKey)
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

    func addMachine() {
        machines.append(Machine(host: "new-machine", ip: "", port: 8899, token: installToken()))
        save()
    }

    // MARK: Push

    /// Fan the APNs device token out to every configured machine; each meshd
    /// stores it and pushes alerts directly. Failures are fine — offline hosts
    /// get the token next launch.
    func uploadPushToken(_ token: String) async {
        for machine in machines {
            try? await MeshClient(machine: machine).registerPush(deviceToken: token)
        }
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
                    var stats: Stats?
                    var health: HealthInfo?
                    var tailnetPeers: [TailnetPeer]?
                    var tailnetError: String?
                    var errorText: String?
                    var authError: String?
                    do {
                        health = try await client.healthInfo()
                    } catch {
                        errorText = Self.describe(error)
                    }
                    guard health?.ok == true else {
                        return MachineSnapshot(host: machine.host,
                                               config: machine,
                                               reachable: false,
                                               stats: nil,
                                               agents: [],
                                               error: errorText ?? "unreachable")
                    }
                    do {
                        stats = try await client.stats()
                    } catch {
                        errorText = Self.describe(error)
                        if Self.isAuthError(error) { authError = "token rejected" }
                    }
                    do {
                        let tailnet = try await client.tailnet()
                        if tailnet.ok {
                            tailnetPeers = tailnet.peers
                        } else {
                            tailnetError = tailnet.error ?? "not available"
                        }
                    } catch {
                        tailnetError = Self.describe(error)
                    }
                    async let bridge = Self.probe(machine.resolvedBridge)
                    async let vnc = Self.probe(machine.resolvedVNC)
                    let bridgeStatus = await bridge
                    let vncStatus = await vnc
                    var agents: [Agent] = []
                    do {
                        agents = try await client.agents()
                    } catch {
                        if Self.isAuthError(error) { authError = "token rejected" }
                    }
                    // Concurrently: one round trip of latency instead of one per agent.
                    // Over a relay this was the difference between a 1s and a 6s poll.
                    await withTaskGroup(of: (Int, [Pane]?).self) { paneGroup in
                        for idx in agents.indices {
                            let name = agents[idx].name
                            paneGroup.addTask { (idx, try? await client.panes(agent: name)) }
                        }
                        for await (idx, panes) in paneGroup { agents[idx].panes = panes }
                    }
                    let reachable = stats != nil || health?.ok == true
                    return MachineSnapshot(host: machine.host,
                                           config: machine,
                                           reachable: reachable,
                                           stats: stats,
                                           agents: agents,
                                           error: reachable ? nil : errorText,
                                           authError: authError,
                                           bridgeReachable: bridgeStatus.ok,
                                           bridgeError: bridgeStatus.error,
                                           vncReachable: vncStatus.ok,
                                           vncError: vncStatus.error,
                                           meshdVersion: health?.meshdVersion,
                                           capabilities: health?.capabilities,
                                           tailnetPeers: tailnetPeers,
                                           tailnetError: tailnetError)
                }
            }
            // Publish each machine the moment it answers. Waiting for the whole group
            // means the slowest host sets first paint, and one host that has been off
            // for days (two addresses x the full timeout) held the entire UI on
            // "checking…" — with every control disabled behind it.
            for await snap in group {
                results.append(snap)
                publishPartial(results, targets: targets)
            }
        }
        // Stable order matching the machine list.
        let ordered = targets.compactMap { m in results.first { $0.host == m.host } }
            .map { holdRecentlyGood($0) }

        var usage: UsageSnapshot?
        for machine in targets {
            guard let fetched = try? await MeshClient(machine: machine).usage(),
                  !fetched.providers.isEmpty else { continue }
            usage = fetched
            break
        }

        // Relay live output for whatever agent the watch is watching.
        var watchedOutput: [String]?
        if let host = watchedHost, let agent = watchedAgent,
           let m = targets.first(where: { $0.host == host }) {
            watchedOutput = (try? await MeshClient(machine: m).output(agent: agent, lines: 60, pane: watchedPane))?.lines
        }
        var screenJPEGData: Data?
        var screenError: String?
        if let host = watchedScreenHost,
           let m = targets.first(where: { $0.host == host }) {
            do {
                screenJPEGData = try await MeshClient(machine: m).screenImage(display: watchedScreenDisplay)
            } catch {
                screenError = Self.describe(error)
            }
        }
        await refreshEvents(from: targets)

        let now = ISO8601DateFormatter().string(from: Date())
        let snap = MeshSnapshot(updatedISO: now,
                                machines: ordered,
                                usage: usage,
                                quickCommands: quickCommands,
                                events: events,
                                screenHost: watchedScreenHost,
                                screenFetchedISO: screenJPEGData == nil ? nil : now,
                                screenJPEGData: screenJPEGData,
                                screenError: screenError,
                                watchedHost: watchedHost,
                                watchedAgent: watchedAgent,
                                watchedPane: watchedPane,
                                watchedOutput: watchedOutput,
                                pinnedLimitSessions: pinnedLimitSessions)
        snapshot = snap
        PhoneConnectivity.shared.push(snap)
        NotificationManager.shared.evaluate(snap, pinned: pinnedLimitSessions)
    }

    /// Emit a snapshot containing the hosts that have answered so far, with the rest
    /// carrying whatever we last knew, so the list fills in progressively.
    private func publishPartial(_ answered: [MachineSnapshot], targets: [Machine]) {
        let byHost = Dictionary(uniqueKeysWithValues: answered.map { ($0.host, $0) })
        let merged = targets.map { machine -> MachineSnapshot in
            if let fresh = byHost[machine.host] { return holdRecentlyGood(fresh) }
            if let remembered = lastGood[machine.host] {
                var held = remembered.snapshot
                held.staleSeconds = max(1, Int(Date().timeIntervalSince(remembered.at)))
                return held
            }
            return MachineSnapshot(host: machine.host, config: machine, reachable: false,
                                   stats: nil, agents: [], error: "checking…")
        }
        snapshot = MeshSnapshot(updatedISO: ISO8601DateFormatter().string(from: Date()),
                                machines: merged,
                                usage: snapshot?.usage,
                                quickCommands: quickCommands,
                                events: events,
                                pinnedLimitSessions: pinnedLimitSessions)
        PhoneConnectivity.shared.push(snapshot!)
    }

    /// Keep showing a machine's last good state through a few missed polls.
    private func holdRecentlyGood(_ snapshot: MachineSnapshot) -> MachineSnapshot {
        let host = snapshot.host
        if snapshot.reachable && snapshot.authError == nil {
            lastGood[host] = (snapshot, Date())
            missesByHost[host] = 0
            return snapshot
        }
        // A rejected token is a real answer, not a miss — show it immediately.
        if snapshot.authError != nil { return snapshot }

        let misses = (missesByHost[host] ?? 0) + 1
        missesByHost[host] = misses
        guard misses < Self.missesBeforeOffline, let remembered = lastGood[host] else { return snapshot }
        var held = remembered.snapshot
        held.staleSeconds = max(1, Int(Date().timeIntervalSince(remembered.at)))
        return held
    }

    private func refreshEvents(from targets: [Machine]) async {
        var fetched: [AgentEvent] = []
        var notifyEvents: [AgentEvent] = []
        for machine in targets {
            let previousSince = lastEventISOByHost[machine.host]
            guard let machineEvents = try? await MeshClient(machine: machine).events(since: previousSince) else { continue }
            let shouldNotify = initializedEventHosts.contains(machine.host)
            initializedEventHosts.insert(machine.host)
            guard !machineEvents.isEmpty else {
                if previousSince == nil && !shouldNotify {
                    lastEventISOByHost[machine.host] = ISO8601DateFormatter().string(from: Date())
                }
                continue
            }
            let tagged = machineEvents.map { event in
                AgentEvent(id: event.id,
                           host: event.host ?? machine.host,
                           source: event.source,
                           session: event.session,
                           level: event.level,
                           title: event.title,
                           body: event.body,
                           createdISO: event.createdISO)
            }
            fetched.append(contentsOf: tagged)
            if shouldNotify {
                notifyEvents.append(contentsOf: tagged)
            }
            lastEventISOByHost[machine.host] = tagged.map(\.createdISO).max()
        }
        guard !fetched.isEmpty else { return }
        events = Array((events + fetched).suffix(100))
        NotificationManager.shared.evaluate(events: notifyEvents)
    }

    /// Send `continue` to the pinned rmux session for a provider (from limit-reset alerts).
    func resumePinnedLimit(providerId: String) async {
        guard let pin = pinnedLimitSessions.first(where: { $0.providerId.lowercased() == providerId.lowercased() }),
              let machine = machines.first(where: { $0.host == pin.host }) else {
            lastError = "No pinned session for \(providerId). Set one in Settings."
            return
        }
        if let provider = snapshot?.usage?.providers.first(where: { $0.id.lowercased() == providerId.lowercased() }),
           provider.limits.contains(where: { LimitHelpers.isBlocked($0) }) {
            lastError = "\(provider.displayName) is still at its limit. Try again after it resets."
            return
        }
        do {
            try await MeshClient(machine: machine).send(agent: pin.sessionName, text: "continue\n")
            await refresh()
        } catch {
            lastError = "continue failed: \(error)"
        }
    }

    func updatePinnedLimit(_ pin: PinnedLimitSession) {
        if let idx = pinnedLimitSessions.firstIndex(where: { $0.providerId.lowercased() == pin.providerId.lowercased() }) {
            pinnedLimitSessions[idx] = pin
        } else {
            pinnedLimitSessions.append(pin)
        }
        save()
    }

    func removePinnedLimit(providerId: String) {
        pinnedLimitSessions.removeAll { $0.providerId.lowercased() == providerId.lowercased() }
        save()
    }

    // MARK: Sessions

    /// Create a new rmux session on a machine, then refresh so it appears in the list.
    func newSession(on machine: Machine, name: String, cmd: String?, cwd: String? = nil, initialText: String? = nil) async {
        do {
            try await MeshClient(machine: machine).newSession(name: name, cmd: cmd, cwd: cwd, initialText: initialText)
            await refresh()
        } catch {
            lastError = "create session failed: \(error)"
        }
    }

    /// Kill a session on a machine, then refresh so it drops out of every client's list.
    func kill(on machine: Machine, name: String) async {
        do {
            try await MeshClient(machine: machine).kill(agent: name)
            await refresh()
        } catch {
            lastError = "kill session failed: \(error)"
        }
    }

    // MARK: Watch commands

    /// Returns payload data for commands the watch is waiting on an answer for.
    @discardableResult
    func handle(_ command: WatchCommand) async -> Data? {
        switch command.kind {
        case .refresh:
            // Hand the snapshot straight back. updateApplicationContext is best-effort
            // and rate-limited; a reply is not, and it is what the watch is waiting on.
            await refresh()
            return snapshot.flatMap { try? JSONEncoder().encode($0) }
        case .agentSend:
            guard let host = command.host, let agent = command.agent,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await MeshClient(machine: machine).send(agent: agent, text: command.text, key: command.key, pane: command.pane)
            await refresh()
        case .killAgent:
            guard let host = command.host, let agent = command.agent,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            await kill(on: machine, name: agent)
        case .killPane:
            guard let host = command.host, let agent = command.agent, let pane = command.pane,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await MeshClient(machine: machine).killPane(agent: agent, paneId: pane)
            if watchedHost == host, watchedAgent == agent, watchedPane == pane {
                watchedPane = nil
            }
            await refresh()
        case .agentOutput:
            // Watch asked to watch (or stop watching) an agent's live output.
            watchedHost = command.host
            watchedAgent = command.agent
            watchedPane = command.pane
            await refresh()
        case .screenPeek:
            watchedScreenHost = command.host
            watchedScreenDisplay = command.display
            await refresh()
        case .newAgent:
            guard let host = command.host, let name = command.text,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            await newSession(on: machine, name: name, cmd: command.cmd, initialText: command.initialText)
        case .newPane:
            guard let host = command.host, let agent = command.agent,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await MeshClient(machine: machine).newPane(agent: agent)
            await refresh()
        case .input:
            // Watch trackpad/keys, relayed when the watch itself can't reach meshd.
            guard let host = command.host, let events = command.input,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await MeshClient(machine: machine).input(events)
        case .volume:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await MeshClient(machine: machine).volume(delta: command.volumeDelta, muted: command.volumeMuted)
        case .clipboard:
            guard let host = command.host, let text = command.text,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await MeshClient(machine: machine).setClipboard(text)
        case .system:
            guard let host = command.host, let action = command.text,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await MeshClient(machine: machine).system(action)
        case .readClipboard:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }),
                  let text = try? await MeshClient(machine: machine).clipboard() else { return nil }
            return try? JSONEncoder().encode(text)
        case .listApps:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }),
                  let apps = try? await MeshClient(machine: machine).apps() else { return nil }
            return try? JSONEncoder().encode(apps)
        case .activateApp:
            guard let host = command.host, let name = command.text,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await MeshClient(machine: machine).activateApp(name)
        case .listDisplays:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }),
                  let list = try? await MeshClient(machine: machine).displays() else { return nil }
            return try? JSONEncoder().encode(list)
        case .inputStatus:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }),
                  let status = try? await MeshClient(machine: machine).inputStatus(prompt: command.text == "prompt")
            else { return nil }
            return try? JSONEncoder().encode(status)
        }
        return nil
    }

    private nonisolated static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost: return "connection refused"
            case .timedOut: return "timed out"
            case .notConnectedToInternet, .networkConnectionLost: return "network unavailable"
            default: return urlError.localizedDescription
            }
        }
        if let meshError = error as? MeshClient.MeshError {
            switch meshError {
            case .http(let code): return "HTTP \(code)"
            case .badURL: return "bad URL"
            case .decode: return "bad response"
            }
        }
        return error.localizedDescription
    }

    private nonisolated static func isAuthError(_ error: Error) -> Bool {
        if case MeshClient.MeshError.http(let code) = error {
            return code == 401 || code == 403
        }
        return false
    }

    private nonisolated static func probe(_ urlString: String?) async -> (ok: Bool, error: String?) {
        guard let urlString, let url = URL(string: urlString) else { return (false, "bad URL") }
        return await withTaskGroup(of: (ok: Bool, error: String?).self) { group in
            group.addTask {
                var req = URLRequest(url: url)
                req.timeoutInterval = 2
                do {
                    let (_, resp) = try await URLSession.shared.data(for: req)
                    guard let http = resp as? HTTPURLResponse else { return (true, nil) }
                    let ok = (200...399).contains(http.statusCode)
                    return (ok, ok ? nil : "HTTP \(http.statusCode)")
                } catch {
                    return (false, describe(error))
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return (false, "timed out")
            }
            let first = await group.next() ?? (false, "timed out")
            group.cancelAll()
            return first
        }
    }
}

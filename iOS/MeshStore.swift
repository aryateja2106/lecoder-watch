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
    /// Set when every machine fails instantly — iOS is blocking local-network traffic
    /// and no amount of retrying will help until the user grants the permission.
    @Published var localNetworkBlocked = false

    private var timer: Timer?
    private let defaultsKey = "mesh.machines.v1"
    private let installTokenKey = "mesh.installToken.v1"
    private let quickCommandsKey = "mesh.quickCommands.v1"
    private let pinnedLimitsKey = "mesh.pinnedLimits.v1"
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
    /// How long a host may go unanswered before we stop holding its last good state
    /// and admit "offline". Time-based, not a miss counter: partial publishes and
    /// overlapping refreshes each ran the old counter, so one timed-out poll could
    /// burn all three strikes inside a single refresh and flash offline instantly.
    /// ~45s is five clean 8s polls, or three worst-case 16s failures (8s timeout x
    /// two addresses) — sustained silence, not a blip.
    private static let offlineGraceSeconds: TimeInterval = 45
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
        // No seeded machines and so no tombstones to suppress them: an empty list means
        // "nothing paired yet", which the Machines tab turns into the pairing flow.
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Machine].self, from: data) {
            machines = decoded
        }
        if let decoded = UserDefaults.standard.stringArray(forKey: quickCommandsKey), !decoded.isEmpty {
            quickCommands = Self.mergedQuickCommands(decoded)
            UserDefaults.standard.set(quickCommands, forKey: quickCommandsKey)
        }
        if let data = UserDefaults.standard.data(forKey: pinnedLimitsKey),
           let decoded = try? JSONDecoder().decode([PinnedLimitSession].self, from: data) {
            pinnedLimitSessions = decoded
        }
    }

    func deleteMachines(atOffsets offsets: IndexSet) {
        machines.remove(atOffsets: offsets)
        save()
    }

    /// Redeem a pairing code and adopt everything the paired machine knows about.
    /// Returns the hosts that were added or refreshed, so the UI can say what happened.
    @discardableResult
    func pair(address: String, port: Int, code: String) async throws -> [PairedHost] {
        let result = try await MeshClient.claimPair(address: address, port: port, code: code)
        let hosts = result.allHosts
        guard !hosts.isEmpty else { throw MeshClient.MeshError.decode }
        machines = mergingPairedHosts(machines, hosts)
        save()
        // The highest-intent moment in the app: they just connected a machine, so
        // "let this thing alert you about it" now has an obvious referent.
        NotificationManager.shared.requestAuthorizationOncePaired(hasMachines: !machines.isEmpty)
        await refresh()
        return hosts
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

    /// The manual escape hatch. An empty token rather than a generated one: the
    /// machine already has a token of its own and a random one here would just 401,
    /// which reads as "the machine is broken" instead of "you have not paired it".
    func addMachine() {
        machines.append(Machine(host: "new-machine", ip: "", port: 8899, token: ""))
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
        // Single flight. A dead host takes up to 16s just to fail /health while the
        // timer fires every 8s, so unguarded overlap was the steady state — and an
        // old timed-out pass finishing late would overwrite the newer green snapshot
        // with "offline". That race was most of the visible online/offline flapping.
        guard !polling else { return }
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
                    var deniedInstantly = false
                    do {
                        let began = Date()
                        do {
                            health = try await client.healthInfo()
                        } catch {
                            errorText = Self.describe(error)
                            deniedInstantly = looksLikeLocalNetworkDenial(
                                error: error, elapsed: Date().timeIntervalSince(began))
                                && machine.addresses.contains(where: isLocalNetworkAddress)
                        }
                    }
                    guard health?.ok == true else {
                        return MachineSnapshot(host: machine.host,
                                               config: machine,
                                               reachable: false,
                                               stats: nil,
                                               agents: [],
                                               error: deniedInstantly ? "blocked by iOS" : (errorText ?? "unreachable"))
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
                                           tailnetError: tailnetError,
                                           mac: health?.mac)
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
        // Every host failing instantly is a permission problem, not a fleet outage.
        let reachableCount = results.filter(\.reachable).count
        let blockedCount = results.filter { $0.error == "blocked by iOS" }.count
        localNetworkBlocked = reachableCount == 0 && blockedCount == results.count && !results.isEmpty

        // Stable order matching the machine list.
        let ordered = targets.compactMap { m in results.first { $0.host == m.host } }
            .map { holdRecentlyGood($0) }

        // Remember each machine's hardware MAC while it's awake — that's exactly the
        // information you no longer have once it's asleep and you want to wake it.
        var machinesChanged = false
        for snap in ordered {
            guard let mac = snap.mac, !mac.isEmpty,
                  let idx = machines.firstIndex(where: { $0.host == snap.host }),
                  machines[idx].macAddress != mac else { continue }
            machines[idx].macAddress = mac
            machinesChanged = true
        }
        if machinesChanged { save() }

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
                // A phone screen is ~390 points at 3x, so 480px was soft even before
                // anyone zoomed. 1400 is legible and still about 270KB.
                screenJPEGData = try await MeshClient(machine: m).screenImage(display: watchedScreenDisplay, width: 1400)
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
        // Only off the full snapshot: a partial one is missing hosts, and a card that
        // flickers to another session mid-poll is worse than one that lands a beat late.
        LiveActivityController.shared.sync(snapshot: snap)
        // A banner that outlives the wait it announced is the complaint this answers.
        // `refreshEvents` ran just above, so the poll that first sees "Claude stopped"
        // is the same poll that pulls the "needs attention" banner down — no separate
        // lane watching for stop-shaped events, which would only ever be a guess about
        // one producer's wording.
        //
        // Guarded on having seen any event at all: a cold launch knows nothing yet, and
        // sweeping on no evidence would clear a live "needs you" banner that the first
        // poll simply has not caught up with.
        if !(snap.events ?? []).isEmpty {
            NotificationManager.shared.clearResolvedAlerts(
                attention: sessionsNeedingAttention(from: snap).map { ($0.host, $0.session) })
        }
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

    /// Keep showing a machine's last good state until it has been silent for the
    /// whole grace window. Judged purely by the clock, so it is idempotent — the
    /// partial publish and the final ordering pass can both run it for the same host
    /// without changing the verdict.
    private func holdRecentlyGood(_ snapshot: MachineSnapshot) -> MachineSnapshot {
        let host = snapshot.host
        if snapshot.reachable && snapshot.authError == nil {
            lastGood[host] = (snapshot, Date())
            return snapshot
        }
        // A rejected token is a real answer, not a miss — show it immediately.
        if snapshot.authError != nil { return snapshot }

        guard let remembered = lastGood[host],
              connectionPhase(lastContact: remembered.at,
                              grace: Self.offlineGraceSeconds) != .offline else { return snapshot }
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
    /// Answer an agent from a notification button. Errors are swallowed on purpose:
    /// there is no UI to report into — the user has already put the phone down — and
    /// the next poll shows whether the session moved.
    func respondToAgent(host: String, session: String, text: String?, key: String?) async {
        guard let machine = machineMatching(host, in: machines) else { return }
        try? await MeshClient(machine: machine).send(agent: session, text: text, key: key)
        await refresh()
    }

    /// Set by a `meshwatch://session/<host>/<name>` link (the live card, or a
    /// notification tap) and consumed by the Terminal tab.
    @Published var deepLinkSession: SessionTarget?

    struct SessionTarget: Identifiable, Hashable {
        var host: String
        var session: String
        var id: String { "\(host)/\(session)" }
    }

    /// Set by a `meshwatch://pair?h=<addr>&p=<port>&c=<code>` link — the QR that
    /// `mesh pair` prints. Scanning it with the system Camera lands here with every
    /// field filled; no in-app scanner, no camera permission. The user still sees
    /// the code and taps Pair themselves — that confirmation against what the
    /// terminal printed is the verification step, so the claim is never automatic.
    @Published var deepLinkPair: PairTarget?

    struct PairTarget: Identifiable, Hashable {
        var address: String
        var port: Int
        var code: String
        var id: String { "\(address):\(port)/\(code)" }
    }

    /// `meshwatch://session/<host>/<session>` or `meshwatch://pair?h=&p=&c=`.
    /// Anything else is ignored rather than guessed at.
    func open(url: URL) -> Bool {
        guard url.scheme == "meshwatch" else { return false }
        if url.host == "pair" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            guard let address = value("h")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !address.isEmpty,
                  let code = value("c"), normalizedPairingCode(code).count >= 6 else { return false }
            deepLinkPair = PairTarget(address: address,
                                      port: Int(value("p") ?? "") ?? 8899,
                                      code: code)
            return true
        }
        guard url.host == "session" else { return false }
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        deepLinkSession = SessionTarget(host: parts[0], session: parts[1])
        return true
    }

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
            await newSession(on: machine, name: name, cmd: command.cmd, cwd: command.cwd, initialText: command.initialText)
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

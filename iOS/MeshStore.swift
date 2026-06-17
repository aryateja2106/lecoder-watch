import Foundation
import Combine

/// Where a tapped notification should navigate: a session on a machine.
struct SessionRoute: Identifiable, Hashable {
    let host: String
    let session: String
    var id: String { "\(host)/\(session)" }
}

/// iPhone-side brain: persists the machine list, polls every machine's meshd
/// concurrently, builds the snapshot for the UI, and relays it to the watch.
@MainActor
final class MeshStore: ObservableObject {
    @Published var machines: [Machine] = []
    /// Named SSH/VNC identities. Non-secret metadata only — the password/key lives in Keychain
    /// (KeychainVault, keyed by credential id). Persisted separately from machines.
    @Published var credentials: [Credential] = []
    @Published var quickCommands: [String] = MeshStore.defaultQuickCommands
    @Published var snapshot: MeshSnapshot?
    @Published var events: [AgentEvent] = []
    @Published var lastError: String?
    @Published var polling = false
    /// Per-source / per-type notification toggles (Settings → Notifications).
    @Published var notifPrefs: NotifPrefs = MeshStore.loadNotifPrefs() { didSet { saveNotifPrefs() } }
    /// Notification-tap deep link: which tab to show and which session to push.
    @Published var selectedTab: Int = 0
    @Published var pendingSession: SessionRoute?
    /// The pinned "primary" session: leads the Live Activity and is the only
    /// session whose *completion* pings (needs-input/error still ping for all).
    @Published var primarySessionId: String? = UserDefaults.standard.string(forKey: MeshStore.primaryKey) {
        didSet { UserDefaults.standard.set(primarySessionId, forKey: Self.primaryKey) }
    }

    private var timer: Timer?
    private let defaultsKey = "mesh.machines.v1"
    private let credentialsKey = "mesh.credentials.v1"
    private let installTokenKey = "mesh.installToken.v1"
    private let quickCommandsKey = "mesh.quickCommands.v1"
    private static let notifPrefsKey = "mesh.notifPrefs.v1"
    private static let primaryKey = "mesh.primarySession.v1"
    static let defaultQuickCommands = ["continue", "git status", "pwd", "ls", "cd ..", "clear", "~/.mesh/bin/mesh-self-check"]
    // The agent the watch asked us to relay live output for.
    private var watchedHost: String?
    private var watchedAgent: String?
    private var watchedPane: String?
    private var lastEventISOByHost: [String: String] = [:]
    private var initializedEventHosts = Set<String>()

    init() {
        load()
        PhoneConnectivity.shared.commandHandler = { [weak self] cmd in
            await self?.handle(cmd)
        }
        // A notification tap opens its machine→session: switch to Terminal, push it.
        NotificationManager.shared.onOpen = { [weak self] host, session in
            Task { @MainActor in self?.openSession(host: host, session: session) }
        }
        // A notification action (Reply / Enter / Kill) runs through the WatchCommand router.
        NotificationManager.shared.onAction = { [weak self] command in
            Task { await self?.handle(command) }
        }
    }

    /// Deep-link from a tapped notification to the originating session.
    func openSession(host: String, session: String?) {
        selectedTab = 1   // Terminal tab (see ContentView tab order)
        if let session { pendingSession = SessionRoute(host: host, session: session) }
    }

    // MARK: Primary (pinned) session

    func isPrimary(_ session: String) -> Bool { primarySessionId == session }
    func setPrimary(_ session: String?) {
        primarySessionId = session
        LiveActivityController.shared.setPinned(session)
        // Start the activity right away while we're in the foreground (tap context).
        if session != nil, let snap = snapshot { LiveActivityController.shared.sync(snapshot: snap) }
    }

    // MARK: Notification prefs persistence

    private static func loadNotifPrefs() -> NotifPrefs {
        guard let data = UserDefaults.standard.data(forKey: notifPrefsKey),
              let decoded = try? JSONDecoder().decode(NotifPrefs.self, from: data) else { return .default }
        return decoded
    }

    private func saveNotifPrefs() {
        if let data = try? JSONEncoder().encode(notifPrefs) {
            UserDefaults.standard.set(data, forKey: Self.notifPrefsKey)
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
        hydrateTokens()
        if let data = UserDefaults.standard.data(forKey: credentialsKey),
           let decoded = try? JSONDecoder().decode([Credential].self, from: data) {
            credentials = decoded
        }
        if let decoded = UserDefaults.standard.stringArray(forKey: quickCommandsKey), !decoded.isEmpty {
            quickCommands = Self.mergedQuickCommands(decoded)
            UserDefaults.standard.set(quickCommands, forKey: quickCommandsKey)
        }
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

    /// Pull each machine's bearer token from the Keychain after decoding the (token-free)
    /// UserDefaults blob. Legacy blobs still carry a plaintext token: keep it, push it into the
    /// Keychain, and re-save so the next persisted blob is redacted.
    private func hydrateTokens() {
        var migratedLegacy = false
        for i in machines.indices {
            let stored = KeychainVault.token(for: machines[i].id)
            if machines[i].token.isEmpty {
                if let stored { machines[i].token = stored }
            } else if stored == nil {
                // Legacy plaintext token from the old UserDefaults blob → move into Keychain.
                KeychainVault.setToken(machines[i].token, for: machines[i].id)
                migratedLegacy = true
            }
        }
        if migratedLegacy { save() }   // overwrite the plaintext blob with a redacted one
    }

    func save() {
        // Secrets live in the Keychain, never in the UserDefaults plaintext blob.
        for machine in machines {
            if machine.token.isEmpty {
                KeychainVault.deleteToken(for: machine.id)
            } else {
                KeychainVault.setToken(machine.token, for: machine.id)
            }
        }
        let redacted = machines.map { m -> Machine in var c = m; c.token = ""; return c }
        if let data = try? JSONEncoder().encode(redacted) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        UserDefaults.standard.set(quickCommands, forKey: quickCommandsKey)
    }

    // MARK: Credentials (Vault)

    private func saveCredentials() {
        if let data = try? JSONEncoder().encode(credentials) {
            UserDefaults.standard.set(data, forKey: credentialsKey)
        }
    }

    /// Create a named identity: metadata persisted, secret stored in Keychain.
    func addCredential(name: String, kind: Credential.Kind, username: String, secret: String) {
        let cred = Credential(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                              kind: kind,
                              username: username.trimmingCharacters(in: .whitespacesAndNewlines))
        KeychainVault.setSecret(secret, forCredential: cred.id)
        credentials.append(cred)
        saveCredentials()
    }

    /// Replace a credential's metadata (and secret if a non-nil value is supplied).
    func updateCredential(_ cred: Credential, secret: String?) {
        if let idx = credentials.firstIndex(where: { $0.id == cred.id }) {
            credentials[idx] = cred
        }
        if let secret { KeychainVault.setSecret(secret, forCredential: cred.id) }
        saveCredentials()
    }

    func deleteCredentials(at offsets: IndexSet) {
        for i in offsets { KeychainVault.deleteSecret(forCredential: credentials[i].id) }
        credentials.remove(atOffsets: offsets)
        saveCredentials()
    }

    func update(_ machine: Machine) {
        if let idx = machines.firstIndex(where: { $0.id == machine.id }) {
            machines[idx] = machine
        } else {
            machines.append(machine)
        }
        save()
    }

    enum AddHostError: LocalizedError {
        case emptyAddress, duplicate(String)
        var errorDescription: String? {
            switch self {
            case .emptyAddress: return "Enter the machine's Tailscale IP or hostname."
            case .duplicate(let h): return "“\(h)” is already added."
            }
        }
    }

    /// Add a real machine from the Add-Host sheet: validate non-empty + unique, persist,
    /// then refresh so its reachable/auth status resolves inline. Returns the new machine's id.
    @discardableResult
    func addHost(name: String, ip: String, port: Int = 8899, token: String,
                 bridgeURL: String? = nil, vncURL: String? = nil) throws -> UUID {
        let ip = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else { throw AddHostError.emptyAddress }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = trimmedName.isEmpty ? ip : trimmedName
        guard !machines.contains(where: { $0.host.caseInsensitiveCompare(host) == .orderedSame }) else {
            throw AddHostError.duplicate(host)
        }
        let machine = Machine(
            host: host, ip: ip, port: port,
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            bridgeURL: bridgeURL?.isEmpty == true ? nil : bridgeURL,
            vncURL: vncURL?.isEmpty == true ? nil : vncURL
        )
        machines.append(machine)
        save()
        Task { await refresh() }
        return machine.id
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
                        health = try? await client.healthInfo()
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
                    for idx in agents.indices {
                        agents[idx].panes = try? await client.panes(agent: agents[idx].name)
                    }
                    let reachable = stats != nil || health?.ok == true
                    return MachineSnapshot(host: machine.host,
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
            for await snap in group { results.append(snap) }
        }
        // Stable order matching the machine list.
        let ordered = targets.compactMap { m in results.first { $0.host == m.host } }

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
        await refreshEvents(from: targets)

        let snap = MeshSnapshot(updatedISO: ISO8601DateFormatter().string(from: Date()),
                                machines: ordered,
                                usage: usage,
                                quickCommands: quickCommands,
                                events: events,
                                watchedHost: watchedHost,
                                watchedAgent: watchedAgent,
                                watchedPane: watchedPane,
                                watchedOutput: watchedOutput)
        snapshot = snap
        PhoneConnectivity.shared.push(snap)
        NotificationManager.shared.evaluate(snap)
        LiveActivityController.shared.sync(snapshot: snap)
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
                // Tag with the app's display host (e.g. "my-mac") rather than
                // meshd's os.hostname() so notification taps
                // resolve back to a Machine and the Monitor feed reads consistently.
                AgentEvent(id: event.id,
                           host: machine.host,
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
        NotificationManager.shared.evaluate(events: notifyEvents, prefs: notifPrefs, primary: primarySessionId)
    }

    // MARK: Sessions

    /// Create a new rmux session on a machine, then refresh so it appears in the list.
    func newSession(on machine: Machine, name: String, cmd: String?, initialText: String? = nil) async {
        do {
            try await MeshClient(machine: machine).newSession(name: name, cmd: cmd, initialText: initialText)
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

    func handle(_ command: WatchCommand) async {
        switch command.kind {
        case .refresh:
            await refresh()
        case .agentSend:
            guard let host = command.host, let agent = command.agent,
                  let machine = machines.first(where: { $0.host == host }) else { return }
            try? await MeshClient(machine: machine).send(agent: agent, text: command.text, key: command.key, pane: command.pane)
            await refresh()
        case .killAgent:
            guard let host = command.host, let agent = command.agent,
                  let machine = machines.first(where: { $0.host == host }) else { return }
            await kill(on: machine, name: agent)
        case .killPane:
            guard let host = command.host, let agent = command.agent, let pane = command.pane,
                  let machine = machines.first(where: { $0.host == host }) else { return }
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
        case .newAgent:
            guard let host = command.host, let name = command.text,
                  let machine = machines.first(where: { $0.host == host }) else { return }
            await newSession(on: machine, name: name, cmd: command.cmd, initialText: command.initialText)
        case .newPane:
            guard let host = command.host, let agent = command.agent,
                  let machine = machines.first(where: { $0.host == host }) else { return }
            try? await MeshClient(machine: machine).newPane(agent: agent)
            await refresh()
        }
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

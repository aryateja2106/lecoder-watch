import Foundation
import Combine
import CoreGraphics
import UIKit

/// A failure with the moment it happened. A bare string could not say whether it was
/// describing right now or a tap from twenty minutes ago, so it sat in the Monitor tab
/// forever and stopped meaning anything.
struct StoreError: Equatable {
    var message: String
    var at: Date
}

/// What we remember about a machine's network identity while it is awake — exactly the
/// three facts a Wake-on-LAN needs once it is asleep and can no longer be asked.
/// UserDefaults rather than the Keychain: a MAC and a subnet are not secrets, and the
/// Keychain blob is the token store.
struct MachineNetIdentity: Codable, Hashable {
    var mac: String? = nil
    var ipv4: String? = nil
    var netmask: String? = nil
}

/// iPhone-side brain: persists the machine list, polls every machine's meshd
/// concurrently, builds the snapshot for the UI, and relays it to the watch.
@MainActor
final class MeshStore: ObservableObject {
    @Published var machines: [Machine] = []
    @Published var quickCommands: [String] = MeshStore.defaultQuickCommands
    @Published var pinnedLimitSessions: [PinnedLimitSession] = []
    @Published var snapshot: MeshSnapshot?
    @Published var events: [AgentEvent] = []
    @Published var lastError: StoreError?
    @Published var polling = false
    /// False until the very first poll has finished. "No machines online" and "we have
    /// not looked yet" are different sentences, and showing the first one during launch
    /// is how the app told people their fleet was down every single cold start.
    @Published private(set) var hasEverPolled = false
    /// Set when every machine fails instantly — iOS is blocking local-network traffic
    /// and no amount of retrying will help until the user grants the permission.
    @Published var localNetworkBlocked = false

    private var timer: Timer?
    private let defaultsKey = "mesh.machines.v1"
    private let installTokenKey = "mesh.installToken.v1"
    private let quickCommandsKey = "mesh.quickCommands.v1"
    private let pinnedLimitsKey = "mesh.pinnedLimits.v1"
    private let netIdentityKey = "mesh.netIdentity.v1"
    private let capabilitiesKey = "mesh.capabilities.v1"
    private let removedHostsKey = "mesh.removedHosts.v1"
    static let defaultQuickCommands = ["continue", "git status", "pwd", "ls", "cd ..", "clear", "~/.mesh/bin/mesh-self-check"]
    // The agent the watch asked us to relay live output for.
    private var watchedHost: String?
    private var watchedAgent: String?
    /// Mirrors the watch's Reader toggle so a relayed capture reads the same way its
    /// direct-route twin does.
    private var watchedReader = false
    private var watchedPane: String?
    private var watchedScreenHost: String?
    private var watchedScreenDisplay: Int?
    /// Normalized crop / size / quality the watch asked for on its last screenPeek.
    /// Held across polls because the watch names them once and then just waits for
    /// frames; re-sending them on every poll would be three fields of noise per tick.
    private var watchedScreenRect: CGRect?
    private var watchedScreenWidth: Int?
    private var watchedScreenQuality: Int?
    /// What each daemon last advertised on /health, so every `MeshClient` built here
    /// knows which 0.5.0 features it may use. Absent = assume an old daemon and leave
    /// every gated parameter off the wire, which is exactly what 0.4.1 expects.
    ///
    /// Persisted, because the alternative is a launch where every gated feature is off
    /// until the first poll lands — and the Live Activity push-to-start token arrives
    /// from ActivityKit *before* that, gets refused for want of a known "laPush", and
    /// is then never offered again until it rotates. A remembered capability list is
    /// stale at worst: the first poll of the launch corrects it either way.
    private var capabilitiesByHost: [String: [String]] = [:]
    /// Live Activity tokens are offered once per launch, after the first poll.
    private var hasOfferedLATokensThisLaunch = false
    /// MAC + subnet per host, remembered from /health while the machine was awake.
    private(set) var netIdentityByHost: [String: MachineNetIdentity] = [:]
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

    // MARK: Errors

    /// Record a failure with its timestamp. Everything that used to assign a bare
    /// string goes through here so no lane can put an undateable error on screen.
    func fail(_ message: String) {
        lastError = StoreError(message: message, at: Date())
    }

    // MARK: Clients

    /// A `MeshClient` that knows what this machine's daemon can do. Building one
    /// without the capabilities silently disables every 0.5.0 feature — correct
    /// against a 0.4.1 daemon, wrong against a 0.5.0 one — so this is the only
    /// constructor the store uses.
    func client(for machine: Machine) -> MeshClient {
        var configured = MeshClient(machine: machine)
        configured.capabilities = capabilitiesByHost[machine.host]
        return configured
    }

    /// Whether a machine's daemon advertised a capability, from the last poll.
    func supports(_ capability: String, host: String) -> Bool {
        capabilitiesByHost[host]?.contains(capability) ?? false
    }

    // MARK: Persistence

    func load() {
        // No seeded machines and so no tombstones to suppress them: an empty list means
        // "nothing paired yet", which the Machines tab turns into the pairing flow.
        //
        // Machines carry meshd tokens, so they live in the Keychain. Builds before
        // this kept them in UserDefaults in plaintext; migrate those once.
        if let data = SecureStore.migrateFromUserDefaults(key: defaultsKey),
           let decoded = try? JSONDecoder().decode([Machine].self, from: data) {
            // Stamp every machine written before `uid` existed, once, before anything
            // renders — the rest of the app may then treat `id` as stable and unique.
            let needsStamping = decoded.contains { $0.uid == nil }
            machines = decoded.map { var m = $0; if m.uid == nil { m.uid = UUID() }; return m }
            if needsStamping { save() }
        }
        if let decoded = UserDefaults.standard.stringArray(forKey: quickCommandsKey), !decoded.isEmpty {
            quickCommands = Self.mergedQuickCommands(decoded)
            UserDefaults.standard.set(quickCommands, forKey: quickCommandsKey)
        }
        if let data = UserDefaults.standard.data(forKey: pinnedLimitsKey),
           let decoded = try? JSONDecoder().decode([PinnedLimitSession].self, from: data) {
            pinnedLimitSessions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: netIdentityKey),
           let decoded = try? JSONDecoder().decode([String: MachineNetIdentity].self, from: data) {
            netIdentityByHost = decoded
        }
        if let data = UserDefaults.standard.data(forKey: capabilitiesKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            capabilitiesByHost = decoded
        }
        // A MAC cached by an earlier build lives on the Machine itself; fold it in so
        // the wake path has one place to look.
        for machine in machines {
            guard let mac = machine.macAddress, !mac.isEmpty,
                  netIdentityByHost[machine.host]?.mac == nil else { continue }
            var identity = netIdentityByHost[machine.host] ?? MachineNetIdentity()
            identity.mac = mac
            netIdentityByHost[machine.host] = identity
        }
    }

    private func saveNetIdentities() {
        guard let data = try? JSONEncoder().encode(netIdentityByHost) else { return }
        UserDefaults.standard.set(data, forKey: netIdentityKey)
    }

    private func saveCapabilities() {
        guard let data = try? JSONEncoder().encode(capabilitiesByHost) else { return }
        UserDefaults.standard.set(data, forKey: capabilitiesKey)
    }

    /// Hosts the user deliberately removed, kept so a later pairing's fleet import does
    /// not resurrect them (pairing adopts the paired machine's whole hosts.json).
    /// Lowercased names and addresses; not secret, so UserDefaults is the right place.
    private var removedHosts: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: removedHostsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: removedHostsKey) }
    }

    private func tombstone(_ machine: Machine) {
        var set = removedHosts
        if !machine.host.isEmpty { set.insert(machine.host.lowercased()) }
        if !machine.ip.isEmpty { set.insert(machine.ip.lowercased()) }
        removedHosts = set
    }

    func deleteMachines(atOffsets offsets: IndexSet) {
        let removed = Set(offsets.map { machines[$0].host })
        for i in offsets { tombstone(machines[i]) }
        machines.remove(atOffsets: offsets)
        // Same ghost problem as removeMachine: an in-flight poll can write the row
        // back moments later, so the visible snapshot must forget it too.
        snapshot?.machines.removeAll { removed.contains($0.host) }
        save()
    }

    /// Removal from the machine list or detail screen, where there is no IndexSet.
    /// Local only — the machine itself is untouched — and remembered, so the row does
    /// not reappear from the next pairing's fleet.
    func removeMachine(host: String) {
        // The row being removed may be a ghost a stale poll wrote back after the
        // config was already deleted. Removal must never be a silent no-op: strip the
        // snapshot row and record the tombstone even when there is no config row left.
        var set = removedHosts
        set.insert(host.lowercased())
        removedHosts = set
        if let index = machines.firstIndex(where: { $0.host == host })
            ?? machines.firstIndex(where: { hostNamesMatch($0.host, host) }) {
            tombstone(machines[index])
            machines.remove(at: index)
        }
        // Drop the stale snapshot row too; waiting for the next poll to erase a machine
        // the user just deleted reads as the delete not working.
        snapshot?.machines.removeAll { $0.host == host }
        save()
    }

    /// Redeem a pairing code and adopt everything the paired machine knows about.
    /// Returns the hosts that were added or refreshed, so the UI can say what happened.
    @discardableResult
    func pair(address: String, port: Int, code: String) async throws -> [PairedHost] {
        let result = try await MeshClient.claimPair(address: address, port: port, code: code)
        guard !result.allHosts.isEmpty else { throw MeshClient.MeshError.decode }
        // Pairing this machine is the un-remove gesture: its identifiers leave the
        // tombstone set so it can be removed and re-added forever. Every OTHER fleet
        // entry still respects a deliberate removal — without this, deleting a stale
        // machine is silently undone by the next pairing.
        var tombstones = removedHosts
        tombstones.remove(result.host.lowercased())
        tombstones.remove(address.lowercased())
        for entry in result.allHosts where hostNamesMatch(entry.host, result.host) || entry.ip == address {
            tombstones.remove(entry.host.lowercased())
            tombstones.remove(entry.ip.lowercased())
        }
        removedHosts = tombstones
        let hosts = filteringRemovedHosts(result.allHosts, removed: tombstones,
                                          pairedHost: result.host, pairedAddress: address)
        machines = mergingPairedHosts(machines, hosts)
        save()
        // The highest-intent moment in the app: they just connected a machine, so
        // "let this thing alert you about it" now has an obvious referent.
        NotificationManager.shared.requestAuthorizationOncePaired(hasMachines: !machines.isEmpty)
        await refresh()
        // After the refresh, so the capability list this machine advertises is known
        // before we try to hand it tokens that only a "laPush" daemon can accept.
        await LiveActivityController.shared.resendTokens()
        return hosts
    }

    func installToken() -> String {
        if let saved = SecureStore.migrateStringFromUserDefaults(key: installTokenKey), !saved.isEmpty {
            return saved
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        SecureStore.save(token, for: installTokenKey)
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
            SecureStore.save(data, for: defaultsKey)
        }
        UserDefaults.standard.set(quickCommands, forKey: quickCommandsKey)
        if let data = try? JSONEncoder().encode(pinnedLimitSessions) {
            UserDefaults.standard.set(data, forKey: pinnedLimitsKey)
        }
    }

    /// Match on `host`, not on `id`. A machine is the same machine when it is the same
    /// box; `id` is only the row's identity in a list, and a freshly paired `Machine`
    /// carries a brand new one — matching on it would append a second copy of a machine
    /// you already had every time you re-paired it. The existing row's `uid` is kept so
    /// the list does not lose the row's identity underneath the user.
    func update(_ machine: Machine) {
        if let idx = machines.firstIndex(where: { $0.host == machine.host }) {
            var merged = machine
            merged.uid = machines[idx].uid ?? machine.uid ?? UUID()
            machines[idx] = merged
        } else {
            var added = machine
            if added.uid == nil { added.uid = UUID() }
            machines.append(added)
        }
        save()
    }

    /// The manual escape hatch. An empty token rather than a generated one: the
    /// machine already has a token of its own and a random one here would just 401,
    /// which reads as "the machine is broken" instead of "you have not paired it".
    func addMachine() {
        // A unique name as well as a unique id: two rows called "new-machine" are
        // indistinguishable to the user even once the list can render them safely.
        var name = "new-machine"
        var n = 2
        while machines.contains(where: { $0.host == name }) {
            name = "new-machine-\(n)"; n += 1
        }
        machines.append(Machine(uid: UUID(), host: name, ip: "", port: 8899, token: ""))
        save()
    }

    // MARK: Push

    /// Fan the APNs device token out to every configured machine; each meshd
    /// stores it and pushes alerts directly. Failures are fine — offline hosts
    /// get the token next launch.
    func uploadPushToken(_ token: String) async {
        for machine in machines {
            try? await client(for: machine).registerPush(deviceToken: token)
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
        let startedAt = Date()
        let targets = machines
        // Read once on the main actor; the per-machine tasks below are nonisolated and
        // must not reach back into store state while the group is running.
        let cachedCapabilities = capabilitiesByHost
        var results: [MachineSnapshot] = []
        await withTaskGroup(of: MachineSnapshot.self) { group in
            for machine in targets {
                group.addTask {
                    // A machine added by hand has no token yet. Polling it answers
                    // "token rejected", which reads as "this machine is broken" when the
                    // truth is "you have not paired it" — and it is the very first thing
                    // you see after tapping Add manually.
                    guard machine.isConfigured else {
                        return MachineSnapshot(
                            host: machine.host, config: machine, reachable: false, agents: [],
                            error: "not paired yet — open this machine and tap Pair")
                    }
                    // Seeded from the last poll so the very first call of this pass is
                    // already capability-correct, then replaced by whatever /health
                    // says a moment later.
                    var client = MeshClient(machine: machine)
                    client.capabilities = cachedCapabilities[machine.host]
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
                    // From here on this client speaks the daemon's own dialect.
                    if let advertised = health?.capabilities { client.capabilities = advertised }
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
                                           mac: health?.mac,
                                           ipv4: health?.ipv4,
                                           netmask: health?.netmask)
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
        // information you no longer have once it's asleep and you want to wake it. The
        // subnet (ipv4 + netmask, meshd 0.5.0+) rides along for the same reason: it is
        // what picks a peer that can actually reach the sleeping machine's LAN.
        var machinesChanged = false
        var identitiesChanged = false
        var capabilitiesChanged = false
        for snap in ordered {
            guard snap.reachable else { continue }
            if let mac = snap.mac, !mac.isEmpty,
               let idx = machines.firstIndex(where: { $0.host == snap.host }),
               machines[idx].macAddress != mac {
                machines[idx].macAddress = mac
                machinesChanged = true
            }
            var identity = netIdentityByHost[snap.host] ?? MachineNetIdentity()
            let updated = MachineNetIdentity(mac: snap.mac ?? identity.mac,
                                             ipv4: snap.ipv4 ?? identity.ipv4,
                                             netmask: snap.netmask ?? identity.netmask)
            if updated != identity {
                identity = updated
                netIdentityByHost[snap.host] = identity
                identitiesChanged = true
            }
            if let caps = snap.capabilities, capabilitiesByHost[snap.host] != caps {
                capabilitiesByHost[snap.host] = caps
                capabilitiesChanged = true
            }
        }
        if machinesChanged { save() }
        if identitiesChanged { saveNetIdentities() }
        if capabilitiesChanged { saveCapabilities() }

        // ActivityKit hands over the push-to-start token within moments of launch —
        // usually before the first poll, when we do not yet know whether any machine
        // can accept it, so the upload is refused and never retried. Offer them again
        // once per launch as soon as we have actually heard from the fleet, or an
        // upgrading user registers nothing until they happen to re-pair.
        if !hasOfferedLATokensThisLaunch, !capabilitiesByHost.isEmpty {
            hasOfferedLATokensThisLaunch = true
            await LiveActivityController.shared.resendTokens()
        }

        var usage: UsageSnapshot?
        for machine in targets {
            guard let fetched = try? await client(for: machine).usage(),
                  !fetched.providers.isEmpty else { continue }
            usage = fetched
            break
        }

        // Relay live output for whatever agent the watch is watching, in the shape the
        // watch is currently displaying. The relay is the normal route for a watch that
        // is not on the tailnet, so sending the plain capture regardless meant Reader
        // mode did half its job exactly where it was needed most. MeshClient drops the
        // flags against a daemon without "captureJoin", which is the old behavior.
        var watchedOutput: [String]?
        if let host = watchedHost, let agent = watchedAgent,
           let m = targets.first(where: { $0.host == host }) {
            watchedOutput = (try? await client(for: m).output(agent: agent, lines: 60, pane: watchedPane,
                                                              join: watchedReader, plain: watchedReader))?.lines
        }
        var screenJPEGData: Data?
        var screenError: String?
        if let host = watchedScreenHost,
           let m = targets.first(where: { $0.host == host }) {
            do {
                // 1400px is right for the phone's own viewer at ~270KB — but this frame
                // is about to ride a WatchConnectivity message, and those are capped at
                // 262,144 bytes. Over the cap the send throws, PhoneConnectivity swallows
                // it, and the wrist just shows nothing forever. The watch screen is 184
                // points wide, so 600 is already generous.
                screenJPEGData = try await client(for: m).screenImage(display: watchedScreenDisplay,
                                                                      width: watchedScreenWidth ?? 600,
                                                                      rect: watchedScreenRect,
                                                                      quality: watchedScreenQuality)
            } catch {
                screenError = Self.describe(error)
            }
        }
        await refreshEvents(from: targets)

        // This poll captured `targets = machines` up to ~16s ago (a dead host takes
        // that long to fail /health while the timer fires every 8s), and the user may
        // have removed a machine since. Writing the stale row back resurrects it on
        // screen — the "I deleted it and it came again" bug — so the snapshot keeps
        // only rows the machine list still owns.
        let liveHosts = Set(machines.map { $0.host })
        let liveOrdered = ordered.filter { liveHosts.contains($0.host) }
        let now = ISO8601DateFormatter().string(from: Date())
        let snap = MeshSnapshot(updatedISO: now,
                                machines: liveOrdered,
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

        // "We have looked" — the Machines tab stops saying "checking…" about a fleet it
        // has never actually contacted, and starts saying what it found.
        hasEverPolled = true

        // A healthy pass retires an older complaint. Only an *older* one: an error
        // raised during this very refresh is the freshest thing we know and clearing it
        // here would make failures flash and vanish.
        if let error = lastError, error.at < startedAt, reachableCount > 0, !localNetworkBlocked {
            lastError = nil
        }
    }

    /// Emit a snapshot containing the hosts that have answered so far, with the rest
    /// carrying whatever we last knew, so the list fills in progressively.
    private func publishPartial(_ answered: [MachineSnapshot], targets: [Machine]) {
        // `uniqueKeysWithValues` TRAPS on a duplicate key, and two machines can share a
        // host name — nothing stops you naming them both "pi". Keep the newest answer.
        let byHost = Dictionary(answered.map { ($0.host, $0) }, uniquingKeysWith: { _, newer in newer })
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
            guard let machineEvents = try? await client(for: machine).events(since: previousSince) else { continue }
            let shouldNotify = initializedEventHosts.contains(machine.host)
            initializedEventHosts.insert(machine.host)
            guard !machineEvents.isEmpty else {
                if previousSince == nil && !shouldNotify {
                    lastEventISOByHost[machine.host] = ISO8601DateFormatter().string(from: Date())
                }
                continue
            }
            // Copy-and-mutate, never a memberwise re-init. The old re-init named eight
            // fields and silently dropped the two it did not — `replyable` and `pane`,
            // the exact fields that decide whether an alert gets buttons and where a
            // reply lands — and it would drop every future field the same way. Only the
            // host is being filled in here, so only the host should be written.
            let tagged = machineEvents.map { event -> AgentEvent in
                var tagged = event
                tagged.host = event.host ?? machine.host
                return tagged
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
            fail("No pinned session for \(providerId). Set one in Settings.")
            return
        }
        if let provider = snapshot?.usage?.providers.first(where: { $0.id.lowercased() == providerId.lowercased() }),
           provider.limits.contains(where: { LimitHelpers.isBlocked($0) }) {
            fail("\(provider.displayName) is still at its limit. Try again after it resets.")
            return
        }
        do {
            try await client(for: machine).send(agent: pin.sessionName, text: "continue\n")
            await refresh()
        } catch {
            fail("continue failed: \(Self.describe(error))")
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
    /// Returns whether it actually landed — `@discardableResult` so the fire-and-forget
    /// callers (the watch relay's `.newAgent` command) are unaffected, while a caller
    /// with a sheet on screen (`NewSessionSheet`) can keep that sheet open and show the
    /// failure inline instead of dismissing on the strength of having tried.
    @discardableResult
    func newSession(on machine: Machine, name: String, cmd: String?, cwd: String? = nil, initialText: String? = nil,
                    cols: Int? = nil, rows: Int? = nil) async -> Bool {
        do {
            try await client(for: machine).newSession(name: name, cmd: cmd, cwd: cwd, initialText: initialText,
                                                      cols: cols, rows: rows)
            await refresh()
            return true
        } catch {
            fail("create session failed: \(Self.describe(error))")
            return false
        }
    }

    /// Kill a session on a machine, then refresh so it drops out of every client's list.
    func kill(on machine: Machine, name: String) async {
        do {
            try await client(for: machine).kill(agent: name)
            await refresh()
        } catch {
            fail("kill session failed: \(Self.describe(error))")
        }
    }

    // MARK: Watch commands

    /// Answer an agent from a notification button, or from the Needs-you row.
    ///
    /// The failure used to be swallowed on the theory that nobody was looking. They
    /// often are — the same call backs the in-app affirmative — and a tap that quietly
    /// did nothing is indistinguishable from a tap that worked, which is the worst
    /// possible outcome for a button whose whole job is to unblock an agent. The error
    /// is recorded either way; if nobody is looking it costs a line in Monitor.
    ///
    /// `pane` routes the answer into the pane the question came from, when the event
    /// named one. Nil means the session's active pane — the pre-existing behavior.
    ///
    /// Returns nil when the answer landed, or the reason it did not, so a caller with a
    /// button can stop labelling it "Sent" on the strength of having tried.
    @discardableResult
    func respondToAgent(host: String, session: String, text: String?, key: String?,
                        pane: String? = nil) async -> String? {
        guard let machine = machineMatching(host, in: machines) else {
            let line = "\(host) isn't paired on this phone, so there is nowhere to send that."
            fail(line)
            return line
        }
        var failure: String?
        do {
            try await client(for: machine).send(agent: session, text: text, key: key, pane: pane)
        } catch {
            failure = "Couldn't answer \(session) on \(host): \(Self.describe(error))"
            fail(failure!)
        }
        await refresh()
        return failure
    }

    // MARK: Power

    /// Run a `/system` action and report what actually happened. meshd 0.5.0 answers
    /// with the real exit code and stderr, so a `pmset` that was refused finally reads
    /// as refused; older daemons say `{ok:true}` regardless and that stays "worked",
    /// which is exactly today's behavior and no worse.
    ///
    /// Returns nil on success, or the line to show the user.
    @discardableResult
    func systemAction(_ action: String, on machine: Machine) async -> String? {
        do {
            let result = try await client(for: machine).systemAction(action)
            guard let line = result.failureLine else { return nil }
            fail("\(action) on \(machine.host): \(line)")
            return line
        } catch MeshClient.MeshError.unsupported(let capability) {
            let line = "\(machine.host) runs an agent without \(capability) support. Re-run the install command on it."
            fail(line)
            return line
        } catch {
            let line = Self.describe(error)
            fail("\(action) on \(machine.host): \(line)")
            return line
        }
    }

    /// The directed broadcast for an address and its mask — host bits all ones. Nil
    /// unless both parse as dotted quads: guessing here aims a magic packet at the
    /// wrong network, which is worse than not sending one at all.
    static func directedBroadcast(ipv4: String?, netmask: String?) -> String? {
        guard let address = quad(ipv4), let mask = quad(netmask) else { return nil }
        return (0..<4).map { String((address[$0] & mask[$0]) | (~mask[$0] & 255)) }.joined(separator: ".")
    }

    /// Whether two addresses sit on the same IPv4 subnet. Requires both masks and
    /// requires them to agree — two hosts claiming different masks for one wire is not
    /// something to paper over by picking one.
    static func sameSubnet(_ address: String?, _ mask: String?,
                           _ otherAddress: String?, _ otherMask: String?) -> Bool {
        guard let a = quad(address), let m = quad(mask),
              let b = quad(otherAddress), let n = quad(otherMask), m == n else { return false }
        return (0..<4).allSatisfy { (a[$0] & m[$0]) == (b[$0] & m[$0]) }
    }

    private static func quad(_ text: String?) -> [Int]? {
        guard let text else { return nil }
        let parts = text.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return parts
    }

    /// The remembered network identity for a host, whether it came from this session's
    /// polls or from a previous launch.
    func netIdentity(for host: String) -> MachineNetIdentity {
        var identity = netIdentityByHost[host] ?? MachineNetIdentity()
        if let snap = snapshot?.machines.first(where: { $0.host == host }) {
            identity = MachineNetIdentity(mac: snap.mac ?? identity.mac,
                                          ipv4: snap.ipv4 ?? identity.ipv4,
                                          netmask: snap.netmask ?? identity.netmask)
        }
        if identity.mac == nil { identity.mac = machines.first { $0.host == host }?.macAddress }
        return identity
    }

    /// An awake machine that can broadcast a magic packet onto the sleeping one's own
    /// LAN. Wake-on-LAN is a LAN broadcast, so the phone cannot send it across the
    /// tailnet itself and a peer on the *wrong* network sends a packet nobody hears.
    ///
    /// When the target's subnet is known (meshd 0.5.0 reports it), only a peer on that
    /// subnet qualifies. When it is not — an old daemon never said — any wake-capable
    /// peer is offered, which is exactly the pre-0.5.0 behavior.
    func wakePeer(for host: String) -> Machine? {
        let target = netIdentity(for: host)
        let peers = (snapshot?.machines ?? []).filter {
            $0.host != host && $0.reachable && !$0.isStale && ($0.capabilities?.contains("wake") ?? false)
        }
        if target.ipv4 != nil, target.netmask != nil {
            let onSubnet = peers.first { peer in
                let identity = netIdentity(for: peer.host)
                return Self.sameSubnet(target.ipv4, target.netmask, identity.ipv4, identity.netmask)
            }
            return onSubnet.flatMap { peer in machines.first { $0.host == peer.host } }
        }
        return peers.compactMap { peer in machines.first { $0.host == peer.host } }.first
    }

    /// Ask a peer to wake a sleeping machine. Returns nil on success, or the honest
    /// reason it could not be done — never a button that pretends.
    @discardableResult
    func wake(host: String) async -> String? {
        let identity = netIdentity(for: host)
        guard let mac = identity.mac, !mac.isEmpty else {
            let line = "No hardware address for \(host) yet. Open it once while it's awake and this appears."
            fail(line)
            return line
        }
        guard let peer = wakePeer(for: host) else {
            let line = identity.ipv4 == nil
                ? "Can't wake \(host): no online machine can broadcast for it."
                : "Can't wake \(host): no online peer on that network."
            fail(line)
            return line
        }
        let broadcast = Self.directedBroadcast(ipv4: identity.ipv4, netmask: identity.netmask)
        do {
            try await client(for: peer).wake(mac: mac, via: broadcast)
            return nil
        } catch {
            let line = "Wake via \(peer.host) failed: \(Self.describe(error))"
            fail(line)
            return line
        }
    }

    // MARK: Live Activity push tokens

    /// Hand a Live Activity push token to every paired machine that can use one.
    /// Hosts without the "laPush" capability refuse client-side and are skipped in
    /// silence — an old daemon has no route to take it.
    func uploadLAToken(kind: MeshClient.LATokenKind, token: String, session: String? = nil) async {
        for machine in machines {
            try? await client(for: machine).uploadLAToken(kind: kind, token: token, session: session)
        }
    }

    // MARK: What the user is looking at

    /// The session on screen right now, if any. A banner about the thing you are
    /// already staring at is pure noise, so both notification lanes consult this.
    @Published private(set) var currentlyViewing: SessionTarget? {
        didSet {
            NotificationManager.shared.currentlyViewing =
                currentlyViewing.map { (host: $0.host, session: $0.session) }
        }
    }

    /// Called by a session screen as it appears and disappears.
    func viewing(_ target: SessionTarget?) {
        currentlyViewing = target
    }

    /// Set by a `meshwatch://session/<host>/<name>` link (the live card, or a
    /// notification tap) and consumed by the Terminal tab.
    ///
    /// Doubles as the "on screen" signal for the route it drives: SwiftUI clears it
    /// when the destination is popped, so it is already an accurate statement about
    /// what is visible.
    @Published var deepLinkSession: SessionTarget? {
        didSet {
            guard let deepLinkSession else {
                if currentlyViewing == oldValue { viewing(nil) }
                return
            }
            viewing(deepLinkSession)
        }
    }

    struct SessionTarget: Identifiable, Hashable {
        var host: String
        var session: String
        var id: String { "\(host)/\(session)" }
    }

    /// Set by a `meshwatch://pair?h=<addr>&p=<port>&c=<code>` link — the QR that
    /// `mesh pair` prints, whether the system Camera handed it off or the in-app
    /// scanner (`PairingScannerSheet`) read it directly. Either way it lands here with
    /// every field filled, not paired: the user still sees the code and taps Pair
    /// themselves — that confirmation against what the terminal printed is the
    /// verification step, so the claim is never automatic.
    @Published var deepLinkPair: PairTarget?

    struct PairTarget: Identifiable, Hashable {
        var address: String
        var port: Int
        var code: String
        var id: String { "\(address):\(port)/\(code)" }
    }

    /// `meshwatch://session/<host>/<session>` or `meshwatch://pair?h=&p=&c=`.
    /// Anything else is ignored rather than guessed at. The pairing half defers to
    /// `parsePairingLink`, the same parser the in-app QR scanner uses, so a link
    /// handed off by the system Camera and one read straight off the frame agree.
    func open(url: URL) -> Bool {
        if let link = parsePairingLink(url) {
            deepLinkPair = PairTarget(address: link.address, port: link.port, code: link.code)
            return true
        }
        guard url.scheme == "meshwatch", url.host == "session" else { return false }
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        deepLinkSession = SessionTarget(host: parts[0], session: parts[1])
        return true
    }

    /// Service one command relayed from the watch. Returns payload data for the
    /// commands the watch is waiting on an answer for, nil for fire-and-forget ones.
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
            try? await client(for: machine).send(agent: agent, text: command.text, key: command.key, pane: command.pane)
            await refresh()
        case .killAgent:
            guard let host = command.host, let agent = command.agent,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            await kill(on: machine, name: agent)
        case .killPane:
            guard let host = command.host, let agent = command.agent, let pane = command.pane,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await client(for: machine).killPane(agent: agent, paneId: pane)
            if watchedHost == host, watchedAgent == agent, watchedPane == pane {
                watchedPane = nil
            }
            await refresh()
        case .agentOutput:
            // Watch asked to watch (or stop watching) an agent's live output.
            watchedHost = command.host
            watchedAgent = command.agent
            watchedPane = command.pane
            watchedReader = command.reader ?? false
            await refresh()
        case .screenPeek:
            watchedScreenHost = command.host
            watchedScreenDisplay = command.display
            // A watch that has zoomed into a corner asks for that corner. The rect is
            // only honoured against a daemon advertising "screenRegion"; MeshClient
            // drops it otherwise and the full frame comes back, which is the right
            // degradation — a stretched full frame beats a hard error.
            if let rect = command.rect, rect.count == 4 {
                watchedScreenRect = CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
            } else {
                watchedScreenRect = nil
            }
            watchedScreenWidth = command.width
            watchedScreenQuality = command.quality
            await refresh()
        case .newAgent:
            guard let host = command.host, let name = command.text,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            await newSession(on: machine, name: name, cmd: command.cmd, cwd: command.cwd,
                             initialText: command.initialText, cols: command.cols, rows: command.rows)
        case .newPane:
            guard let host = command.host, let agent = command.agent,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await client(for: machine).newPane(agent: agent)
            await refresh()
        case .input:
            // Watch trackpad/keys, relayed when the watch itself can't reach meshd.
            guard let host = command.host, let events = command.input,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await client(for: machine).input(events)
        case .volume:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            _ = try? await client(for: machine).volume(delta: command.volumeDelta, muted: command.volumeMuted)
        case .clipboard:
            guard let host = command.host, let text = command.text,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await client(for: machine).setClipboard(text)
        case .system:
            guard let host = command.host, let action = command.text,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            // Answer with the daemon's real verdict instead of dropping it. A watch
            // that ignores the reply is unaffected; one that decodes `SystemResult`
            // can finally say "that failed" instead of animating a success it did not
            // observe. Client-side refusals (shutdown on a daemon without "power")
            // come back as a result too, not as silence.
            do {
                let result = try await client(for: machine).systemAction(action)
                if let line = result.failureLine { fail("\(action) on \(host): \(line)") }
                return try? JSONEncoder().encode(result)
            } catch MeshClient.MeshError.unsupported(let capability) {
                let line = "\(host) has no \(capability) support — update the agent on it."
                fail(line)
                return try? JSONEncoder().encode(SystemResult(ok: false, exitCode: nil, stderr: nil, action: action, error: line))
            } catch {
                let line = Self.describe(error)
                fail("\(action) on \(host): \(line)")
                return try? JSONEncoder().encode(SystemResult(ok: false, exitCode: nil, stderr: nil, action: action, error: line))
            }
        case .readClipboard:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }),
                  let text = try? await client(for: machine).clipboard() else { return nil }
            return try? JSONEncoder().encode(text)
        case .readPhoneClipboard:
            // The *iPhone's* pasteboard, not the Mac's — that one is `readClipboard`.
            // iOS only serves UIPasteboard to a foreground app: from the background it
            // hands back nothing, and relaying that empty string would tell the wrist
            // "you copied nothing", which is a lie about the user's own clipboard.
            // Say why instead.
            guard UIApplication.shared.applicationState == .active else {
                return try? JSONEncoder().encode(RelayReply.failure(
                    "open MeshWatch on your iPhone — iOS only shares the clipboard with an app you're looking at"))
            }
            return try? JSONEncoder().encode(UIPasteboard.general.string ?? "")
        case .openURL:
            // Validated here as well as in MeshClient and again in the daemon: a
            // `file:` or custom scheme opened on someone's Mac is an attack surface,
            // and the wrist is the least verifiable place a URL can come from.
            guard let host = command.host, let raw = command.url,
                  let url = URL(string: raw),
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            do {
                try await client(for: machine).openURL(url)
            } catch {
                fail("Couldn't open that link on \(host): \(Self.describe(error))")
            }
        case .fsList:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }),
                  let listing = try? await client(for: machine).fsList(path: command.path) else { return nil }
            return try? JSONEncoder().encode(listing)
        case .listApps:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }),
                  let apps = try? await client(for: machine).apps() else { return nil }
            return try? JSONEncoder().encode(apps)
        case .activateApp:
            guard let host = command.host, let name = command.text,
                  let machine = machines.first(where: { $0.host == host }) else { return nil }
            try? await client(for: machine).activateApp(name)
        case .listDisplays:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }),
                  let list = try? await client(for: machine).displays() else { return nil }
            return try? JSONEncoder().encode(list)
        case .inputStatus:
            guard let host = command.host,
                  let machine = machines.first(where: { $0.host == host }),
                  let status = try? await client(for: machine).inputStatus(prompt: command.text == "prompt")
            else { return nil }
            return try? JSONEncoder().encode(status)
        }
        return nil
    }

    // MARK: Connection diagnosis

    /// Per-address result of a connection attempt. "timed out" on the machine row
    /// only reports whichever address failed last, which hides whether the address
    /// was unreachable, unresolvable, or answering with the wrong token.
    struct AddressDiagnosis: Identifiable {
        var id: String { address }
        var address: String
        var outcome: String
        var ok: Bool
    }

    /// Try every address a machine would use, separately, and report each result.
    /// `/health` needs no token, so a green address next to a red auth row isolates
    /// the fault to the token rather than the network — and vice versa. That is
    /// exactly the distinction the machine row's single error string cannot make.
    ///
    /// The only place that builds a bare `MeshClient` on purpose: it is `nonisolated`
    /// and cannot reach the store's capability cache, and it deliberately calls the two
    /// routes every daemon since 0.1 has served. A diagnosis must work against the
    /// oldest daemon in the fleet — that is when you need one.
    nonisolated static func diagnose(_ machine: Machine) async -> [AddressDiagnosis] {
        var results: [AddressDiagnosis] = []
        for address in machine.addresses {
            guard let url = URL(string: "http://\(address):\(machine.port)/health") else {
                results.append(.init(address: address, outcome: "bad URL", ok: false))
                continue
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = MeshClient(machine: machine).timeout
            let started = Date()
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                results.append(.init(address: address,
                                     outcome: "HTTP \(code) in \(ms)ms",
                                     ok: (200...299).contains(code)))
            } catch {
                results.append(.init(address: address, outcome: describe(error), ok: false))
            }
        }
        // A reachable machine still fails everything if the token is wrong, so
        // check an authenticated endpoint too — that separates network from auth.
        do {
            let agents = try await MeshClient(machine: machine).agents()
            results.append(.init(address: "auth",
                                 outcome: "token OK · \(agents.count) session\(agents.count == 1 ? "" : "s")",
                                 ok: true))
        } catch {
            if isAuthError(error) {
                results.append(.init(address: "auth",
                                     outcome: "token REJECTED — re-pair this machine",
                                     ok: false))
            } else {
                results.append(.init(address: "auth",
                                     outcome: "unreachable: \(describe(error))",
                                     ok: false))
            }
        }
        return results
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
            // Not a network failure at all: the call never left the phone because the
            // daemon never claimed it could do this. Say which thing is missing —
            // "unsupported" alone sends people looking at the wrong end.
            case .unsupported(let capability): return "this agent has no \(capability) support"
            // The daemon's own sentence, which names the thing that went wrong —
            // "pane w9:p2 not found" instead of the "HTTP 400" it used to collapse to.
            case .refused(_, let why): return why
            }
        }
        return error.localizedDescription
    }

    /// Asked of `statusCode`, not of one case: a 401 carrying meshd's
    /// `{"error":"unauthorized"}` body arrives as .refused, and matching only .http
    /// would drop the token prompt exactly when the token is the problem.
    private nonisolated static func isAuthError(_ error: Error) -> Bool {
        guard let code = (error as? MeshClient.MeshError)?.statusCode else { return false }
        return code == 401 || code == 403
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

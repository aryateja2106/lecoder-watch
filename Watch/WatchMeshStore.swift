import Foundation
import Combine
import WatchKit

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
    /// Why the watch has nothing to show. Without this the empty state told a user who
    /// had already paired three machines to go and pair a machine — the one instruction
    /// guaranteed not to help.
    @Published var lastPhoneReplyAt: Date?
    @Published var phoneReplyMachineCount: Int?
    @Published var phoneLinkNote: String?
    /// The last time *any* path (phone reply or a direct poll) gave us real data. The
    /// connection phase is judged from this, not from WCSession's reachability flag,
    /// which flaps to false every few seconds when the phone app suspends.
    @Published private var lastGoodContact: Date?

    /// How connected we actually are. The UI keys off this instead of `phoneReachable`
    /// so a momentary WCSession drop doesn't read as "offline" over a 6-second-old
    /// snapshot. See `connectionPhase`.
    var connectionState: ConnectionPhase { connectionPhase(lastContact: lastGoodContact) }

    /// Reader mode asks the daemon to unwrap soft-wrapped lines and strip the
    /// box-drawing and spinner glyphs a TUI paints (meshd 0.5.0 "captureJoin"), so a
    /// 21-column screen shows sentences instead of rubble. Off = the capture exactly
    /// as tmux hands it over, which is what the Raw view wants.
    @Published var readerOutput = true {
        didSet {
            // Tell the phone too, or toggling Reader changes only the direct route and
            // the relayed lines keep arriving in the other shape.
            guard readerOutput != oldValue, let t = watching else { return }
            WatchLink.shared.send(WatchCommand(kind: .agentOutput, host: t.host, agent: t.agent,
                                               text: nil, key: nil, pane: t.pane, reader: readerOutput))
        }
    }

    struct WatchTarget: Equatable { let host: String; let agent: String; let pane: String? }
    static let defaultQuickCommands = ["continue", "git status", "pwd", "ls", "cd ..", "clear", "~/.mesh/bin/mesh-self-check"]

    /// A session that still looks busy but has said nothing for this long has "gone
    /// quiet" — distinct from "waiting", where somebody actually asked you something.
    static let stallSeconds: TimeInterval = 600

    /// The prefix the phone puts on a `.readPhoneClipboard` reply it could not
    /// fulfil. UIPasteboard is foreground-only on iOS, so a blocked read has to come
    /// back as a *sentence*: an empty clipboard and an unreadable one are different
    /// facts, and an empty string would collapse them into the same shrug.
    static let clipboardErrorPrefix = RelayReply.errorPrefix

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

    /// Every agent across the mesh that is stopped waiting on a human. The one list
    /// the watch exists to show, assembled from whichever path is live.
    var needsAttention: [LiveSessionPick] {
        var merged = MeshSnapshot(updatedISO: relayed?.updatedISO ?? "", machines: snaps)
        merged.events = events
        return sessionsNeedingAttention(from: merged)
    }

    /// True once we know there is nothing to show — as opposed to not knowing yet.
    /// Without the distinction, a first run with no machines spins "Connecting…" forever.
    var hasNoMachines: Bool { machines.isEmpty }

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

    // MARK: Capabilities

    /// What this machine's daemon said it can do, from whichever path answered.
    ///
    /// Every meshd 0.5.0 addition in `MeshClient` is gated on this list, and its
    /// default is nil = "assume a 0.4.1 daemon". A bare `MeshClient(machine:)`
    /// therefore silently turns OFF region capture, reader mode and /open even
    /// against a daemon that has them — which is why nothing in this file constructs
    /// one directly any more; see `client(for:)`.
    func capabilities(for host: String) -> [String]? {
        snaps.first { $0.host == host }?.capabilities
    }

    func supports(_ capability: String, host: String) -> Bool {
        capabilities(for: host)?.contains(capability) ?? false
    }

    /// A client that knows what the daemon on `host` can do. Nil when the machine is
    /// not in our list — the caller then has only the phone relay, which is the same
    /// answer it had before.
    private func client(for host: String) -> MeshClient? {
        guard let machine = machines.first(where: { $0.host == host }) else { return nil }
        var client = MeshClient(machine: machine)
        client.capabilities = capabilities(for: host)
        return client
    }

    /// The host name THIS app uses for the machine a daemon (or an APNs payload)
    /// called `name`. See `machineMatching` for why the two can differ.
    func knownHost(for name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return machineMatching(name, in: machines)?.host
    }

    /// How we are reaching this machine — a fact about the MACHINE, never about the
    /// watch's link to the phone.
    ///
    /// The two used to be one string, and the conflation ran both ways: a machine the
    /// phone had explicitly reported as down read "reconnecting" (as if the fault were
    /// the watch's), and a live machine we simply had no word about read "offline" (as
    /// if the Mac were the thing that had gone). Both are the wrong noun, and on a row
    /// whose only other content is a session count that single word is the whole
    /// diagnosis. So: if anything has an opinion about the host, report the host; only
    /// when nothing does is the sentence allowed to be about the link.
    func routeLabel(for host: String) -> String {
        if directReachable(host) { return "direct" }
        if let relayedHost = relayed?.machines.first(where: { $0.host == host }) {
            if relayedHost.reachable {
                return connectionState == .offline ? "phone snapshot" : "via phone"
            }
            // The phone answered and said this machine is not answering IT. That is a
            // fact about the Mac, and it stays true whatever the watch link is doing.
            return connectionState == .offline ? "offline · last known" : "offline"
        }
        switch connectionState {
        case .live, .reconnecting: return "reconnecting"
        case .waiting: return "connecting"
        case .offline: return "no link to iPhone"
        }
    }

    private var pollTask: Task<Void, Never>?
    private var outputTask: Task<Void, Never>?
    /// Single-flight for `refresh()`. See the guard there for why the watch needs this
    /// even more than the phone does.
    private var refreshing = false
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
            // Keychain, not UserDefaults — this cache carries every machine's meshd
            // token, and the watch backs up and restores like the phone does.
            SecureStore.save(data, for: Self.machinesKey)
        }
        Task { await refresh() }
    }

    private static let machinesKey = "watch.machines.v1"

    private func loadCachedMachines() {
        // Migrating read: older builds cached the list in UserDefaults in plaintext.
        guard let data = SecureStore.migrateFromUserDefaults(key: Self.machinesKey),
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
            Task { @MainActor in
                guard let self else { return }
                let regained = r && !self.phoneReachable
                self.phoneReachable = r
                // The phone just became reachable — don't sit out the rest of the 6s
                // poll interval. Clear the direct backoff too: a watch that walked back
                // into range can reach its machines directly again right now.
                if regained {
                    self.directBlockedUntil.removeAll()
                    await self.refresh()
                }
            }
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
        guard let data = await WatchLink.shared.request(command, timeout: 10) else {
            phoneLinkNote = phoneReachable ? "iPhone did not answer" : "iPhone not reachable"
            WatchLink.shared.send(command)   // queue it; the phone answers next time
            return
        }
        guard let snap = try? JSONDecoder().decode(MeshSnapshot.self, from: data) else {
            // A reply we cannot read is a version skew between the two apps, and it
            // looks identical to no reply at all unless it is named.
            phoneLinkNote = "iPhone sent something this watch could not read"
            return
        }
        lastPhoneReplyAt = Date()
        lastGoodContact = Date()
        phoneReplyMachineCount = snap.machines.count
        phoneLinkNote = snap.machines.isEmpty ? "iPhone answered, but has no machines paired" : nil
        relayed = snap
        adoptConfigs(from: snap)
    }

    /// What to tell someone staring at an empty watch. Every branch names the next
    /// useful action, and none of them says "pair a machine" to someone who already has.
    var emptyStateReason: (title: String, detail: String) {
        if let count = phoneReplyMachineCount, count == 0 {
            return ("No machines paired",
                    "Your iPhone answered but has nothing paired yet. Open LeSearch Mesh on your iPhone and pair a machine.")
        }
        if lastPhoneReplyAt != nil {
            return ("Nothing to show yet", phoneLinkNote ?? "Your iPhone answered but sent no machines.")
        }
        // Only call it unreachable after we have actually been out of contact a while —
        // a cold start or a momentary drop should read as "connecting", not a fault.
        switch connectionState {
        case .offline:
            return ("iPhone not reachable",
                    "Keep your iPhone nearby and unlocked, then open LeSearch Mesh on it once. The watch reaches your machines through the phone.")
        default:
            return ("Connecting…", "Reaching your iPhone. Keep it nearby and unlocked.")
        }
    }

    /// A line the user can read out to us when it is still not working.
    var linkStatusLine: String {
        let phase: String
        switch connectionState {
        case .live: phase = "Live"
        case .reconnecting: phase = "Reconnecting"
        case .offline: phase = "Offline"
        case .waiting: phase = "Connecting"
        }
        var parts = [phase, phoneReachable ? "iPhone reachable" : "iPhone asleep"]
        if let at = lastPhoneReplyAt {
            parts.append("replied \(Int(Date().timeIntervalSince(at)))s ago")
        } else {
            parts.append("no reply yet")
        }
        if let n = phoneReplyMachineCount { parts.append("\(n) machine\(n == 1 ? "" : "s") from phone") }
        parts.append("\(machines.count) known here")
        return parts.joined(separator: " · ")
    }

    func refresh() async {
        // Single flight, for the same reason MeshStore.refresh() is single flight on the
        // phone — an older, slower pass finishing late overwrites the newer green
        // snapshot with "offline", and that race was most of the visible flapping.
        //
        // The watch needs this MORE than the phone, because reconnecting is what sets it
        // off. `adoptConfigs` fires `Task { await refresh() }` whenever a relayed machine
        // config changes, and it is itself called from `pullFromPhone()` — which runs
        // inside this function. So one refresh spawns a second refresh from inside its own
        // body, at exactly the moment a machine comes back and its config gains a MAC
        // address. Add the reachability-regained trigger and the poll loop on top and
        // three passes race, which is why the connection was "decently stable until it
        // tried reconnecting again".
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

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
                                           capabilities: health?.capabilities,
                                           // Carried so the wrist wake path has a MAC to
                                           // aim at and a subnet to aim it into; meshd
                                           // 0.5.0 reports ipv4/netmask, older ones nil.
                                           mac: health?.mac,
                                           ipv4: health?.ipv4,
                                           netmask: health?.netmask)
                }
            }
            for await s in group { results.append(s) }
        }
        for snap in results {
            noteDirect(host: snap.host, ok: snap.reachable && snap.authError == nil)
        }
        // A direct poll that reached a machine is contact too, so a watch on the same
        // network as a host stays "live" even when the phone is asleep.
        if results.contains(where: { $0.reachable && $0.authError == nil }) {
            lastGoodContact = Date()
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
        publishGlance()
    }

    // MARK: Per-session status

    /// The newest event this app holds for a (host, session) pair, for daemons that
    /// send no `status`/`lastEvent*` of their own. `events` arrives oldest-first, so
    /// the last match is the newest one; host names are matched tolerantly for the
    /// same reason `sessionsNeedingAttention` does it — the daemon's name for a box
    /// is not always the name this app stored.
    func latestEvent(host: String, session: String) -> AgentEvent? {
        events.last { event in
            guard let eventHost = event.host, event.session == session else { return false }
            return hostNamesMatch(eventHost, host)
        }
    }

    /// What a session row should say: the daemon's own verdict when it has one
    /// (meshd 0.5.0 "sessionStatus"), else derived from the newest event we hold.
    func displayState(of agent: Agent, host: String, now: Date = Date()) -> SessionDisplayState {
        agent.displayState(latestEvent: latestEvent(host: host, session: agent.name), now: now)
    }

    /// Sessions that still look busy but have produced nothing for `stallSeconds`.
    ///
    /// Deliberately not folded into "Needs you": nobody asked you anything, so there
    /// is no button to press — but on a long unattended run the difference between
    /// "still going" and "wedged" is the whole reason to look at your wrist. Sessions
    /// already listed as waiting are excluded so one agent is never counted twice, and
    /// a session that has never emitted an event is skipped rather than accused: not
    /// having spoken yet is not the same as having gone quiet.
    var stalledSessions: [(host: String, session: String)] {
        let now = Date()
        let waiting = Set(needsAttention.map { "\($0.host)\u{1}\($0.session)" })
        var out: [(host: String, session: String)] = []
        for snap in snaps where snap.reachable && snap.authError == nil {
            for agent in snap.agents {
                if waiting.contains("\(snap.host)\u{1}\(agent.name)") { continue }
                guard displayState(of: agent, host: snap.host, now: now) == .working else { continue }
                let event = latestEvent(host: snap.host, session: agent.name)
                guard let last = parseISO(agent.lastEventISO) ?? parseISO(event?.createdISO) else { continue }
                if now.timeIntervalSince(last) >= Self.stallSeconds {
                    out.append((host: snap.host, session: agent.name))
                }
            }
        }
        return out
    }

    /// Hand the face complications the little they can show. Written after every
    /// refresh, from whichever path answered — the complication runs in another
    /// process and has no way to ask.
    func publishGlance() {
        let reachable = snaps.filter { $0.reachable && $0.authError == nil }
        GlanceStore.write(WatchGlance(
            updatedISO: ISO8601DateFormatter().string(from: Date()),
            waiting: needsAttention.map { .init(host: $0.host, session: $0.session, line: $0.lastLine,
                                                risky: $0.risk.isDestructive) },
            machinesUp: reachable.count,
            machinesTotal: machines.count,
            // Rendered only in the rectangular band, and only when nothing is
            // waiting — the circular count stays reserved for the actionable number.
            stalled: stalledSessions.count,
        ))
    }

    // MARK: Watch a single agent

    func watch(host: String, agent: String, pane: String? = nil) {
        watching = WatchTarget(host: host, agent: agent, pane: pane)
        directOutput = []
        // Ask the phone to relay this agent's output too (used if direct fails).
        WatchLink.shared.send(WatchCommand(kind: .agentOutput, host: host, agent: agent, text: nil, key: nil,
                                           pane: pane, reader: readerOutput))
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
        guard let w = watching, directReachable(w.host), let c = client(for: w.host) else { return }
        // Reader mode is a *daemon* transform when the daemon has it: join unwraps the
        // soft-wrapped lines tmux stores, plain strips the box-drawing. Against a
        // 0.4.1 daemon `supports` is false, the flags never go on the wire, and the
        // capture comes back byte-identical to today's — the reader view then still
        // wraps text, it just cannot un-wrap what tmux already broke.
        let cleaned = readerOutput && c.supports("captureJoin")
        // 60 lines was about three wrist-screens: scrolling back past a compile error
        // ran out of buffer before it ran out of screen. 300 is ~15 screens.
        //
        // The ceiling is not this route (a direct HTTP capture) but the relay: the same
        // capture rides `updateApplicationContext`, which WatchConnectivity caps at
        // 262,144 bytes and which throws SILENTLY past it — the wrist would just stop
        // updating with no error anywhere. 300 lines of a wide Mac pane (~200 columns)
        // is ~60KB encoded, and it shares that snapshot with a 600px screen-peek JPEG
        // (~110KB once JSON-encoded), so the worst case still leaves ~90KB of slack.
        if let out = try? await c.output(agent: w.agent, lines: 300, pane: w.pane,
                                         join: cleaned, plain: cleaned) {
            directOutput = out.lines
        }
    }

    // MARK: Send — direct if reachable, else via the phone relay.

    /// Turn a relay acknowledgement into something the wrist can feel and read.
    ///
    /// The relay used to be fire-and-forget: `WatchLink.send` returns void whether the
    /// phone took the command, was asleep, or is running a build that cannot decode it.
    /// On a screen with no console and no second chance, "I pressed Enter and nothing
    /// visibly happened" is indistinguishable from "Enter went through" — so every
    /// write now waits for the phone to say so.
    private func apply(_ ack: WatchLink.Ack, verb: String) {
        switch ack {
        case .delivered:
            lastError = nil
            WKInterfaceDevice.current().play(.success)
        case .queued:
            lastError = "iPhone asleep — \(verb) queued until it wakes"
            WKInterfaceDevice.current().play(.retry)
        case .failed(let why):
            lastError = "\(verb) failed — \(why)"
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func send(text: String? = nil, key: String? = nil) {
        guard let w = watching else { return }
        if directReachable(w.host), let c = client(for: w.host) {
            sending = true
            lastError = nil
            Task {
                do {
                    try await c.send(agent: w.agent, text: text, key: key, pane: w.pane)
                    // No success haptic on this path deliberately. A key chip is
                    // pressed in runs — ten Downs to scroll a list — and ten buzzes
                    // for ten keys is not feedback, it is a vibrating watch. The
                    // direct path answers in well under the 300ms below, so the
                    // output redrawing IS the confirmation. Failure still buzzes:
                    // that one is rare and worth interrupting for.
                } catch {
                    lastError = "send failed"
                    WKInterfaceDevice.current().play(.failure)
                }
                try? await Task.sleep(for: .milliseconds(300))
                await pollOutput()
                sending = false
            }
        } else {
            sending = true
            lastError = nil
            Task {
                // Not queued: a keystroke delivered ten minutes late lands on whatever
                // is on screen then, which is worse than losing it.
                let ack = await WatchLink.shared.acknowledge(
                    WatchCommand(kind: .agentSend, host: w.host, agent: w.agent,
                                 text: text, key: key, pane: w.pane))
                apply(ack, verb: "send")
                await pollOutput()
                sending = false
            }
        }
    }

    /// Answer an agent from a notification button. The host comes from the APNs
    /// payload, so it is the name the *daemon* uses; our stored name may be the key
    /// from another machine's hosts.json, hence the tolerant match.
    ///
    /// `pane` is the exact `session:window.pane` the event named, when it named one,
    /// so Approve lands in the agent's pane rather than whichever pane the mux session
    /// last had focused.
    func respondToAgent(host: String, session: String, pane: String? = nil,
                        text: String?, key: String?) {
        let match = machineMatching(host, in: machines)
        if let m = match, directReachable(m.host), let c = client(for: m.host) {
            lastError = nil
            Task {
                do {
                    try await c.send(agent: session, text: text, key: key, pane: pane)
                    WKInterfaceDevice.current().play(.success)
                } catch {
                    lastError = "reply failed"
                    WKInterfaceDevice.current().play(.failure)
                }
                await refresh()
            }
        } else {
            // Off the tailnet, or the machine is not in our list yet: the phone has both.
            // Queued when the phone is asleep — an answer that arrives late still beats
            // an agent left blocked, and `apply` says out loud that it is only queued.
            lastError = nil
            Task {
                let ack = await WatchLink.shared.acknowledge(
                    WatchCommand(kind: .agentSend, host: match?.host ?? host,
                                 agent: session, text: text, key: key, pane: pane),
                    queueWhenUnreachable: true)
                apply(ack, verb: "reply")
                await refresh()
            }
        }
    }

    /// Send `continue` to a limit-pinned session (resume-at-reset from the wrist).
    func sendToPinned(_ pin: PinnedLimitSession) {
        if directReachable(pin.host), let c = client(for: pin.host) {
            lastError = nil
            Task {
                do {
                    try await c.send(agent: pin.sessionName, text: "continue\n")
                    WKInterfaceDevice.current().play(.success)
                } catch {
                    lastError = "resume failed"
                    WKInterfaceDevice.current().play(.failure)
                }
            }
        } else {
            lastError = nil
            Task {
                let ack = await WatchLink.shared.acknowledge(
                    WatchCommand(kind: .agentSend, host: pin.host, agent: pin.sessionName,
                                 text: "continue\n", key: nil),
                    queueWhenUnreachable: true)
                apply(ack, verb: "resume")
            }
        }
    }

    // MARK: The iPhone's own clipboard

    /// Type whatever is on the iPhone's pasteboard into the watched session.
    ///
    /// This is the one thing a watch genuinely cannot do for itself: there is no
    /// scribble surface wide enough for a URL, an error string or an API key, and the
    /// text is nearly always already on the phone that is two feet away. UIPasteboard
    /// is foreground-only on iOS, so the failure is real and has to be a sentence —
    /// never an empty string, which would be indistinguishable from an empty clipboard.
    ///
    /// Text only, no newline: it lands in the prompt for you to read before you send it.
    @discardableResult
    func insertPhoneClipboard() async -> Bool {
        guard watching != nil else { return false }
        lastError = nil
        switch await Self.phoneClipboardText() {
        case .problem(let why):
            lastError = why
            WKInterfaceDevice.current().play(.failure)
            return false
        case .text(let text):
            send(text: text)
            return true
        }
    }

    /// The iPhone's clipboard, or the honest reason it could not be read.
    ///
    /// Static, and free of `watching`, because the wrist needs this from two places
    /// that share no state: the terminal, where the text lands in the prompt, and the
    /// Clipboard screen, where you only want to look at it. It was written for the
    /// first and reachable from neither — the terminal never grew a button, so a fully
    /// implemented feature sat here with no caller at all while the Clipboard screen
    /// offered the Mac's clipboard and not the phone's.
    enum PhoneClipboard {
        case text(String)
        /// A sentence for the wrist, never an empty string: "the clipboard is empty"
        /// and "iOS won't share it while the app is in the background" are different
        /// facts and both render blank if they share a representation.
        case problem(String)
    }

    static func phoneClipboardText() async -> PhoneClipboard {
        let ack = await WatchLink.shared.acknowledge(
            WatchCommand(kind: .readPhoneClipboard, host: nil, agent: nil, text: nil, key: nil))
        switch ack {
        case .failed(let why):
            return .problem("clipboard — \(why)")
        case .queued:
            return .problem("open LeSearch Mesh on your iPhone once, then try again")
        case .delivered(let data):
            guard let data, let text = try? JSONDecoder().decode(String.self, from: data) else {
                // No payload: either an older phone build that does not know this
                // command, or one that could not read its own pasteboard from the
                // background. Both have the same fix.
                return .problem("open LeSearch Mesh on your iPhone once — it can only read its clipboard while open")
            }
            if text.hasPrefix(clipboardErrorPrefix) {
                let why = String(text.dropFirst(clipboardErrorPrefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .problem(why.isEmpty ? "the iPhone could not read its clipboard" : why)
            }
            guard !text.isEmpty else { return .problem("the iPhone's clipboard is empty") }
            return .text(text)
        }
    }

    // MARK: Open a link on the machine

    /// Whether this machine's daemon has the /open route at all (meshd 0.5.0+).
    /// A button that is honestly absent beats one that 404s into "network error".
    func canOpenOnMac(host: String) -> Bool { supports("openUrl", host: host) }

    /// Open a link in the machine's own browser. http/https only — `MeshClient`
    /// checks again, and so does the daemon.
    func openOnMac(host: String, url: URL) {
        guard canOpenOnMac(host: host) else {
            lastError = "\(shortHostName(host)) needs meshd 0.5.0 to open links"
            WKInterfaceDevice.current().play(.failure)
            return
        }
        if directReachable(host), let c = client(for: host) {
            lastError = nil
            Task {
                do {
                    try await c.openURL(url)
                    WKInterfaceDevice.current().play(.success)
                } catch {
                    lastError = "could not open that link on \(shortHostName(host))"
                    WKInterfaceDevice.current().play(.failure)
                }
            }
        } else {
            lastError = nil
            Task {
                let ack = await WatchLink.shared.acknowledge(
                    WatchCommand(kind: .openURL, host: host, agent: nil, text: nil, key: nil,
                                 url: url.absoluteString))
                apply(ack, verb: "open link")
            }
        }
    }

    /// The PTY a wrist-launched session gets.
    ///
    /// The daemon's default is 80×24, and a watch draws about 21 monospaced columns —
    /// so every logical line arrives pre-broken into four, and no amount of client-side
    /// reflow can put it back together. Asking for a narrow terminal in the first place
    /// is the only fix that reaches the source. Sent unconditionally: a daemon that
    /// does not know these fields ignores them and creates the session at its default.
    static let wristCols = 60
    static let wristRows = 30

    @discardableResult
    func newSession(host: String, cmd: String?, cwd: String? = nil, initialText: String? = nil) -> String {
        let name = watchSessionName(cmd)
        if directReachable(host), let c = client(for: host) {
            lastError = nil
            Task {
                do {
                    try await c.newSession(name: name, cmd: cmd, cwd: cwd, initialText: initialText,
                                           cols: Self.wristCols, rows: Self.wristRows)
                    watch(host: host, agent: name)
                } catch {
                    lastError = "new session failed"
                }
                await refresh()
            }
        } else {
            WatchLink.shared.send(WatchCommand(kind: .newAgent, host: host, agent: nil, text: name, key: nil,
                                               cmd: cmd, cwd: cwd, initialText: initialText,
                                               cols: Self.wristCols, rows: Self.wristRows))
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

    /// Directories the machine's own live panes are sitting in, newest first.
    ///
    /// Typing a path on a watch is not realistic, so the only workable way to choose a
    /// workspace is to pick one you are already working in. The phone already offers
    /// this; the panes carry `currentPath`, so the watch can too.
    func workspaceSuggestions(host: String) -> [String] {
        let agents = snaps.first { $0.host == host }?.agents ?? []
        var seen = Set<String>()
        return agents
            .flatMap { $0.panes ?? [] }
            .compactMap(\.currentPath)
            .filter { $0 != "/" && seen.insert($0).inserted }
    }

    /// Fetch a still of the Mac's screen. `rect` (meshd 0.5.0 "screenRegion") asks for
    /// just the part being looked at, captured at native pixels — which is what makes
    /// zooming reveal detail instead of magnifying a downsample. `MeshClient` drops it
    /// against a daemon that never grew the parameter, so the frame is simply full.
    func requestScreen(host: String, display: Int? = nil, rect: CGRect? = nil) {
        screenHost = host
        screenError = nil
        if directReachable(host), let c = client(for: host) {
            Task {
                do {
                    // Screen peek is a still you study, not a live pad, so it is worth
                    // more than the 480px default: at 480 a Mac display is a blur.
                    screenJPEGData = try await c.screenImage(display: display, width: 960, rect: rect)
                    screenUpdatedISO = ISO8601DateFormatter().string(from: Date())
                    screenError = nil
                } catch {
                    screenError = "\(shortHostName(host)) did not send a screen — asking the iPhone"
                    WatchLink.shared.send(WatchCommand(kind: .screenPeek, host: host, agent: nil, text: nil, key: nil,
                                                       display: display,
                                                       rect: rect.map { [Double($0.origin.x), Double($0.origin.y),
                                                                         Double($0.size.width), Double($0.size.height)] }))
                }
            }
        } else {
            screenJPEGData = nil
            WatchLink.shared.send(WatchCommand(kind: .screenPeek, host: host, agent: nil, text: nil, key: nil,
                                               display: display,
                                               rect: rect.map { [Double($0.origin.x), Double($0.origin.y),
                                                                 Double($0.size.width), Double($0.size.height)] }))
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
        if directReachable(host), let c = client(for: host) {
            lastError = nil
            Task {
                do {
                    try await c.newPane(agent: agent)
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
        if directReachable(host), let c = client(for: host) {
            lastError = nil
            Task {
                do {
                    try await c.kill(agent: agent)
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
        if directReachable(host), let c = client(for: host) {
            lastError = nil
            Task {
                do {
                    try await c.killPane(agent: agent, paneId: pane)
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

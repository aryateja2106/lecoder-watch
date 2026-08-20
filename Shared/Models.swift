import Foundation

// MARK: - Machine

/// A machine on the Tailscale mesh that runs `meshd`.
struct Machine: Codable, Identifiable, Hashable {
    var id: String { host }
    var host: String          // display name, e.g. "arya-macbook-pro"
    var ip: String            // tailscale IP, e.g. "100.94.221.115"
    var port: Int             // meshd port, default 8899
    var token: String         // bearer token
    var bridgeURL: String?    // rmux-bridge base (tailscale-serve https); nil = not deployed
    var vncURL: String?       // noVNC/web VNC URL; nil = http://ip:6080/vnc.html

    var addresses: [String] {
        var seen = Set<String>()
        var values = [ip, host]
        #if targetEnvironment(simulator)
        if host.lowercased().contains("mac") {
            values.insert("127.0.0.1", at: 0)
        }
        #endif
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var baseURLs: [URL] {
        addresses.compactMap { URL(string: "http://\($0):\(port)") }
    }

    var baseURL: URL? { baseURLs.first }

    /// Stored bridge URL, or a known default for the Mac (tailscale-serve host),
    /// so the Terminal tab works even for machines persisted before this field existed.
    var resolvedBridge: String? {
        if let b = bridgeURL, !b.isEmpty { return b }
        // rmux-bridge runs on every mesh machine at tailnet IP:7820 (http+ws).
        return addresses.last.map { "http://\($0):7820" }
    }

    /// meshd's own remote desktop: polls /screen.jpg, posts /input. Needs no VNC
    /// server, no websockify and no Screen Sharing — unlike `resolvedVNC`, which
    /// points at a noVNC bridge that has to be installed and running separately.
    func desktopURL(display: Int? = nil) -> URL? {
        guard let base = baseURL else { return nil }
        return URL(string: "/desktop\(display.map { "?display=\($0)" } ?? "")", relativeTo: base)
    }

    var resolvedVNC: String {
        if let v = vncURL, !v.isEmpty { return v }
        let address = addresses.last ?? ip
        return "http://\(address):6080/vnc.html?autoconnect=1&resize=scale"
    }

    /// Live terminal URL for an rmux session on this machine's bridge.
    /// Pass `pane` to focus a specific pane (bridge must honor `&pane=`; see TerminalView note).
    func terminalURL(session: String, pane: String? = nil) -> URL? {
        guard let base = resolvedBridge else { return nil }
        let q = session.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? session
        var s = "\(base)/?session=\(q)"
        if let pane, !pane.isEmpty {
            let pq = pane.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pane
            s += "&pane=\(pq)"
        }
        return URL(string: s)
    }

    /// No built-in machines. Three of someone else's tailnet addresses is not a
    /// starting point, it is a bug report from every user who is not that someone —
    /// and a shipped token would be a shared secret granting keystroke injection and
    /// arbitrary shell. An empty list is the honest state: pair a machine (see
    /// `PairResult`) and the list fills itself.
    var isConfigured: Bool { !token.isEmpty }
}

// MARK: - Pairing

/// One machine as `meshd` hands it over during pairing.
struct PairedHost: Codable, Hashable {
    var host: String
    var ip: String
    var port: Int
    var token: String
}

/// The answer to `POST /pair/claim`. Pairing one machine adopts the whole fleet,
/// because the machine you paired already knows the rest from its `hosts.json`.
struct PairResult: Codable, Hashable {
    var ok: Bool
    var host: String
    var port: Int
    var token: String
    var platform: String?
    var fleet: [PairedHost]?

    /// The paired machine itself, plus its fleet, deduped — `fleet` already contains
    /// the self entry when meshd is current, but an older daemon may omit it.
    var allHosts: [PairedHost] {
        var out = [PairedHost(host: host, ip: "", port: port, token: token)]
        var seen = Set<String>()
        for entry in fleet ?? [] where !entry.ip.isEmpty && seen.insert(entry.ip).inserted {
            if entry.host == host { out[0] = entry } else { out.append(entry) }
        }
        return out.filter { !$0.ip.isEmpty && !$0.token.isEmpty }
    }
}

/// A pairing code as the user typed it: case and grouping do not matter, and neither
/// does a stray space. Mirrors `normalizeCode` in `meshd/pair.ts`.
func normalizedPairingCode(_ input: String) -> String {
    input.uppercased().filter { $0.isASCII && ($0.isNumber || ($0.isLetter && $0.isUppercase)) }
}

/// Find the machine a daemon means by `name`.
///
/// The name in an APNs payload comes from `os.hostname()` on that machine, which is not
/// always what this app has it stored as: a host imported from another machine's
/// `hosts.json` carries that file's key ("dataflow") while its own daemon says
/// "dataflowagents", and macOS reports "Aryas-MacBook-Pro.local" where pairing stored
/// "Aryas-MacBook-Pro". Exact, then case-insensitive, then leading-component prefix.
///
/// Deliberately never falls back to "the only machine with a session by that name":
/// session names are not unique across machines and typing Enter into the wrong box is
/// worse than doing nothing.
func machineMatching(_ name: String, in machines: [Machine]) -> Machine? {
    if let exact = machines.first(where: { $0.host == name }) { return exact }
    let wanted = name.lowercased()
    if let insensitive = machines.first(where: { $0.host.lowercased() == wanted }) { return insensitive }
    func head(_ value: String) -> String {
        value.lowercased().split(separator: ".").first.map(String.init) ?? value.lowercased()
    }
    let wantedHead = head(name)
    guard !wantedHead.isEmpty else { return nil }
    return machines.first {
        let mine = head($0.host)
        return !mine.isEmpty && (mine == wantedHead || mine.hasPrefix(wantedHead) || wantedHead.hasPrefix(mine))
    }
}

/// Fold newly paired hosts into the saved list. Identity is the address, because that
/// is what actually reaches the daemon; a machine renamed on the Mac must update in
/// place rather than appear twice. An existing entry keeps its user-visible name and
/// takes the fresh token, so re-pairing is also how you recover from a rotation.
func mergingPairedHosts(_ existing: [Machine], _ paired: [PairedHost]) -> [Machine] {
    var out = existing
    for entry in paired where !entry.ip.isEmpty && !entry.token.isEmpty {
        if let i = out.firstIndex(where: { $0.ip == entry.ip }) {
            out[i].token = entry.token
            out[i].port = entry.port
        } else if let i = out.firstIndex(where: { $0.host == entry.host }) {
            out[i].ip = entry.ip
            out[i].token = entry.token
            out[i].port = entry.port
        } else {
            out.append(Machine(host: entry.host, ip: entry.ip, port: entry.port, token: entry.token))
        }
    }
    return out
}

// MARK: - Stats (htop-style)

struct MemInfo: Codable, Hashable {
    var usedMB: Double
    var totalMB: Double
    var pct: Double
}

struct DiskInfo: Codable, Hashable {
    var path: String
    var usedGB: Double
    var totalGB: Double
    var pct: Double
}

struct ProcInfo: Codable, Hashable, Identifiable {
    var id: Int { pid }
    var pid: Int
    var cmd: String
    var cpuPct: Double
    var memMB: Double
    var memPct: Double
}

struct Stats: Codable, Hashable {
    var host: String
    var platform: String
    var cpuPct: Double
    var load: [Double]
    var mem: MemInfo
    var disk: DiskInfo
    var topProcs: [ProcInfo]
    var agentsCount: Int
}

struct HealthInfo: Codable, Hashable {
    var ok: Bool
    var host: String?
    var platform: String?
    var arch: String?
    var uptimeSec: Int?
    var meshdVersion: String?
    var capabilities: [String]?
}

// MARK: - Tailnet

struct TailnetPeer: Codable, Hashable, Identifiable {
    var id: String { dnsName ?? host }
    var host: String
    var dnsName: String?
    var ips: [String]
    var online: Bool
    var os: String?
}

struct TailnetSnapshot: Codable, Hashable {
    var ok: Bool
    var peers: [TailnetPeer]
    var error: String?
}

// MARK: - Agents

struct Agent: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var title: String?
    var windows: Int
    var createdISO: String?
    var attached: Bool
    var agentType: String?
    var memMB: Double?   // resident memory of this session's process tree
    var cpuPct: Double?  // summed %CPU of this session's process tree
    var panes: [Pane]?    // present when meshd supports pane listing

    /// "512 MB" / "1.2 GB" — compact memory label, or nil if unknown.
    var memLabel: String? {
        guard let mb = memMB else { return nil }
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : "\(Int(mb)) MB"
    }

    var displayName: String { title?.isEmpty == false ? title! : name }
    var isCmux: Bool { name.hasPrefix("cmux:") }
}

struct AgentOutput: Codable, Hashable {
    var name: String
    var lines: [String]
}

/// One pane within a session (a session may hold several windows/panes).
struct Pane: Codable, Hashable, Identifiable {
    var id: String { paneId }
    var paneId: String
    var windowIndex: Int
    var paneIndex: Int
    var command: String
    var active: Bool
    var windowName: String
    var currentPath: String?

    /// e.g. "0.1 claude" — short label for a chip.
    var label: String {
        let cmd = command.isEmpty ? "shell" : command
        return "\(windowIndex).\(paneIndex) \(cmd)"
    }
}

struct PaneList: Codable, Hashable {
    var name: String
    var panes: [Pane]
}

// MARK: - Usage (OpenUsage)

struct UsageLimit: Codable, Hashable, Identifiable {
    var id: String { label }
    var label: String
    var usedPct: Double?
    var resetsAtISO: String?
    var periodDurationMs: Double?
}

struct UsageModel: Codable, Hashable, Identifiable {
    var id: String { label }
    var label: String
    var pct: String
}

struct UsageProvider: Codable, Hashable, Identifiable {
    var id: String
    var displayName: String
    var plan: String?
    var limits: [UsageLimit]
    var today: String?
    var yesterday: String?
    var last30: String?
    var topModels: [UsageModel]?
}

struct UsageSnapshot: Codable, Hashable {
    var fetchedAt: String?
    var providers: [UsageProvider]
}

/// When a provider session limit resets, tap the notification to send `continue` here.
struct PinnedLimitSession: Codable, Hashable, Identifiable {
    var id: String { providerId }
    var providerId: String
    var host: String
    var sessionName: String
}

// MARK: - Agent hooks

struct AgentEvent: Codable, Hashable, Identifiable {
    var id: String
    var host: String?
    var source: String?
    var session: String?
    var level: String?
    var title: String
    var body: String?
    var createdISO: String
}

// MARK: - The live card

/// The one session worth a Lock Screen card, a Dynamic Island and a slot in the watch
/// Smart Stack, chosen from a whole mesh.
struct LiveSessionPick: Hashable {
    var host: String
    var session: String
    var agentType: String
    var state: SessionState
    var lastLine: String
    var cpuPct: Double?
    var memLabel: String?
}

/// Every session across the whole mesh that is stopped waiting on a human, newest
/// first. This is the list the product exists to show: not "here are your machines",
/// but "these two agents are blocked on you right now".
///
/// Derived from `events`, because that is the only signal that arrives without the
/// session being open — `mesh-hook` posts one the moment an agent asks a question.
/// A session that has since produced a newer, calmer event is dropped: the question
/// was answered, and a stale "needs you" row is worse than none.
func sessionsNeedingAttention(from snapshot: MeshSnapshot) -> [LiveSessionPick] {
    var latestByKey: [String: AgentEvent] = [:]
    for event in snapshot.events ?? [] {
        guard let host = event.host, let session = event.session else { continue }
        let key = "\(host)\u{1}\(session)"
        // `events` arrives oldest first, so a later one always wins.
        latestByKey[key] = event
    }

    return (snapshot.events ?? []).reversed().compactMap { event -> LiveSessionPick? in
        guard let host = event.host, let session = event.session else { return nil }
        guard latestByKey["\(host)\u{1}\(session)"]?.id == event.id else { return nil }  // superseded
        let state = cardStateForLevel(event.level)
        guard state.wantsAttentionState else { return nil }
        guard let agent = snapshot.machines.first(where: { $0.host == host })?
                .agents.first(where: { $0.name == session }) else { return nil }
        return LiveSessionPick(host: host, session: session, agentType: agent.agentType ?? "shell",
                               state: state, lastLine: String((event.body ?? event.title).prefix(80)),
                               cpuPct: agent.cpuPct, memLabel: agent.memLabel)
    }
}

/// Pick the session that deserves the live card, or nil for "show nothing".
///
/// Two reasons qualify and no others. A session that is **blocked or broken** is the
/// whole point — that is the interruption worth carrying on your wrist. A session the
/// user is **actively watching** qualifies because they have already said they care.
/// A merely-busy session somewhere in the fleet does not: a permanent card that says
/// "Working" is wallpaper, and every update spends a budget ActivityKit enforces.
func liveSessionPick(from snapshot: MeshSnapshot) -> LiveSessionPick? {
    if let blocked = sessionsNeedingAttention(from: snapshot).first { return blocked }

    // The session the user opened. Its real output beats any event guess.
    if let host = snapshot.watchedHost, let name = snapshot.watchedAgent,
       let match = snapshot.machines.first(where: { $0.host == host })?
           .agents.first(where: { $0.name == name }) {
        let lines = snapshot.watchedOutput ?? []
        let state = lines.isEmpty ? (match.attached ? SessionState.running : .idle)
                                  : sessionState(lines: lines, attached: match.attached)
        let last = lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return LiveSessionPick(host: host, session: name, agentType: match.agentType ?? "shell",
                               state: state, lastLine: String(last.prefix(80)),
                               cpuPct: match.cpuPct, memLabel: match.memLabel)
    }

    return nil
}

/// Level-to-state, duplicated free of SwiftUI so the selection above stays testable
/// with bare swiftc. `cardState(forLevel:attached:)` in SessionCard.swift wraps it.
func cardStateForLevel(_ level: String?) -> SessionState {
    switch (level ?? "").lowercased() {
    case "warning": return .waiting
    case "error":   return .error
    default:        return .unknown
    }
}

// MARK: - Relay envelope (iPhone -> Watch over WatchConnectivity)

/// One bundle the phone pushes to the watch so the watch never talks to the mesh directly.
struct MeshSnapshot: Codable, Hashable {
    var updatedISO: String
    var machines: [MachineSnapshot]
    var usage: UsageSnapshot?
    var quickCommands: [String]?
    var events: [AgentEvent]? = nil
    var screenHost: String? = nil
    var screenFetchedISO: String? = nil
    var screenJPEGData: Data? = nil
    var screenError: String? = nil
    // Live output the phone relays for the agent the watch is currently watching.
    var watchedHost: String?
    var watchedAgent: String?
    var watchedPane: String?
    var watchedOutput: [String]?
    var pinnedLimitSessions: [PinnedLimitSession]? = nil
}

struct MachineSnapshot: Codable, Hashable, Identifiable {
    var id: String { host }
    var host: String
    /// The phone's own config for this machine — address, port and current token.
    /// The watch ships hard-coded defaults that go stale the moment a token is
    /// rotated, which silently demotes it to the slow relay; this keeps it honest.
    var config: Machine? = nil
    var reachable: Bool
    var stats: Stats?
    var agents: [Agent]
    var error: String? = nil
    var authError: String? = nil
    var bridgeReachable: Bool? = nil
    var bridgeError: String? = nil
    var vncReachable: Bool? = nil
    var vncError: String? = nil
    var meshdVersion: String? = nil
    var capabilities: [String]? = nil
    var tailnetPeers: [TailnetPeer]? = nil
    var tailnetError: String? = nil
    /// Seconds since this host last actually answered. Non-nil means the data shown is
    /// remembered, not fresh — a relayed tailnet drops polls, and blanking the whole
    /// machine on the first miss is what made the app look broken every few minutes.
    var staleSeconds: Int? = nil

    var isStale: Bool { (staleSeconds ?? 0) > 0 }

    /// "offline" only once it has really stopped answering.
    var statusLabel: String {
        if let authError { return authError }
        if reachable && !isStale { return "online" }
        if let staleSeconds, reachable { return "last seen \(Self.age(staleSeconds))" }
        return error ?? "offline"
    }

    static func age(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

/// Version, build and the moment this binary was produced. The build date comes from
/// the bundle itself, so it changes on every build with nothing to remember to bump —
/// which is the whole point when you are sideloading several times an hour.
enum BuildInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
    static var builtAt: Date? {
        guard let url = Bundle.main.executableURL,
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        else { return nil }
        return values.contentModificationDate
    }
    /// "0.1.0 (1) · built 20 Aug 14:32"
    static var summary: String {
        var text = "\(version) (\(build))"
        if let builtAt {
            let f = DateFormatter()
            f.dateFormat = "d MMM HH:mm"
            text += " · built \(f.string(from: builtAt))"
        }
        return text
    }
}

/// iOS refuses local-network traffic until the user grants it, and Tailscale's
/// 100.64.0.0/10 range counts as local network. A denied app does not get an error
/// saying so — URLSession returns NSURLErrorTimedOut, and after the first attempt it
/// returns it *immediately* rather than waiting out the timeout. That impossibly fast
/// "timeout" is the only signal we get, so it is the one we detect.
///
/// Measured on device: first attempt 16s (a real timeout across two addresses), every
/// attempt after 6ms.
func looksLikeLocalNetworkDenial(error: Error, elapsed: TimeInterval) -> Bool {
    guard elapsed < 0.5 else { return false }
    guard let urlError = error as? URLError else { return false }
    return urlError.code == .timedOut || urlError.code == .cannotConnectToHost
}

/// Addresses iOS gates behind the Local Network permission.
func isLocalNetworkAddress(_ host: String) -> Bool {
    let parts = host.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4 else { return false }
    if parts[0] == 10 { return true }
    if parts[0] == 192 && parts[1] == 168 { return true }
    if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
    // 100.64.0.0/10 — CGNAT, which is where every Tailscale address lives.
    if parts[0] == 100 && (64...127).contains(parts[1]) { return true }
    return false
}

// MARK: - Mac remote control (meshd 0.2.2+, macOS hosts)

/// One synthetic input event for the Mac. Mirrors `bin/mesh-input`'s NDJSON shape;
/// nil fields are omitted by JSONEncoder, so the wire stays small enough to batch.
struct InputEvent: Codable, Hashable {
    var t: String
    var dx: Double? = nil
    var dy: Double? = nil
    var x: Double? = nil
    var y: Double? = nil
    var button: String? = nil
    var count: Int? = nil
    var key: String? = nil
    var mods: [String]? = nil
    var s: String? = nil
    var place: String? = nil
    var display: Int? = nil

    static func move(dx: Double, dy: Double) -> InputEvent { .init(t: "move", dx: dx, dy: dy) }
    /// Normalized 0…1 within one display — the same frame `/screen.jpg?display=` shows.
    static func moveTo(x: Double, y: Double, display: Int? = nil) -> InputEvent {
        .init(t: "moveTo", x: x, y: y, display: display)
    }
    static func click(_ button: String = "left", count: Int = 1) -> InputEvent {
        .init(t: "click", button: button, count: count)
    }
    static let hold = InputEvent(t: "down")
    static let release = InputEvent(t: "up")
    static func scroll(dx: Double = 0, dy: Double = 0) -> InputEvent { .init(t: "scroll", dx: dx, dy: dy) }
    static func key(_ key: String, _ mods: [String] = []) -> InputEvent {
        .init(t: "key", key: key, mods: mods.isEmpty ? nil : mods)
    }
    static func text(_ s: String) -> InputEvent { .init(t: "text", s: s) }
    /// Media / brightness / keyboard-backlight — the NX channel, not a keycode.
    static func media(_ key: String) -> InputEvent { .init(t: "media", key: key) }
    /// Snap the frontmost window: left, right, top, bottom, center, full.
    static func window(_ place: String, display: Int? = nil) -> InputEvent {
        .init(t: "window", place: place, display: display)
    }
}

struct InputStatus: Codable, Hashable {
    var ok: Bool
    /// False until the helper binary is in System Settings › Privacy › Accessibility.
    /// Quartz drops every event silently until then, so the UI has to say it out loud.
    var trusted: Bool
    var helper: String?
    var hint: String?
    var error: String?
}

struct DisplayInfo: Codable, Hashable, Identifiable {
    var id: Int { index }
    /// 1-based and shared with `screencapture -D`, so the preview and the cursor
    /// coordinates always mean the same screen.
    var index: Int
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var main: Bool?
    var name: String?

    var label: String { name ?? "Display \(index)" }
    var aspect: Double { height > 0 ? Double(width) / Double(height) : 1.6 }
}

struct DisplayList: Codable, Hashable {
    var ok: Bool
    var displays: [DisplayInfo]
}

struct MacApp: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var bundleID: String?
    var front: Bool?
}

struct AppList: Codable, Hashable {
    var ok: Bool
    var front: String?
    var running: [MacApp]
    var installed: [String]
}

struct VolumeState: Codable, Hashable {
    var ok: Bool
    var level: Int?
    var muted: Bool?
    var error: String?
}

/// Wrist rotation → cursor velocity, the air-mouse mapping.
///
/// WowMouse does this on Wear OS by pairing as a Bluetooth HID mouse. watchOS gives
/// third-party apps no HID peripheral role at all, so that exact route is closed to
/// us — but the useful half is the motion mapping, and CoreMotion gives us the same
/// signal. We send the resulting delta over the network instead of over HID.
///
/// Rotation *rate* rather than attitude: rate is self-centring (stop moving your arm
/// and the cursor stops), where attitude drifts and needs a re-zero. The deadzone
/// exists because a resting wrist is never actually still.
/// ponytail: sensitivity and deadzone are the calibration knobs — a wrist is not a
/// mouse and these want tuning per person, not per first principles.
func airMouseDelta(pitchRate: Double, yawRate: Double,
                   sensitivity: Double = 9, deadzone: Double = 0.06) -> CGVector? {
    guard sensitivity > 0 else { return nil }
    // Ignore tremor, but measure the throw from the deadzone edge so crossing it is
    // smooth instead of jumping by a whole deadzone's worth.
    func shaped(_ rate: Double) -> Double {
        let magnitude = abs(rate)
        guard magnitude > deadzone else { return 0 }
        return (magnitude - deadzone) * (rate < 0 ? -1 : 1) * sensitivity
    }
    let dx = shaped(yawRate)
    let dy = shaped(pitchRate)
    return (dx == 0 && dy == 0) ? nil : CGVector(dx: dx, dy: dy)
}

/// Pointer gain for one drag callback, given the distance that callback moved.
///
/// A fixed multiplier cannot serve both jobs: what makes a 40mm pad cross a 3432pt
/// two-screen arrangement in one flick makes it impossible to hit a close button. So
/// slow movement stays near the base gain for precision and fast movement scales up.
/// ponytail: tuned by feel on a 46mm watch — these three numbers are the knob.
func pointerGain(step: Double, base: Double = 2.2, softening: Double = 6, ceiling: Double = 3.5) -> Double {
    guard step > 0, softening > 0 else { return base }
    return base * min(ceiling, 1 + step / softening)
}

/// Where a tap on the watch's screen preview lands, as 0…1 of the actual screenshot.
///
/// The preview is scaled to fit, so it is letterboxed whenever its aspect ratio differs
/// from its container's — a 16:9 external display shown in a 1.54 slot. Mapping the tap
/// against the container rather than the drawn image would put the cursor somewhere
/// else entirely. Returns nil for taps in the letterbox, which point at no pixel.
func normalizedPreviewPoint(tap: CGPoint, container: CGSize, imageAspect: Double) -> CGPoint? {
    guard container.width > 0, container.height > 0, imageAspect > 0 else { return nil }
    let containerAspect = Double(container.width / container.height)
    let drawn = imageAspect > containerAspect
        ? CGSize(width: container.width, height: container.width / imageAspect)
        : CGSize(width: container.height * imageAspect, height: container.height)
    let origin = CGPoint(x: (container.width - drawn.width) / 2,
                         y: (container.height - drawn.height) / 2)
    let x = (tap.x - origin.x) / drawn.width
    let y = (tap.y - origin.y) / drawn.height
    guard (0...1).contains(x), (0...1).contains(y) else { return nil }
    return CGPoint(x: x, y: y)
}

// MARK: - Watch -> Phone command

enum WatchCommandKind: String, Codable {
    case refresh
    case agentSend
    case agentOutput
    case screenPeek
    case newAgent
    case newPane
    case killAgent
    case killPane
    case input
    case volume
    case clipboard
    case system
    case readClipboard
    case inputStatus
    case listApps
    case activateApp
    case listDisplays
}

struct WatchCommand: Codable {
    var kind: WatchCommandKind
    var host: String?
    var agent: String?
    var text: String?
    var key: String?
    var pane: String? = nil
    var cmd: String? = nil
    var initialText: String? = nil
    var input: [InputEvent]? = nil
    var display: Int? = nil
    var volumeDelta: Int? = nil
    var volumeMuted: Bool? = nil
}

// MARK: - Tiny local phrase mapper

func shellCommand(from phrase: String) -> String {
    let raw = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = raw.lowercased()
    guard !raw.isEmpty else { return "" }

    if ["list", "list files", "show files", "ls"].contains(lower) { return "ls" }
    if ["where am i", "current directory", "pwd"].contains(lower) { return "pwd" }
    if lower == "git status" || lower == "status" { return "git status" }
    if lower == "git pull" || lower == "pull latest" { return "git pull" }
    if lower == "git push" || lower == "push changes" { return "git push" }
    if ["run tests", "test", "run test"].contains(lower) { return "make test" }
    if ["npm install", "install packages"].contains(lower) { return "npm install" }
    if ["npm test", "run npm tests"].contains(lower) { return "npm test" }
    if ["npm build", "build npm"].contains(lower) { return "npm run build" }
    if ["bun install"].contains(lower) { return "bun install" }
    if ["bun test", "run bun tests"].contains(lower) { return "bun test" }
    if lower == "clear" || lower == "clear screen" { return "clear" }
    if lower == "continue" { return "continue" }
    if ["go back", "up one", "parent directory", "cd dot dot"].contains(lower) { return "cd .." }
    if ["home", "go home", "cd home"].contains(lower) { return "cd ~" }
    if ["projects", "go projects", "go to projects"].contains(lower) { return "cd ~/Projects" }
    if ["desktop", "go desktop", "go to desktop"].contains(lower) { return "cd ~/Desktop" }
    if ["downloads", "go downloads", "go to downloads"].contains(lower) { return "cd ~/Downloads" }
    if ["list all", "show hidden files", "list hidden files"].contains(lower) { return "ls -la" }
    if lower == "start claude" || lower == "run claude" { return "claude" }
    if lower == "start codex" || lower == "run codex" { return "codex" }
    if ["check mesh", "mesh check", "run self check", "run self-check", "self check", "self-check"].contains(lower) {
        return "~/.mesh/bin/mesh-self-check"
    }
    if ["tailscale status", "tail scale status", "check tailscale", "check tail scale"].contains(lower) {
        return "tailscale status"
    }
    if ["check bridge", "terminal bridge", "check terminal bridge"].contains(lower) {
        return "curl -fsS http://127.0.0.1:7820/ >/dev/null && echo bridge OK"
    }

    for prefix in ["go to ", "open folder ", "change directory to ", "cd "] {
        if lower.hasPrefix(prefix) {
            let path = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? "" : "cd \(shellQuotedArgument(path))"
        }
    }
    for prefix in ["make directory ", "create folder ", "mkdir "] {
        if lower.hasPrefix(prefix) {
            let path = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? "" : "mkdir -p \(shellQuotedArgument(path))"
        }
    }
    for prefix in ["touch file ", "create file ", "touch "] {
        if lower.hasPrefix(prefix) {
            let path = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? "" : "touch \(shellQuotedArgument(path))"
        }
    }
    for prefix in ["search for ", "grep for ", "find text "] {
        if lower.hasPrefix(prefix) {
            let term = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return term.isEmpty ? "" : "grep -R \(shellQuotedArgument(term)) ."
        }
    }
    for prefix in ["ask claude to ", "tell claude to ", "claude "] {
        if lower.hasPrefix(prefix) {
            let task = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return task.isEmpty ? "claude" : "claude \(shellQuotedArgument(task))"
        }
    }
    for prefix in ["ask codex to ", "tell codex to ", "codex "] {
        if lower.hasPrefix(prefix) {
            let task = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return task.isEmpty ? "codex" : "codex \(shellQuotedArgument(task))"
        }
    }

    return raw
}

func shellQuotedArgument(_ value: String) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-:@"))
    if !value.isEmpty, value.rangeOfCharacter(from: safe.inverted) == nil {
        return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - Session state inference

/// Coarse, output-derived state so the UI can show "waiting / running / idle / error"
/// instead of a meaningless attached flag — the difference between "my agent needs me"
/// and "it's still thinking" at a glance.
/// ponytail: pure heuristic over the captured tail, no agent-specific protocol. Tighten
/// the marker lists (or fold in /events hook signals) if it misclassifies in practice.
extension SessionState {
    /// The states that justify interrupting someone. Kept next to the enum and free of
    /// SwiftUI so `liveSessionPick` stays checkable; `wantsAttention` in
    /// SessionCard.swift is the same predicate for view code.
    var wantsAttentionState: Bool { self == .waiting || self == .error }
}

enum SessionState: String {
    case waiting   // shell/agent is asking the user something — needs attention
    case running   // producing output, no prompt yet — busy
    case idle      // sitting at a shell prompt, ready for input
    case error     // recent output looks like a failure
    case unknown

    var label: String {
        switch self {
        case .waiting: return "waiting"
        case .running: return "running"
        case .idle:    return "idle"
        case .error:   return "error"
        case .unknown: return "—"
        }
    }
}

func sessionState(lines: [String], attached: Bool) -> SessionState {
    let nonEmpty = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard let last = nonEmpty.last else { return attached ? .running : .unknown }
    let tail = nonEmpty.suffix(6).joined(separator: "\n").lowercased()

    // 1. A decision prompt always wins — this is the "needs the human" signal.
    let waitMarkers = ["(y/n)", "[y/n]", "y/n)", "(yes/no)", "[yes]", "do you want",
                       "proceed?", "continue?", "press enter", "❯ 1.", "1. yes",
                       "allow?", "approve", "overwrite?", "would you like"]
    if waitMarkers.contains(where: { tail.contains($0) }) { return .waiting }

    // 2. Back at a shell prompt → ready (any error is already in the past).
    if isShellPrompt(last) { return .idle }

    // 3. Current output looks like a failure.
    let errMarkers = ["error:", "fatal:", "panic:", "traceback (most recent",
                      "command not found", "no such file", "permission denied", "exception"]
    if errMarkers.contains(where: { tail.contains($0) }) { return .error }

    // 4. Output present, no prompt, not waiting → something is running.
    return attached ? .running : .idle
}

/// Last line looks like an interactive shell prompt waiting for input.
private func isShellPrompt(_ line: String) -> Bool {
    guard let last = line.last else { return false }
    if "$%#>".contains(last) { return true }                       // bash / zsh / root / generic
    if line.hasSuffix("❯") || line.hasSuffix("→") { return true }  // starship / pure / zsh themes
    return false
}

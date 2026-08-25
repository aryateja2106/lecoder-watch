import Foundation
import CoreGraphics

/// Talks to a single machine's `meshd` over Tailscale. iPhone-only (the watch never calls this).
struct MeshClient {
    let machine: Machine

    /// Tailscale does not always find a direct path. When it falls back to a DERP
    /// relay a single round trip measures ~0.5s, so 3s was declaring healthy machines
    /// dead. The phone can afford to wait; the watch polls three machines over two
    /// addresses each and cannot, so it keeps a tight budget and backs off instead.
    var timeout: TimeInterval = {
        #if os(watchOS)
        return 1.5
        #else
        return 8
        #endif
    }()

    /// The capabilities this machine's daemon advertised on `/health` (or in the
    /// relayed snapshot), passed in by the caller. The 0.5.0 protocol additions are
    /// gated on these so the app keeps working against deployed 0.4.1 daemons:
    /// when the list is absent or lacks a capability, the gated query params below
    /// are silently omitted — the request degrades to exactly what an old daemon
    /// serves anyway — and the gated *methods* refuse with `.unsupported` instead
    /// of 404ing a daemon that never grew the route.
    var capabilities: [String]? = nil

    /// Whether the daemon advertised a capability. `nil` capabilities read as
    /// "assume old daemon" — the conservative answer for everything gated.
    func supports(_ capability: String) -> Bool {
        capabilities?.contains(capability) ?? false
    }

    enum MeshError: Error {
        case badURL, http(Int), decode
        /// The daemon did not advertise the named capability, so the call was
        /// refused client-side rather than sent to a route that does not exist.
        case unsupported(String)
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard !machine.baseURLs.isEmpty else {
            throw MeshError.badURL
        }
        var lastError: Error?
        for base in machine.baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = timeout
            req.setValue("Bearer \(machine.token)", forHTTPHeaderField: "Authorization")
            if let body {
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw MeshError.http(http.statusCode)
                }
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MeshError.badURL
    }

    /// Redeem a one-time pairing code (`mesh pair` on the machine) for its real
    /// token. This is the only call that runs without one, so it is deliberately
    /// static — there is no configured `Machine` yet, which is the point.
    static func claimPair(address: String, port: Int, code: String) async throws -> PairResult {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let url = URL(string: "http://\(host):\(port)/pair/claim") else {
            throw MeshError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["code": normalizedPairingCode(code)])
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MeshError.http(http.statusCode)
        }
        return try JSONDecoder().decode(PairResult.self, from: data)
    }

    func health() async throws -> Bool {
        _ = try await request("/health")
        return true
    }

    func healthInfo() async throws -> HealthInfo {
        let data = try await request("/health")
        return try JSONDecoder().decode(HealthInfo.self, from: data)
    }

    func stats() async throws -> Stats {
        let data = try await request("/stats")
        return try JSONDecoder().decode(Stats.self, from: data)
    }

    /// Setup truth for this machine. `fix: true` POSTs /doctor/fix, which makes macOS
    /// show the Accessibility and Screen Recording dialogs on that Mac — the only way
    /// to prompt for them, since TCC only ever asks from the process that needs the
    /// grant. The report comes back either way so the UI can show what still failed.
    func doctor(fix: Bool = false) async throws -> DoctorReport {
        let data = try await request(fix ? "/doctor/fix" : "/doctor", method: fix ? "POST" : "GET")
        return try JSONDecoder().decode(DoctorReport.self, from: data)
    }

    func agents() async throws -> [Agent] {
        let data = try await request("/agents")
        return try JSONDecoder().decode([Agent].self, from: data)
    }

    func usage() async throws -> UsageSnapshot {
        let data = try await request("/usage")
        return try JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    /// Whole main screen, or one display when `display` is given (1-based).
    ///
    /// `width` is the longest edge; meshd clamps it to 240…2000 and defaults to 480.
    /// It used to be honoured ONLY on the `?display=` path, so a caller that did not name
    /// a display silently got 480px however much detail it asked for — and the client only
    /// names a display when the Mac has more than one. On a single-display Mac, which is
    /// most of them, no width could ever take effect. Both paths now carry it.
    /// meshd 0.5.0+ ("screenRegion"): `rect` crops to a normalized region of the
    /// display — x, y, w, h in 0…1, top-left origin, the same rect
    /// `visibleRect(zoom:pan:containerAspect:imageAspect:)` computes — captured at
    /// NATIVE pixel resolution, which is what makes zoom sharp instead of a blur of
    /// stretched downsample. `quality` (1…100) sets the JPEG encode quality. Both are
    /// sent only when `capabilities` advertise "screenRegion": an old daemon ignores
    /// unknown params but must never be *interpreted* as having cropped, so the
    /// client simply never asks one for a crop.
    func screenImage(display: Int? = nil, width: Int? = nil,
                     rect: CGRect? = nil, quality: Int? = nil) async throws -> Data {
        var query: [String] = []
        if let display { query.append("display=\(display)") }
        if let width { query.append("width=\(min(2000, max(240, width)))") }
        if supports("screenRegion") {
            if let rect {
                // Clamp into the unit square and drop degenerate slivers — the daemon
                // rejects w/h ≤ 0.01 with a 400, and a full frame beats a hard error.
                let x = min(max(Double(rect.origin.x), 0), 1)
                let y = min(max(Double(rect.origin.y), 0), 1)
                let w = min(max(Double(rect.size.width), 0), 1 - x)
                let h = min(max(Double(rect.size.height), 0), 1 - y)
                if w > 0.01, h > 0.01 {
                    query.append(String(format: "x=%.4f&y=%.4f&w=%.4f&h=%.4f", x, y, w, h))
                }
            }
            if let quality { query.append("q=\(min(100, max(1, quality)))") }
        }
        let suffix = query.isEmpty ? "" : "?" + query.joined(separator: "&")
        return try await request("/screen.jpg" + suffix)
    }

    func displays() async throws -> DisplayList {
        let data = try await request("/displays")
        return try JSONDecoder().decode(DisplayList.self, from: data)
    }

    func tailnet() async throws -> TailnetSnapshot {
        let data = try await request("/tailnet")
        return try JSONDecoder().decode(TailnetSnapshot.self, from: data)
    }

    func events(since: String? = nil) async throws -> [AgentEvent] {
        let query = since.map { "?since=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" } ?? ""
        let data = try await request("/events\(query)")
        return try JSONDecoder().decode([AgentEvent].self, from: data)
    }

    func panes(agent: String) async throws -> [Pane] {
        let data = try await request("/agents/\(agent)/panes")
        return try JSONDecoder().decode(PaneList.self, from: data).panes
    }

    /// meshd 0.5.0+ ("captureJoin"): `join` unwraps soft-wrapped physical lines back
    /// into logical ones (`capture-pane -J`), and `plain` additionally strips
    /// box-drawing and braille-spinner glyphs and collapses space runs — the reader
    /// mode a 21-column watch needs. Sent only when the daemon advertises the
    /// capability; against an old daemon the flags are dropped and the output is
    /// byte-identical to today's.
    func output(agent: String, lines: Int = 80, pane: String? = nil,
                join: Bool = false, plain: Bool = false) async throws -> AgentOutput {
        var path = "/agents/\(agent)/output?lines=\(lines)"
        if let pane, !pane.isEmpty {
            let enc = pane.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pane
            path += "&pane=\(enc)"
        }
        if supports("captureJoin") {
            if join { path += "&join=1" }
            if plain { path += "&plain=1" }
        }
        let data = try await request(path)
        return try JSONDecoder().decode(AgentOutput.self, from: data)
    }

    /// meshd 0.5.0+ ("paste"): `paste: true` asks the daemon to deliver multi-line
    /// text via `load-buffer` + bracketed `paste-buffer` instead of keystrokes, so a
    /// TUI like Claude Code receives one paste rather than a submit per newline. The
    /// flag is only put on the wire when advertised; the daemon itself also falls
    /// back to the send-keys path when the buffer route fails, so either end being
    /// old degrades to today's behavior.
    func send(agent: String, text: String? = nil, key: String? = nil, pane: String? = nil,
              paste: Bool = false) async throws {
        var payload: [String: Any] = [:]
        if let text { payload["text"] = text }
        if let key { payload["key"] = key }
        if let pane, !pane.isEmpty { payload["pane"] = pane }
        if paste, supports("paste") { payload["paste"] = true }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("/agents/\(agent)/send", method: "POST", body: body)
    }

    /// Create a new rmux session (optionally launching a command, e.g. "claude" / "codex").
    ///
    /// `cols`/`rows` (meshd 0.5.0+) set the new PTY's size, so a session created
    /// from the wrist can be 60×30 instead of a default 80×24 that wraps four times
    /// on a watch. Sent unconditionally: the daemon reads only the fields it knows,
    /// so an old one ignores them and creates the session at its default size —
    /// harmless, and gating would buy nothing.
    func newSession(name: String, cmd: String? = nil, cwd: String? = nil, initialText: String? = nil,
                    cols: Int? = nil, rows: Int? = nil) async throws {
        var payload: [String: Any] = ["name": name]
        if let cmd, !cmd.isEmpty { payload["cmd"] = cmd }
        if let cwd, !cwd.isEmpty { payload["cwd"] = cwd }
        if let initialText, !initialText.isEmpty { payload["initialText"] = initialText }
        if let cols, cols > 0 { payload["cols"] = cols }
        if let rows, rows > 0 { payload["rows"] = rows }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("/agents/new", method: "POST", body: body)
    }

    // MARK: - Remote files (endpoints live since 0.4.x — /fs ships in every deployed daemon)

    /// List a directory on the machine. `nil` path = the daemon's home directory.
    func fsList(path: String? = nil) async throws -> FsListing {
        let query = path.map {
            "?path=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)"
        } ?? ""
        let data = try await request("/fs\(query)")
        return try JSONDecoder().decode(FsListing.self, from: data)
    }

    /// Create a directory (recursively, like `mkdir -p`) on the machine.
    func fsMkdir(path: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["path": path])
        _ = try await request("/fs/mkdir", method: "POST", body: body)
    }

    func newPane(agent: String) async throws {
        let enc = agent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agent
        let body = try JSONSerialization.data(withJSONObject: [:])
        _ = try await request("/agents/\(enc)/panes", method: "POST", body: body)
    }

    /// Kill (delete) an rmux session entirely.
    func kill(agent: String) async throws {
        let enc = agent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agent
        _ = try await request("/agents/\(enc)", method: "DELETE")
    }

    // MARK: - Mac remote control

    /// Is the Mac's input helper allowed to inject events yet? `?prompt=1` makes
    /// macOS raise the Accessibility dialog on that Mac.
    func inputStatus(prompt: Bool = false) async throws -> InputStatus {
        let data = try await request("/input\(prompt ? "?prompt=1" : "")")
        return try JSONDecoder().decode(InputStatus.self, from: data)
    }

    /// Batch — a drag is dozens of moves, and one request per move would be all latency.
    func input(_ events: [InputEvent]) async throws {
        guard !events.isEmpty else { return }
        let body = try JSONEncoder().encode(["events": events])
        _ = try await request("/input", method: "POST", body: body)
    }

    func clipboard() async throws -> String {
        let data = try await request("/clipboard")
        return try JSONDecoder().decode([String: String].self, from: data)["text"] ?? ""
    }

    func setClipboard(_ text: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["text": text])
        _ = try await request("/clipboard", method: "POST", body: body)
    }

    /// Pass `level` (0…100) or `delta`, and/or `muted`. No arguments = read current.
    @discardableResult
    func volume(level: Int? = nil, delta: Int? = nil, muted: Bool? = nil) async throws -> VolumeState {
        var payload: [String: Any] = [:]
        if let level { payload["level"] = level }
        if let delta { payload["delta"] = delta }
        if let muted { payload["muted"] = muted }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request("/volume", method: "POST", body: body)
        return try JSONDecoder().decode(VolumeState.self, from: data)
    }

    /// Running and installed apps on the Mac.
    func apps() async throws -> AppList {
        let data = try await request("/apps")
        return try JSONDecoder().decode(AppList.self, from: data)
    }

    /// Bring an app to the front, launching it if needed.
    func activateApp(_ name: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["activate": name])
        _ = try await request("/apps", method: "POST", body: body)
    }

    /// Register this phone's APNs device token so meshd can push alerts directly.
    func registerPush(deviceToken: String) async throws {
        // Read from the embedded profile, never hardcoded: a TestFlight build's token
        // is only valid at the production gateway, and sending it to the sandbox one
        // gets BadDeviceToken — which used to make meshd drop the device for good.
        let body = try JSONSerialization.data(withJSONObject: ["token": deviceToken, "env": APNsEnvironment.current])
        _ = try await request("/push/register", method: "POST", body: body)
    }

    /// Ask THIS machine to broadcast a Wake-on-LAN magic packet for a sleeping
    /// peer. The phone can't send one itself from across the tailnet — WoL is a
    /// LAN broadcast — so any awake machine on the same network does it instead.
    ///
    /// `via` is the sleeping target's directed broadcast address (derived from its
    /// cached /health ipv4+netmask), so a peer aims the packet into the target's
    /// subnet instead of spraying its own. Deployed daemons ≥0.4.0 already accept
    /// an explicit `broadcast` in the body; omitted = today's behavior.
    func wake(mac: String, via broadcast: String? = nil) async throws {
        var payload: [String: String] = ["mac": mac]
        if let broadcast, !broadcast.isEmpty { payload["broadcast"] = broadcast }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("/wake", method: "POST", body: body)
    }

    /// Power/session action: displaysleep, lock, screensaver, sleep.
    func system(_ action: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["action": action])
        _ = try await request("/system", method: "POST", body: body)
    }

    /// `system(_:)` with the truth kept: meshd 0.5.0 runs every /system action
    /// through a checked spawn and reports {ok, exitCode, stderr} honestly, so a
    /// failed `pmset` finally *looks* failed instead of rendering as success. Old
    /// daemons answer {ok:true, action} no matter what happened — `SystemResult`
    /// decodes both shapes.
    ///
    /// The two 0.5.0-only actions, "shutdown" and "restart", are refused client-side
    /// unless the daemon advertises "power": an old daemon would reject them anyway,
    /// and the UI should never offer a button the fleet cannot honor.
    func systemAction(_ action: String) async throws -> SystemResult {
        if (action == "shutdown" || action == "restart") && !supports("power") {
            throw MeshError.unsupported("power")
        }
        let body = try JSONSerialization.data(withJSONObject: ["action": action])
        let data = try await request("/system", method: "POST", body: body)
        return (try? JSONDecoder().decode(SystemResult.self, from: data))
            ?? SystemResult(ok: nil, exitCode: nil, stderr: nil, action: action, error: nil)
    }

    /// Open a link in the machine's default browser (meshd 0.5.0+, "openUrl") —
    /// the whole "browser on the wrist" flow is this plus the existing screen peek.
    /// http/https only, checked here as well as daemon-side: a `file:` or custom
    /// scheme launched on a remote Mac is an attack surface, not a feature.
    func openURL(_ url: URL) async throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw MeshError.badURL
        }
        guard supports("openUrl") else { throw MeshError.unsupported("openUrl") }
        let body = try JSONSerialization.data(withJSONObject: ["url": url.absoluteString])
        _ = try await request("/open", method: "POST", body: body)
    }

    /// Which Live Activity token is being registered with `uploadLAToken`.
    /// Raw values are the daemon's wire vocabulary — do not rename.
    enum LATokenKind: String {
        /// The push-to-start token: lets meshd *begin* a Live Activity remotely.
        case start
        /// A running activity's update token, scoped to one session.
        case update
    }

    /// Register a Live Activity push token so meshd can start/update/end the
    /// session card over APNs (meshd 0.5.0+, "laPush"). `session` names the mux
    /// session an update token belongs to; start tokens are session-less.
    func uploadLAToken(kind: LATokenKind, token: String, session: String? = nil) async throws {
        guard supports("laPush") else { throw MeshError.unsupported("laPush") }
        var payload: [String: String] = ["kind": kind.rawValue, "token": token]
        if let session, !session.isEmpty { payload["session"] = session }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("/la/token", method: "POST", body: body)
    }

    /// Kill a single pane within a session.
    func killPane(agent: String, paneId: String) async throws {
        let a = agent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agent
        let p = paneId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? paneId
        _ = try await request("/agents/\(a)/panes/\(p)", method: "DELETE")
    }
}

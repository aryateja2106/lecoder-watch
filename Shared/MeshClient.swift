import Foundation

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

    enum MeshError: Error { case badURL, http(Int), decode }

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

    func agents() async throws -> [Agent] {
        let data = try await request("/agents")
        return try JSONDecoder().decode([Agent].self, from: data)
    }

    func usage() async throws -> UsageSnapshot {
        let data = try await request("/usage")
        return try JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    /// Whole main screen, or one display when `display` is given (1-based).
    /// `width` is honoured only on the `?display=` path — meshd clamps it to 240…2000
    /// and defaults to 480, which is right for a watch and far too soft for a phone.
    /// Asking for a width therefore means naming a display, so callers that want a
    /// sharp picture have to know which screen they are looking at.
    func screenImage(display: Int? = nil, width: Int? = nil) async throws -> Data {
        guard let display else { return try await request("/screen.jpg") }
        let size = width.map { "&width=\(min(2000, max(240, $0)))" } ?? ""
        return try await request("/screen.jpg?display=\(display)\(size)")
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

    func output(agent: String, lines: Int = 80, pane: String? = nil) async throws -> AgentOutput {
        var path = "/agents/\(agent)/output?lines=\(lines)"
        if let pane, !pane.isEmpty {
            let enc = pane.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pane
            path += "&pane=\(enc)"
        }
        let data = try await request(path)
        return try JSONDecoder().decode(AgentOutput.self, from: data)
    }

    func send(agent: String, text: String? = nil, key: String? = nil, pane: String? = nil) async throws {
        var payload: [String: String] = [:]
        if let text { payload["text"] = text }
        if let key { payload["key"] = key }
        if let pane, !pane.isEmpty { payload["pane"] = pane }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("/agents/\(agent)/send", method: "POST", body: body)
    }

    /// Create a new rmux session (optionally launching a command, e.g. "claude" / "codex").
    func newSession(name: String, cmd: String? = nil, cwd: String? = nil, initialText: String? = nil) async throws {
        var payload: [String: String] = ["name": name]
        if let cmd, !cmd.isEmpty { payload["cmd"] = cmd }
        if let cwd, !cwd.isEmpty { payload["cwd"] = cwd }
        if let initialText, !initialText.isEmpty { payload["initialText"] = initialText }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("/agents/new", method: "POST", body: body)
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
    // ponytail: env hardcoded "dev" — flip to "prod" when a distribution-signed build exists.
    func registerPush(deviceToken: String) async throws {
        // Read from the embedded profile, never hardcoded: a TestFlight build's token
        // is only valid at the production gateway, and sending it to the sandbox one
        // gets BadDeviceToken — which used to make meshd drop the device for good.
        let body = try JSONSerialization.data(withJSONObject: ["token": deviceToken, "env": APNsEnvironment.current])
        _ = try await request("/push/register", method: "POST", body: body)
    }

    /// Power/session action: displaysleep, lock, screensaver, sleep.
    func system(_ action: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["action": action])
        _ = try await request("/system", method: "POST", body: body)
    }

    /// Kill a single pane within a session.
    func killPane(agent: String, paneId: String) async throws {
        let a = agent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agent
        let p = paneId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? paneId
        _ = try await request("/agents/\(a)/panes/\(p)", method: "DELETE")
    }
}

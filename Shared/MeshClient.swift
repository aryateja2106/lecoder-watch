import Foundation

/// Talks to a single machine's `meshd` over Tailscale. iPhone-only (the watch never calls this).
struct MeshClient {
    let machine: Machine

    enum MeshError: Error { case badURL, http(Int), decode }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let base = machine.baseURL, let url = URL(string: path, relativeTo: base) else {
            throw MeshError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 6
        req.setValue("Bearer \(machine.token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MeshError.http(http.statusCode)
        }
        return data
    }

    func health() async throws -> Bool {
        _ = try await request("/health")
        return true
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

    func panes(agent: String) async throws -> [Pane] {
        let data = try await request("/agents/\(agent)/panes")
        return try JSONDecoder().decode(PaneList.self, from: data).panes
    }

    func output(agent: String, lines: Int = 80) async throws -> AgentOutput {
        let data = try await request("/agents/\(agent)/output?lines=\(lines)")
        return try JSONDecoder().decode(AgentOutput.self, from: data)
    }

    func send(agent: String, text: String? = nil, key: String? = nil) async throws {
        var payload: [String: String] = [:]
        if let text { payload["text"] = text }
        if let key { payload["key"] = key }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("/agents/\(agent)/send", method: "POST", body: body)
    }

    /// Create a new rmux session (optionally launching a command, e.g. "claude" / "codex").
    func newSession(name: String, cmd: String? = nil, cwd: String? = nil) async throws {
        var payload: [String: String] = ["name": name]
        if let cmd, !cmd.isEmpty { payload["cmd"] = cmd }
        if let cwd, !cwd.isEmpty { payload["cwd"] = cwd }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("/agents/new", method: "POST", body: body)
    }
}

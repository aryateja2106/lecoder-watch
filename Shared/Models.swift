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

    var baseURL: URL? { URL(string: "http://\(ip):\(port)") }

    /// Stored bridge URL, or a known default for the Mac (tailscale-serve host),
    /// so the Terminal tab works even for machines persisted before this field existed.
    var resolvedBridge: String? {
        if let b = bridgeURL, !b.isEmpty { return b }
        // rmux-bridge runs on every mesh machine at tailnet IP:7820 (http+ws).
        return "http://\(ip):7820"
    }

    /// Live terminal URL for an rmux session on this machine's bridge.
    func terminalURL(session: String) -> URL? {
        guard let base = resolvedBridge else { return nil }
        let q = session.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? session
        return URL(string: "\(base)/?session=\(q)")
    }

    // NOTE: "testtoken" is a dev placeholder for local simulator verification.
    // Replace per-machine in the Settings tab with the real MESHD_TOKEN.
    static let defaults: [Machine] = [
        Machine(host: "arya-macbook-pro", ip: "100.94.221.115", port: 8899, token: "testtoken"),
        Machine(host: "arya-pi", ip: "100.94.168.17", port: 8899, token: "testtoken"),
        Machine(host: "dataflowagents", ip: "100.80.10.95", port: 8899, token: "testtoken")
    ]
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

// MARK: - Agents

struct Agent: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var windows: Int
    var createdISO: String?
    var attached: Bool
    var agentType: String?
}

struct AgentOutput: Codable, Hashable {
    var name: String
    var lines: [String]
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

// MARK: - Relay envelope (iPhone -> Watch over WatchConnectivity)

/// One bundle the phone pushes to the watch so the watch never talks to the mesh directly.
struct MeshSnapshot: Codable, Hashable {
    var updatedISO: String
    var machines: [MachineSnapshot]
    var usage: UsageSnapshot?
    // Live output the phone relays for the agent the watch is currently watching.
    var watchedHost: String?
    var watchedAgent: String?
    var watchedOutput: [String]?
}

struct MachineSnapshot: Codable, Hashable, Identifiable {
    var id: String { host }
    var host: String
    var reachable: Bool
    var stats: Stats?
    var agents: [Agent]
}

// MARK: - Watch -> Phone command

enum WatchCommandKind: String, Codable {
    case refresh
    case agentSend
    case agentOutput
    case newAgent
}

struct WatchCommand: Codable {
    var kind: WatchCommandKind
    var host: String?
    var agent: String?
    var text: String?
    var key: String?
}

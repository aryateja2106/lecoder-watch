// LocalDaemon.swift — the entire network layer of the Mac menu bar app.
//
// Every call here goes to this same Mac's daemon over loopback, which is why there is
// no token anywhere in this file. meshd treats a request arriving from 127.0.0.1 as
// authorised (server.ts `authed`), and /pair/new refuses to mint a code for anyone
// else. Asking the user to paste a token would be inventing a step the daemon does not
// have.
//
// The wire types are copied from Shared/Models.swift on purpose rather than shared:
// this target deliberately compiles nothing but MeshDesktop/, because Shared/ carries
// iOS-flavoured dependencies (ActivityKit, WidgetKit types, the phone's client) that a
// menu bar app has no business linking. Two small structs are cheaper than that.
import Foundation

enum LocalDaemon {
    /// meshd's default port. Hard-coded on purpose: an app launched from Finder or from
    /// Login Items inherits none of the shell's MESHD_PORT, so reading the environment
    /// would only ever be right by accident.
    static let port = 8899

    /// The same line the phone shows on its pairing screen (iOS/PairMachineView).
    static let installCommand =
        "curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh"

    /// The daemon's own browser console — capture plus input, served by input.ts.
    static var consoleURL: URL { url("/desktop") }

    static func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    // MARK: - Wire types

    struct Health: Decodable {
        var ok: Bool
        var host: String?
        var platform: String?
        var meshdVersion: String?
    }

    /// What GET /doctor answers (meshd/doctor.ts). Each check is tested by exercising
    /// the real path, so a green row means it works right now — not that it is
    /// configured.
    struct DoctorReport: Decodable {
        struct Check: Decodable {
            var ok: Bool
            var detail: String
            var fix: String?
        }
        var ok: Bool
        var host: String
        var platform: String
        var version: String
        var bind: String
        var checks: [String: Check]

        /// JSON object key order is not guaranteed, and a list that reshuffles on every
        /// refresh is unreadable. Same order the phone uses.
        static let order = ["token", "input", "screen", "mux", "push"]
        var orderedChecks: [(name: String, check: Check)] {
            let known = Self.order.compactMap { name in checks[name].map { (name, $0) } }
            let extra = checks.keys.filter { !Self.order.contains($0) }.sorted()
                .compactMap { name in checks[name].map { (name, $0) } }
            return known + extra
        }
        var passed: Int { checks.values.filter(\.ok).count }
        var total: Int { checks.count }
    }

    /// What GET /pair/new answers (meshd/pair.ts). Note what is missing: an address.
    /// The daemon knows the port and its own hostname; which IP a phone can actually
    /// reach is decided on this side, exactly as the CLI does it.
    struct PairCode: Decodable {
        var code: String
        var pretty: String
        var expiresISO: String
        var ttlSec: Int
        var host: String
        var port: Int
    }

    // MARK: - Calls

    static func health() async throws -> Health { try await get("/health") }

    static func doctor() async throws -> DoctorReport { try await get("/doctor") }

    /// POST /doctor/fix makes the *daemon's* processes ask for Accessibility and Screen
    /// Recording, which is the only way those dialogs can appear: macOS grants TCC to
    /// the process that requests it, so this app cannot collect them on meshd's behalf.
    /// The timeout is generous because the call returns only once the helper has run.
    static func doctorFix() async throws -> DoctorReport {
        try await send("/doctor/fix", method: "POST", timeout: 30)
    }

    static func pairNew() async throws -> PairCode { try await get("/pair/new") }

    // MARK: - Transport

    enum Failure: LocalizedError {
        case unreachable
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .unreachable: return "meshd isn't answering on 127.0.0.1:\(LocalDaemon.port)."
            case .http(404): return "This machine's daemon predates setup checks. Reinstall to update it."
            case .http(let code): return "The daemon answered \(code)."
            }
        }
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    private static func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(path, method: "GET", timeout: 3)
    }

    private static func send<T: Decodable>(_ path: String, method: String, timeout: TimeInterval) async throws -> T {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        req.timeoutInterval = timeout
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw Failure.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.unreachable }
        guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Which address a phone can reach

    /// Mirrors `reachableAddress()` in install/payload/bin/mesh: Tailscale first, then
    /// the first real IPv4 on this machine.
    ///
    /// The CLI gets its answer by running `tailscale ip -4`. A menu bar app has no PATH
    /// worth trusting and shelling out to a binary that lives in three different places
    /// depending on how Tailscale was installed is a worse bet than reading the
    /// interfaces directly — and `tailscale ip -4` only ever answers with an address in
    /// 100.64.0.0/10, the CGNAT range every tailnet is numbered from. So: prefer an
    /// address in that range, otherwise the first non-loopback IPv4. Same answer, no
    /// subprocess.
    static func reachableAddress() -> String {
        var fallback: String?
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return "" }
        defer { freeifaddrs(head) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(bitPattern: ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                              &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: buf)
            if ip.isEmpty { continue }
            if isTailscale(ip) { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback ?? ""
    }

    /// 100.64.0.0/10 — the CGNAT block Tailscale hands out from.
    private static func isTailscale(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }

    /// The deep link the QR carries. `meshwatch://`, not `mesh://` — meshwatch is the
    /// only scheme the iPhone app registers (project.yml CFBundleURLSchemes), so any
    /// other scheme scans into nothing. Byte-for-byte the URL `mesh pair` prints.
    static func pairingLink(address: String, port: Int, code: String) -> String {
        let escaped = address.addingPercentEncoding(withAllowedCharacters: encodeURIComponentSafe) ?? address
        return "meshwatch://pair?h=\(escaped)&p=\(port)&c=\(code)"
    }

    /// The exact set JavaScript's `encodeURIComponent` leaves alone, so an IP keeps its
    /// dots instead of arriving as 100%2E94%2E221%2E115.
    private static let encodeURIComponentSafe: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_.!~*'()")
        return set
    }()
}

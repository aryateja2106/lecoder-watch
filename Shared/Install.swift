import Foundation

/// The one command a user runs on any machine they want to control.
/// Served from the public mesh-install releases; see docs/mesh-cli-and-remote-install.md.
enum MeshInstall {
    static let releasesBase = "https://github.com/LeSearch-AI/mesh-install/releases/latest/download"
    static let command = "curl -fsSL \(releasesBase)/install.sh | sh"

    /// Same install, pinned to a token the phone already knows — used when adding a
    /// machine from the app so the token doesn't have to travel back by hand.
    static func command(token: String) -> String {
        "curl -fsSL \(releasesBase)/install.sh | sh -s -- --token \(token)"
    }
}

/// What `install.sh` prints when it finishes. Users paste that block into the app
/// instead of transcribing a 32-char token off a terminal.
///
/// Recognised lines (see install/install.sh, the summary block):
///   meshd URL: http://100.94.221.115:8899
///   bridge URL: http://100.94.221.115:7820
///   Tailscale IPv4: 100.94.221.115
///   MESHD token: 8f3c...
struct InstallSummary: Equatable {
    var ip: String?
    var port: Int?
    var bridgeURL: String?
    var token: String?

    var isUsable: Bool { ip != nil && token != nil }
}

func parseInstallSummary(_ text: String) -> InstallSummary {
    var summary = InstallSummary()

    for rawLine in text.split(whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard let colon = line.firstIndex(of: ":") else { continue }
        let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { continue }

        switch key {
        case "meshd url":
            // Splitting on the FIRST colon keeps the whole "http://ip:port" in `value`.
            if let url = URL(string: value), let host = url.host {
                summary.ip = host
                summary.port = url.port
            }
        case "bridge url":
            summary.bridgeURL = value
        case "tailscale ipv4":
            // Skip the "unavailable (run ...)" branch the installer prints without Tailscale.
            if isIPv4(value) { summary.ip = summary.ip ?? value }
        case "meshd token":
            summary.token = value
        default:
            continue
        }
    }
    return summary
}

private func isIPv4(_ value: String) -> Bool {
    let parts = value.split(separator: ".")
    guard parts.count == 4 else { return false }
    return parts.allSatisfy { part in
        guard let n = Int(part), (0...255).contains(n) else { return false }
        return true
    }
}

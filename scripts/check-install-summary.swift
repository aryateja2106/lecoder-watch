import Foundation

// Run: swiftc Shared/Install.swift scripts/check-install-summary.swift -o /tmp/cis && /tmp/cis

@main
struct CheckInstallSummary {
    static func main() {
        // Real tail of a successful `install.sh` run (see install/install.sh summary block).
        let full = """
        meshd: up
        rmux-bridge: up
        Tailscale IPv4: 100.94.221.115
        meshd URL: http://100.94.221.115:8899
        bridge URL: http://100.94.221.115:7820
        MESHD token: 8f3c1d2e4a5b6c7d8e9f0a1b2c3d4e5f
        Self-check: /Users/x/.mesh/bin/mesh-self-check
        Uninstall: sh install.sh --uninstall
        """
        let parsed = parseInstallSummary(full)
        assert(parsed.ip == "100.94.221.115", "ip: \(String(describing: parsed.ip))")
        assert(parsed.port == 8899, "port: \(String(describing: parsed.port))")
        assert(parsed.token == "8f3c1d2e4a5b6c7d8e9f0a1b2c3d4e5f", "token: \(String(describing: parsed.token))")
        assert(parsed.bridgeURL == "http://100.94.221.115:7820", "bridge: \(String(describing: parsed.bridgeURL))")
        assert(parsed.isUsable)

        // No Tailscale: the installer prints a prose "unavailable (...)" that must NOT
        // become an IP, and without an address there is nothing usable to save.
        let noTailscale = """
        meshd: up
        Tailscale IPv4: unavailable (run "tailscale ip -4" once Tailscale is connected)
        MESHD token: deadbeefdeadbeefdeadbeefdeadbeef
        """
        let partial = parseInstallSummary(noTailscale)
        assert(partial.ip == nil, "expected no ip, got \(String(describing: partial.ip))")
        assert(partial.token == "deadbeefdeadbeefdeadbeefdeadbeef")
        assert(!partial.isUsable, "must not be usable without an address")

        // A LAN install with no Tailscale still works if the user has the meshd URL.
        let lan = parseInstallSummary("meshd URL: http://192.168.1.42:8899\nMESHD token: abc123")
        assert(lan.ip == "192.168.1.42" && lan.port == 8899 && lan.isUsable)

        // Garbage in, nothing out — never crash on a stray paste.
        let junk = parseInstallSummary("hello world\n\n:::\nMESHD token:")
        assert(junk.token == nil, "empty value must be ignored")
        assert(!junk.isUsable)

        // A bare token pasted alone is not enough on its own.
        assert(!parseInstallSummary("MESHD token: abc").isUsable)

        // The advertised install command must stay a real public URL, not a placeholder.
        assert(MeshInstall.command.hasPrefix("curl -fsSL https://"), MeshInstall.command)
        assert(!MeshInstall.command.contains("<host>") && !MeshInstall.command.contains("__MESH_SRC__"))
        assert(MeshInstall.command(token: "t0k").hasSuffix("--token t0k"))

        print("check-install-summary: OK")
    }
}

import Foundation

// Run via scripts/check-all.sh. Locks list-order and hostname display so a cleanup
// pass cannot quietly shuffle the machine list or revive personal prefix-stripping.

@main
struct CheckMachineList {
    static func main() {
        func snap(host: String, reachable: Bool, agents: Int) -> MachineSnapshot {
            MachineSnapshot(
                host: host,
                reachable: reachable,
                stats: nil,
                agents: (0..<agents).map { Agent(name: "s\($0)", windows: 1, attached: false) }
            )
        }

        let mixed = [
            snap(host: "zeta", reachable: false, agents: 9),
            snap(host: "beta", reachable: true, agents: 1),
            snap(host: "alpha", reachable: true, agents: 3),
        ]
        assert(mixed.activeFirst().map(\.host) == ["alpha", "beta", "zeta"])

        // Equal session counts fall through to name so the order is stable.
        let tied = [
            snap(host: "b", reachable: true, agents: 1),
            snap(host: "a", reachable: true, agents: 1),
        ]
        assert(tied.activeFirst().map(\.host) == ["a", "b"])
        assert([MachineSnapshot]().activeFirst().isEmpty)

        // Hostname only — not a personal "arya-" / "agents" strip.
        assert(shortHostName("studio.tailnet.ts.net") == "studio")
        assert(shortHostName("pi") == "pi")
        assert(shortHostName("arya-macbook-pro") == "arya-macbook-pro")

        assert(resetText(nil) == nil)
        assert(resetText("") == nil)
        assert(resetText("not-a-date") == nil)
        assert(resetText("2026-08-20T14:02:35Z")?.hasPrefix("resets ") == true)

        print("check-machine-list: OK")
    }
}

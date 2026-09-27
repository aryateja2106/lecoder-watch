import Foundation

// Run via `sh scripts/check-all.sh`, which compiles every check-*.swift against the
// full Shared/ dependency set (Models.swift is not standalone).
//
// Pins mergeDuplicateMachineRows: two machine rows whose /health hardware MAC matches
// are one physical box paired twice. The live case (2026-08-29): a fleet-adopted
// "mac" alias sitting beside "arya-macbook-pro", both listing the same 8 sessions on
// every screen. The merge must keep the better row, absorb the loser's config, and
// hand the loser BACK WITH its keeper so the store can tombstone selectively —
// tombstoning a shared ip would ban the keeper from future fleet adoption.

func machine(_ host: String, ip: String, mac: String?, bridge: String? = nil, vnc: String? = nil) -> Machine {
    Machine(uid: UUID(), host: host, ip: ip, port: 8899, token: "t",
            bridgeURL: bridge, vncURL: vnc, macAddress: mac)
}

@main
struct CheckMachineDedupe {
    static func main() {
        var bad = false
        func check(_ ok: Bool, _ why: String) {
            if !ok { print("check-machine-dedupe: FAIL — \(why)"); bad = true }
        }

        // The live shape: alias vs real row, same box.
        let real = machine("arya-macbook-pro", ip: "100.94.221.115", mac: "22:4A:D0:EB:AA:3A")
        let alias = machine("mac", ip: "100.94.221.115", mac: "22:4a:d0:eb:aa:3a", bridge: "http://x:7820")
        let m1 = mergeDuplicateMachineRows([alias, real])
        check(m1.kept.count == 1, "same MAC (case-insensitively) must collapse to one row, got \(m1.kept.count)")
        check(m1.kept.first?.host == "arya-macbook-pro", "the longer real name must win over the alias, got \(m1.kept.first?.host ?? "-")")
        check(m1.kept.first?.bridgeURL == "http://x:7820", "the keeper must absorb the loser's bridge URL")
        check(m1.removed.count == 1 && m1.removed.first?.loser.host == "mac", "the alias must be reported as removed")
        check(m1.removed.first?.keeper.host == "arya-macbook-pro", "the loser must arrive WITH its keeper, or selective tombstoning is impossible")

        // A 127.0.0.1 artifact loses even to a shorter-named real entry.
        let loop = machine("aryas-macbook-pro-local-artifact", ip: "127.0.0.1", mac: "aa:bb")
        let lan = machine("mbp", ip: "192.168.29.9", mac: "aa:bb")
        let m2 = mergeDuplicateMachineRows([loop, lan])
        check(m2.kept.first?.host == "mbp", "a loopback row must lose regardless of name length")

        // Different MACs, missing MACs: nothing merges, order survives.
        let a = machine("a", ip: "1.1.1.1", mac: "aa:aa")
        let b = machine("b", ip: "2.2.2.2", mac: "bb:bb")
        let c = machine("c", ip: "3.3.3.3", mac: nil)
        let d = machine("d", ip: "4.4.4.4", mac: "")
        let m3 = mergeDuplicateMachineRows([a, b, c, d])
        check(m3.kept.map(\.host) == ["a", "b", "c", "d"], "distinct or absent MACs must not merge or reorder")
        check(m3.removed.isEmpty, "nothing may be removed without a MAC match")

        // The keeper's own config is never overwritten by the loser's.
        let keeperCfg = machine("real", ip: "100.1.1.1", mac: "cc:cc", bridge: "http://keep:7820")
        let loserCfg = machine("x", ip: "127.0.0.1", mac: "cc:cc", bridge: "http://lose:7820", vnc: "http://lose:6080")
        let m4 = mergeDuplicateMachineRows([keeperCfg, loserCfg])
        check(m4.kept.first?.bridgeURL == "http://keep:7820", "an existing keeper bridge must survive the fold")
        check(m4.kept.first?.vncURL == "http://lose:6080", "a keeper gap must be filled from the loser")

        if bad { exit(1) }
        print("check-machine-dedupe: OK (one MAC one row; alias tombstoned with its keeper known; config folds without overwrites)")
    }
}

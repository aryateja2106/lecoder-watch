import Foundation

// Pairing writes real tokens into the saved machine list, so the merge has to be right:
// a wrong match silently points a machine at another machine's credentials, and a
// missed match leaves a duplicate row that half works.
@main
struct CheckPairing {
    static func main() {
        checkCodeNormalization()
        checkAllHosts()
        checkMerge()
        print("check-pairing: OK")
    }

    // Must agree with normalizeCode() in meshd/pair.ts, or a code that the daemon
    // accepts gets mangled on the way out of the phone.
    static func checkCodeNormalization() {
        assert(normalizedPairingCode("K7M4-QP2X") == "K7M4QP2X")
        assert(normalizedPairingCode("k7m4-qp2x") == "K7M4QP2X")
        assert(normalizedPairingCode(" k7m4 qp2x ") == "K7M4QP2X")
        assert(normalizedPairingCode("") == "")
        // Punctuation a keyboard might autocorrect in, and nothing else, is dropped.
        assert(normalizedPairingCode("K7M4—QP2X") == "K7M4QP2X")
    }

    static func host(_ name: String, _ ip: String, _ token: String, port: Int = 8899) -> PairedHost {
        PairedHost(host: name, ip: ip, port: port, token: token)
    }

    static func checkAllHosts() {
        // Current daemon: the fleet already carries the self entry, with a real address.
        let full = PairResult(
            ok: true, host: "studio", port: 8899, token: "self-token", platform: "darwin",
            fleet: [host("studio", "100.1.1.1", "self-token"), host("pi", "100.2.2.2", "pi-token")],
        )
        assert(full.allHosts.count == 2, "self must not be duplicated by the fleet entry")
        assert(full.allHosts[0].ip == "100.1.1.1", "self entry takes the address from the fleet")
        assert(full.allHosts.contains { $0.host == "pi" })

        // Older daemon: no fleet at all. The paired machine alone is still an answer,
        // but we have no address for it from the body, so it must not become a row
        // with an empty ip that can never connect.
        let bare = PairResult(ok: true, host: "studio", port: 8899, token: "t", platform: nil, fleet: nil)
        assert(bare.allHosts.isEmpty, "an entry with no address is not usable")

        // A fleet member with no token is a machine the user never finished setting up.
        let partial = PairResult(
            ok: true, host: "studio", port: 8899, token: "self-token", platform: nil,
            fleet: [host("studio", "100.1.1.1", "self-token"), host("halfdone", "100.3.3.3", "")],
        )
        assert(partial.allHosts.count == 1, "a tokenless host is dropped, not added broken")
    }

    static func checkMerge() {
        let existing = [
            Machine(host: "studio", ip: "100.1.1.1", port: 8899, token: "old-token"),
            Machine(host: "renamed-on-the-mac", ip: "100.2.2.2", port: 8899, token: "pi-old"),
        ]

        // Same address = same machine, even if the name moved. Re-pairing is how you
        // recover from a token rotation, so the new token must win.
        let rotated = mergingPairedHosts(existing, [host("studio", "100.1.1.1", "new-token")])
        assert(rotated.count == 2, "matching on address must not append a duplicate")
        assert(rotated[0].token == "new-token", "a fresh token must replace the stale one")

        // The discriminating case: the daemon reports a DIFFERENT name for a machine we
        // already have at that address (the user renamed the Mac). Address is identity,
        // so this must update in place — matching on name here would append a second
        // row pointing at the same daemon.
        let renamed = mergingPairedHosts(existing, [host("pi-new-name", "100.2.2.2", "pi-fresh")])
        assert(renamed.count == 2, "address must win over name, or the machine doubles up")
        assert(renamed[1].token == "pi-fresh")
        assert(renamed[1].host == "renamed-on-the-mac", "the name the user sees is theirs to keep")

        // Same name, new address: the box moved (new tailnet IP), so update in place.
        let moved = mergingPairedHosts(existing, [host("renamed-on-the-mac", "100.9.9.9", "pi-new")])
        assert(moved.count == 2, "matching on name must not append a duplicate")
        assert(moved[1].ip == "100.9.9.9" && moved[1].token == "pi-new")

        // Genuinely new machine appends.
        let added = mergingPairedHosts(existing, [host("laptop", "100.4.4.4", "laptop-token", port: 9000)])
        assert(added.count == 3)
        assert(added[2].port == 9000, "a non-default port must survive the merge")

        // Pairing into an empty list is the first-run path.
        let first = mergingPairedHosts([], [host("studio", "100.1.1.1", "t")])
        assert(first.count == 1 && first[0].isConfigured)

        // Junk never lands: no address or no token means no row.
        let junk = mergingPairedHosts([], [host("nope", "", "t"), host("nope2", "100.5.5.5", "")])
        assert(junk.isEmpty, "a machine with no address or no token is not a machine")

        // Idempotent — pairing twice must not grow the list.
        let once = mergingPairedHosts(existing, [host("studio", "100.1.1.1", "x")])
        assert(mergingPairedHosts(once, [host("studio", "100.1.1.1", "x")]) == once)
    }
}

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
        checkHostMatching()
        checkTombstones()
        checkBridgeAddress()
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

    // Pairing adopts the paired machine's whole hosts.json, so without tombstones a
    // machine the user deleted resurrects on the very next pair — observed live as an
    // un-removable "my-mac" zombie row. The filter has to hold the line both ways:
    // removed stays removed across unrelated pairs, and explicitly pairing the removed
    // machine itself brings it back.
    static func checkTombstones() {
        let fleet = [host("studio", "100.1.1.1", "t1"),
                     host("pi", "100.2.2.2", "t2"),
                     host("my-mac", "100.3.3.3", "t3")]

        // A host removed by name must not come back from an unrelated pairing…
        let byName = filteringRemovedHosts(fleet, removed: ["my-mac"],
                                           pairedHost: "studio", pairedAddress: "100.1.1.1")
        assert(byName.map(\.host) == ["studio", "pi"], "a removed host must not resurrect")

        // …nor when only its address was tombstoned (manual adds may lack a stable name).
        let byIP = filteringRemovedHosts(fleet, removed: ["100.3.3.3"],
                                         pairedHost: "studio", pairedAddress: "100.1.1.1")
        assert(byIP.map(\.host) == ["studio", "pi"], "a removed address must not resurrect")

        // Tombstones are stored lowercased; hosts arrive as the daemon spells them.
        let cased = filteringRemovedHosts([host("My-Mac", "100.3.3.3", "t3")], removed: ["my-mac"],
                                          pairedHost: "studio", pairedAddress: "100.1.1.1")
        assert(cased.isEmpty, "tombstone matching is case-insensitive")

        // Explicitly pairing the removed machine is the un-remove gesture — by name…
        let unremoved = filteringRemovedHosts(fleet, removed: ["my-mac"],
                                              pairedHost: "my-mac", pairedAddress: "100.3.3.3")
        assert(unremoved.count == 3, "pairing a machine overrides its own tombstone")

        // …and by the address the phone actually dialed, even under a fresh name.
        let redialed = filteringRemovedHosts(fleet, removed: ["my-mac", "100.3.3.3"],
                                             pairedHost: "renamed-mac", pairedAddress: "100.3.3.3")
        assert(redialed.contains { $0.ip == "100.3.3.3" }, "dialed address overrides its tombstone")

        // No tombstones: everything flows through untouched.
        assert(filteringRemovedHosts(fleet, removed: [],
                                     pairedHost: "studio", pairedAddress: "100.1.1.1").count == 3)
    }

    // The terminal died on "http://Aryas-MacBook-Pro:7820 — hostname could not be
    // found" while every meshd probe reached the same machine by IP: the bridge and
    // VNC fallbacks dialed addresses.LAST (the bare name) instead of the numeric
    // address. A phone without MagicDNS can never resolve the name.
    static func checkBridgeAddress() {
        let paired = Machine(host: "Aryas-MacBook-Pro", ip: "100.94.221.115", port: 8899, token: "t")
        assert(paired.resolvedBridge == "http://100.94.221.115:7820",
               "bridge dials the numeric address, not the bare hostname")
        assert(paired.resolvedVNC.hasPrefix("http://100.94.221.115:6080"),
               "VNC dials the numeric address, not the bare hostname")

        // A hand-added machine may have no ip yet — the name is then the only address.
        let manual = Machine(host: "studio", ip: "", port: 8899, token: "t")
        assert(manual.resolvedBridge == "http://studio:7820",
               "with no ip the name is still better than nothing")

        // An explicitly stored bridge URL always wins over any fallback.
        var custom = paired
        custom.bridgeURL = "https://mac.tail.ts.net"
        assert(custom.resolvedBridge == "https://mac.tail.ts.net")
    }

    // The name in an APNs payload is whatever `os.hostname()` says on that machine.
    // Observed live: pairing stored "Aryas-MacBook-Pro" while its own events carry
    // "Aryas-MacBook-Pro.local". If this match fails, the reply button does nothing.
    static func checkHostMatching() {
        let fleet = [
            Machine(host: "Aryas-MacBook-Pro", ip: "100.1.1.1", port: 8899, token: "t"),
            Machine(host: "dataflow", ip: "100.2.2.2", port: 8899, token: "t"),
        ]
        assert(machineMatching("Aryas-MacBook-Pro", in: fleet)?.ip == "100.1.1.1", "exact")
        assert(machineMatching("Aryas-MacBook-Pro.local", in: fleet)?.ip == "100.1.1.1", "the .local suffix must not lose the machine")
        assert(machineMatching("aryas-macbook-pro", in: fleet)?.ip == "100.1.1.1", "case")
        // hosts.json key "dataflow" vs the daemon's own "dataflowagents".
        assert(machineMatching("dataflowagents", in: fleet)?.ip == "100.2.2.2", "prefix both ways")
        assert(machineMatching("dataflow.tailnet.ts.net", in: fleet)?.ip == "100.2.2.2")

        // Never guess. An unknown machine is a no-op, not "the first one".
        assert(machineMatching("someone-elses-box", in: fleet) == nil, "an unknown host must not match anything")
        assert(machineMatching("", in: fleet) == nil, "an empty name must not match the first machine")
        assert(machineMatching("studio", in: []) == nil)
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

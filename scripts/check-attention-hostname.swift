// check-attention-hostname.swift — an event from a machine the phone adopted under another
// name ("pi" from a fleet file, "arya-pi" from its own daemon) still finds its machine and
// its session, so "Needs you" appears and Approve has somewhere to go.
//
// Measured 2026-09-22: Claude Code on the Pi at a permission prompt, the event on the phone,
// the /agents row carrying the agent's sessionId — and no row, because `hostNamesMatch("pi",
// "arya-pi")` is false and the machine lookup gave up before the id-first agent match ran.
// The daemon's own hostname travels in /stats; matching on it is the bridge.
//
// Compiled by check-all.sh together with the Shared/ models — pure, no network.
import Foundation

@main struct CheckAttentionHostname {
    static func main() throws {
        let stats = try JSONDecoder().decode(Stats.self, from: Data("""
        {"host":"arya-pi","platform":"linux","cpuPct":1,"load":[0,0,0],
         "mem":{"usedMB":1,"totalMB":2,"pct":50},"disk":{"path":"/","usedGB":1,"totalGB":2,"pct":50},
         "topProcs":[],"agentsCount":1}
        """.utf8))
        var agent = Agent(name: "pi-claude", windows: 1, attached: false, agentType: "Claude")
        agent.sessionId = "conv-42"
        var machine = MachineSnapshot(host: "pi", reachable: true, stats: stats, agents: [agent])
        machine.capabilities = ["events"]
        var event = AgentEvent(id: "e1", host: "arya-pi", source: "claude", session: "pi-claude",
                               level: "warning", title: "Claude needs attention",
                               body: "Claude needs your permission", createdISO: "2026-09-22T05:12:56Z")
        event.sessionId = "conv-42"
        event.replyable = true
        var snap = MeshSnapshot(updatedISO: "2026-09-22T05:13:00Z", machines: [machine])
        snap.events = [event]

        guard let found = snapshotMachineMatching("arya-pi", in: [machine]) else {
            fail("snapshotMachineMatching could not find 'pi' for the daemon name 'arya-pi'")
        }
        guard found.host == "pi" else { fail("matched the wrong machine: \(found.host)") }
        let picks = sessionsNeedingAttention(from: snap)
        guard picks.count == 1, picks[0].host == "pi", picks[0].session == "pi-claude" else {
            fail("sessionsNeedingAttention returned \(picks.map { "\($0.host)/\($0.session)" }), expected pi/pi-claude")
        }
        // The name rule still wins over stats when it can: a machine stored under the daemon's
        // own name must not be shadowed by another whose stats happen to say the same thing.
        var exact = MachineSnapshot(host: "arya-pi", reachable: true, stats: nil, agents: [])
        exact.capabilities = []
        guard snapshotMachineMatching("arya-pi", in: [machine, exact])?.host == "arya-pi" else {
            fail("an exact host match must outrank a stats match")
        }
        print("check-attention-hostname: OK")
    }

    static func fail(_ message: String) -> Never {
        print("check-attention-hostname: FAIL — \(message)")
        exit(1)
    }
}

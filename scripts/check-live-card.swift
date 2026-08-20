import Foundation

// The live card is the one thing on the Lock Screen and the watch Smart Stack, so
// picking the wrong session is worse than picking none: it buries the agent that is
// actually blocked under one that is merely busy.
@main
struct CheckLiveCard {
    static func main() {
        checkAttentionList()
        checkNothingToShow()
        checkAttentionWins()
        checkNewestBlockedWins()
        checkWatchedSession()
        checkAttentionBeatsWatched()
        print("check-live-card: OK")
    }

    // MARK: Fixtures

    static func agent(_ name: String, attached: Bool = true, type: String? = "claude") -> Agent {
        Agent(name: name, windows: 1, attached: attached, agentType: type)
    }

    static func machine(_ host: String, _ agents: [Agent]) -> MachineSnapshot {
        MachineSnapshot(host: host, reachable: true, stats: nil, agents: agents)
    }

    static func event(_ host: String, _ session: String, level: String, title: String = "t", body: String? = nil,
                      at iso: String = "2026-08-20T10:00:00Z") -> AgentEvent {
        AgentEvent(id: "\(host)-\(session)-\(iso)", host: host, source: "claude", session: session,
                   level: level, title: title, body: body, createdISO: iso)
    }

    static func snapshot(_ machines: [MachineSnapshot],
                         events: [AgentEvent] = [],
                         watchedHost: String? = nil,
                         watchedAgent: String? = nil,
                         watchedOutput: [String]? = nil) -> MeshSnapshot {
        var snap = MeshSnapshot(updatedISO: "2026-08-20T10:00:00Z", machines: machines)
        snap.events = events
        snap.watchedHost = watchedHost
        snap.watchedAgent = watchedAgent
        snap.watchedOutput = watchedOutput
        return snap
    }

    // MARK: Cases

    // The list the whole product is for: every agent across every machine that is
    // stopped waiting on a human.
    static func checkAttentionList() {
        let snap = snapshot(
            [machine("studio", [agent("api"), agent("web")]), machine("pi", [agent("build")])],
            events: [
                event("studio", "api", level: "warning", title: "asks", at: "2026-08-20T09:00:00Z"),
                event("pi", "build", level: "error", title: "broke", at: "2026-08-20T09:30:00Z"),
                event("studio", "web", level: "info", title: "done", at: "2026-08-20T09:45:00Z"),
            ],
        )
        let list = sessionsNeedingAttention(from: snap)
        assert(list.count == 2, "two blocked, one finished — got \(list.count)")
        assert(list[0].session == "build", "newest first")
        assert(list[1].session == "api")
        assert(!list.contains { $0.session == "web" }, "a finished session is not waiting on anyone")

        // A question that has since been answered must drop off. Without this the list
        // only ever grows and every row becomes untrustworthy.
        let answered = snapshot(
            [machine("studio", [agent("api")])],
            events: [
                event("studio", "api", level: "warning", title: "asks", at: "2026-08-20T09:00:00Z"),
                event("studio", "api", level: "info", title: "carried on", at: "2026-08-20T09:10:00Z"),
            ],
        )
        assert(sessionsNeedingAttention(from: answered).isEmpty, "a superseded question must not linger")

        // The reverse order too: a session that finished and then asked again is waiting.
        let askedAgain = snapshot(
            [machine("studio", [agent("api")])],
            events: [
                event("studio", "api", level: "info", title: "done", at: "2026-08-20T09:00:00Z"),
                event("studio", "api", level: "warning", title: "asks again", at: "2026-08-20T09:10:00Z"),
            ],
        )
        assert(sessionsNeedingAttention(from: askedAgain).count == 1)

        // One row per session, not one per event, however many times it asked.
        let repeated = snapshot(
            [machine("studio", [agent("api")])],
            events: (0..<5).map { event("studio", "api", level: "warning", title: "ask \($0)",
                                        at: "2026-08-20T09:0\($0):00Z") },
        )
        let deduped = sessionsNeedingAttention(from: repeated)
        assert(deduped.count == 1, "one row per session, got \(deduped.count)")
        assert(deduped[0].lastLine == "ask 4", "the newest ask is the one to show")

        // An event with no host or no session cannot be routed, so it cannot be a row.
        var headless = event("studio", "api", level: "warning")
        headless.host = nil
        assert(sessionsNeedingAttention(from: snapshot([machine("studio", [agent("api")])], events: [headless])).isEmpty)

        assert(sessionsNeedingAttention(from: snapshot([])).isEmpty)
    }

    // A fleet of busy sessions is not a reason to occupy the Lock Screen. A permanent
    // "Working" card is wallpaper, and every update spends a budget ActivityKit meters.
    static func checkNothingToShow() {
        let busy = snapshot([machine("studio", [agent("api"), agent("web")])])
        assert(liveSessionPick(from: busy) == nil, "merely-running sessions must not raise a card")

        assert(liveSessionPick(from: snapshot([])) == nil, "an empty mesh shows nothing")

        // An "info" event is news, not a prompt.
        let finished = snapshot([machine("studio", [agent("api")])],
                                events: [event("studio", "api", level: "info", title: "Claude stopped")])
        assert(liveSessionPick(from: finished) == nil, "a finished turn is not an interruption")

        // An event for a session that is no longer running must not raise a card for a
        // session you cannot open.
        let ghost = snapshot([machine("studio", [agent("web")])],
                             events: [event("studio", "gone", level: "warning")])
        assert(liveSessionPick(from: ghost) == nil, "no card for a session that is not there")
    }

    static func checkAttentionWins() {
        let snap = snapshot(
            [machine("studio", [agent("api"), agent("web")])],
            events: [event("studio", "web", level: "warning", title: "Claude needs attention", body: "Allow edit?")],
        )
        let pick = liveSessionPick(from: snap)
        assert(pick?.session == "web", "the blocked session gets the card, not the first one listed")
        assert(pick?.state == .waiting)
        assert(pick?.lastLine == "Allow edit?", "the body is the useful line; the title is already the state")
        assert(pick?.agentType == "claude")

        // An error counts too — a broken agent is also stopped.
        let broke = snapshot([machine("studio", [agent("api")])],
                             events: [event("studio", "api", level: "error", title: "Build failed")])
        assert(liveSessionPick(from: broke)?.state == .error)
        assert(liveSessionPick(from: broke)?.lastLine == "Build failed", "falls back to the title when there is no body")
    }

    // `events` arrives oldest first. The newest thing to block is the one you care
    // about, so a naive first-match would show a stale prompt from an hour ago.
    static func checkNewestBlockedWins() {
        let snap = snapshot(
            [machine("studio", [agent("api")]), machine("pi", [agent("build")])],
            events: [
                event("studio", "api", level: "warning", title: "old", at: "2026-08-20T09:00:00Z"),
                event("pi", "build", level: "warning", title: "new", at: "2026-08-20T10:00:00Z"),
            ],
        )
        let pick = liveSessionPick(from: snap)
        assert(pick?.session == "build" && pick?.host == "pi", "the most recent block wins, got \(pick?.session ?? "nil")")
    }

    // Opening a session is the user saying they care; classify its real output.
    static func checkWatchedSession() {
        let snap = snapshot([machine("studio", [agent("api")])],
                            watchedHost: "studio", watchedAgent: "api",
                            watchedOutput: ["running tests", "Do you want to continue?"])
        let pick = liveSessionPick(from: snap)
        assert(pick?.session == "api")
        assert(pick?.state == .waiting, "live output must be classified, not assumed")
        assert(pick?.lastLine == "Do you want to continue?")

        // Watched but with nothing back yet: still a card, because the user is looking.
        let quiet = snapshot([machine("studio", [agent("api")])],
                             watchedHost: "studio", watchedAgent: "api", watchedOutput: [])
        assert(liveSessionPick(from: quiet)?.state == .running)

        // Watching a session on a machine that dropped out of the snapshot: no card,
        // rather than a card naming a machine we cannot reach.
        let dropped = snapshot([], watchedHost: "studio", watchedAgent: "api", watchedOutput: ["x"])
        assert(liveSessionPick(from: dropped) == nil)
    }

    // Both reasons at once: the blocked session outranks the one being watched, because
    // the user can already see the one they have open.
    static func checkAttentionBeatsWatched() {
        let snap = snapshot(
            [machine("studio", [agent("api"), agent("web")])],
            events: [event("studio", "web", level: "warning", title: "needs you")],
            watchedHost: "studio", watchedAgent: "api", watchedOutput: ["building…"],
        )
        assert(liveSessionPick(from: snap)?.session == "web", "blocked outranks watched")
    }
}

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
        checkBlockedSince()
        checkRiskReachesTheRow()
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

        // Observed live, and it made the whole feature silently do nothing: macOS
        // reports its hostname as "Aryas-MacBook-Pro.local" in the event, while the app
        // stored "Aryas-MacBook-Pro" from pairing. An == match found no machine, so a
        // real blocked agent produced no row anywhere.
        let dotted = MeshSnapshot(updatedISO: "", machines: [machine("Aryas-MacBook-Pro", [agent("deploy-api")])])
        var withEvent = dotted
        withEvent.events = [event("Aryas-MacBook-Pro.local", "deploy-api", level: "warning",
                                  title: "Claude needs attention", body: "run git push --force?")]
        let matched = sessionsNeedingAttention(from: withEvent)
        assert(matched.count == 1, "a .local hostname in the event must still find the machine")
        assert(matched[0].host == "Aryas-MacBook-Pro",
               "the row must carry the name the app knows, so the reply reaches the same machine")

        // The daemon's own name vs a hosts.json key, the other direction.
        var keyed = MeshSnapshot(updatedISO: "", machines: [machine("dataflow", [agent("build")])])
        keyed.events = [event("dataflowagents", "build", level: "error", title: "failed")]
        assert(sessionsNeedingAttention(from: keyed).first?.host == "dataflow")

        // Tolerance must not become guessing: an unrelated machine still matches nothing.
        var wrong = MeshSnapshot(updatedISO: "", machines: [machine("studio", [agent("api")])])
        wrong.events = [event("someone-elses-laptop", "api", level: "warning", title: "x")]
        assert(sessionsNeedingAttention(from: wrong).isEmpty,
               "a different machine with a same-named session must never match")

        // Two vocabularies reach /events. Real events on this mesh have used
        // "needs-input" and "finished" as levels, not only mesh-hook's warning/info.
        for level in ["warning", "needs-input", "needs_input", "NEEDS-INPUT", "error", "failed"] {
            let one = snapshot([machine("studio", [agent("api")])],
                               events: [event("studio", "api", level: level)])
            assert(sessionsNeedingAttention(from: one).count == 1, "level \(level) must count as blocked")
        }
        for level in ["info", "finished", "", "debug"] {
            let one = snapshot([machine("studio", [agent("api")])],
                               events: [event("studio", "api", level: level)])
            assert(sessionsNeedingAttention(from: one).isEmpty, "level \(level) must not raise a row")
        }
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

    // The row counts the wait up live from this stamp. If it does not survive the trip
    // from the event, the timer silently renders from a nil date and the number that
    // makes this product feel urgent never appears.
    static func checkBlockedSince() {
        let snap = snapshot([machine("studio", [agent("api")])],
                            events: [event("studio", "api", level: "warning",
                                           at: "2026-08-20T09:30:00Z")])
        let pick = sessionsNeedingAttention(from: snap).first
        assert(pick?.blockedSince != nil, "the block time has to reach the row")
        let expected = ISO8601DateFormatter().date(from: "2026-08-20T09:30:00Z")
        assert(pick?.blockedSince == expected, "and be the event's own time, not now")

        // The shape meshd actually emits. Every fixture above is hand-written as
        // `...:00Z`, and `ISO8601DateFormatter()` in its default configuration parses
        // that happily while returning nil for a fraction — so this check was green
        // while the timer rendered as nothing at all against the live daemon. The
        // fixture, not the code, was the thing that was wrong.
        let real = snapshot([machine("studio", [agent("api")])],
                            events: [event("studio", "api", level: "warning",
                                           at: "2026-08-20T14:02:35.185Z")])
        let fromDaemon = sessionsNeedingAttention(from: real).first
        assert(fromDaemon?.blockedSince != nil,
               "a fractional-seconds stamp is what meshd sends; it must parse")

        // And the helper itself, both ways plus the junk case.
        assert(parseISO("2026-08-20T14:02:35.185Z") != nil)
        assert(parseISO("2026-08-20T14:02:35Z") != nil)
        assert(parseISO("not a date") == nil)
        assert(parseISO("") == nil)
        assert(parseISO(nil) == nil)

        // A watched-but-not-blocked session is not waiting on anyone, so it must not
        // grow a stopwatch implying it is.
        let watched = snapshot([machine("studio", [agent("api")])],
                               watchedHost: "studio", watchedAgent: "api",
                               watchedOutput: ["building…"])
        assert(liveSessionPick(from: watched)?.blockedSince == nil)
    }

    // The verb on the button comes from this. A miss here arms a red-tinted "yes" as a
    // calm "Continue" — which is exactly the button nobody should press by reflex.
    static func checkRiskReachesTheRow() {
        // Classify the body, not the title: mesh-hook's title is boilerplate.
        let risky = snapshot(
            [machine("studio", [agent("deploy")])],
            events: [event("studio", "deploy", level: "warning",
                           title: "Claude needs attention", body: "run git push --force?")],
        )
        let pick = sessionsNeedingAttention(from: risky).first
        assert(pick?.risk.isDestructive == true, "a force push must reach the row as destructive")
        assert(pick?.risk.verb == "Force push", "and name itself, got \(pick?.risk.verb ?? "nil")")
        assert(pick?.risk.consequence != nil)

        // An ordinary question keeps the plain label.
        let calm = snapshot(
            [machine("studio", [agent("api")])],
            events: [event("studio", "api", level: "warning",
                           title: "Claude needs attention", body: "Allow edit to src/auth.rs?")],
        )
        assert(sessionsNeedingAttention(from: calm).first?.risk.verb == "Continue")

        // The session name is never evidence: a session called deploy-api asking
        // something harmless stays calm.
        let named = snapshot(
            [machine("studio", [agent("deploy-api")])],
            events: [event("studio", "deploy-api", level: "warning", title: "Ready to continue?")],
        )
        assert(sessionsNeedingAttention(from: named).first?.risk.isDestructive == false,
               "the session name must not turn the button red")

        // Falls back to the title when the hook sent no body.
        let titleOnly = snapshot(
            [machine("studio", [agent("api")])],
            events: [event("studio", "api", level: "warning", title: "rm -rf build — ok?")],
        )
        assert(sessionsNeedingAttention(from: titleOnly).first?.risk.verb == "Delete files")
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

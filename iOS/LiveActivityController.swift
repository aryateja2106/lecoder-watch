import Foundation
import ActivityKit
import UIKit

/// Drives the pinned session's Live Activity from MeshStore's poll loop. Local
/// updates only (pushType: nil) — no APNs, no server. Starts only in the
/// foreground (an ActivityKit rule), dedupes updates, ends explicitly.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private var activity: Activity<SessionActivityAttributes>?
    private var pinned: String?

    /// Pin/unpin the primary session. Unpinning ends the activity immediately.
    func setPinned(_ session: String?) {
        pinned = session
        if session == nil { Task { await end() } }
    }

    /// Called each poll with the freshest snapshot.
    func sync(snapshot: MeshSnapshot) {
        guard let pinned else { return }
        guard let located = locate(pinned, in: snapshot) else {
            Task { await end() }   // pinned session disappeared
            return
        }
        let content = contentState(for: located.agent, host: located.host, snapshot: snapshot)
        if let activity {
            guard activity.content.state != content else { return }   // dedupe — protect the update budget
            Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
        } else {
            start(host: located.host, session: located.agent.name, content: content)
        }
    }

    private func start(host: String, session: String, content: SessionActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }
        let attributes = SessionActivityAttributes(host: host, session: session)
        activity = try? Activity.request(attributes: attributes,
                                         content: ActivityContent(state: content, staleDate: nil),
                                         pushType: nil)
    }

    private func end() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }

    // MARK: Derive content from the snapshot

    private func locate(_ session: String, in snap: MeshSnapshot) -> (host: String, agent: Agent)? {
        for m in snap.machines where m.agents.contains(where: { $0.name == session }) {
            if let a = m.agents.first(where: { $0.name == session }) { return (m.host, a) }
        }
        return nil
    }

    private func contentState(for agent: Agent, host: String, snapshot: MeshSnapshot) -> SessionActivityAttributes.ContentState {
        // Real output classification when this session is the one being watched, else
        // fall back to its latest event level (same logic the cards use).
        let output = (snapshot.watchedAgent == agent.name) ? snapshot.watchedOutput : nil
        let state: SessionState
        if let output, !output.isEmpty {
            state = sessionState(lines: output, attached: agent.attached)
        } else {
            let latest = (snapshot.events ?? []).last { $0.host == host && $0.session == agent.name }
            state = cardState(forLevel: latest?.level, attached: agent.attached)
        }
        let last = output?.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? (snapshot.events ?? []).last { $0.session == agent.name }?.title
            ?? ""
        return SessionActivityAttributes.ContentState(
            stateRaw: state.rawValue,
            agentType: agent.agentType ?? "shell",
            cpuPct: agent.cpuPct,
            memLabel: agent.memLabel,
            lastLine: String(last.prefix(80))
        )
    }
}

import Foundation
import ActivityKit
import UIKit

/// Runs the live card off MeshStore's poll loop. Local updates only (`pushType: nil`):
/// no server, no APNs, nothing leaves the phone.
///
/// Which session gets the card is decided by `liveSessionPick`, not by the user
/// pinning one — the session that is blocked is the session you want on your wrist,
/// and asking someone to pick it in advance is asking them to predict which agent will
/// get stuck.
///
/// **Known limit:** ActivityKit only lets an app *start* an activity in the foreground.
/// From a pocket, the actionable notification is what reaches you; the card appears
/// next time the app is open. Lifting that needs push-to-start (`pushToStartToken` +
/// a `liveactivity` push from meshd), which is a separate slice.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<SessionActivityAttributes>?
    private var showing: (host: String, session: String)?

    /// Called with each fresh snapshot.
    func sync(snapshot: MeshSnapshot) {
        guard let pick = liveSessionPick(from: snapshot) else {
            Task { await end() }
            return
        }
        let content = SessionActivityAttributes.ContentState(
            stateRaw: pick.state.rawValue,
            agentType: pick.agentType,
            cpuPct: pick.cpuPct,
            memLabel: pick.memLabel,
            lastLine: pick.lastLine,
            blockedSince: pick.blockedSince,
            riskVerb: pick.risk.isDestructive ? pick.risk.verb : nil,
            riskWhy: pick.risk.consequence,
            // Whole-fleet, not just this session's machine: the card is the one place
            // you look without unlocking, so it may as well say whether the rest of the
            // mesh is still answering.
            machinesOnline: snapshot.machines.filter(\.reachable).count,
            machinesTotal: snapshot.machines.count,
        )

        // A different session took over: end the old card rather than relabelling it,
        // because the attributes carry the identity and those cannot be updated.
        if let showing, showing.host != pick.host || showing.session != pick.session {
            Task {
                await end()
                start(host: pick.host, session: pick.session, content: content)
            }
            return
        }

        if let activity {
            // Dedupe: ActivityKit budgets updates, and most polls change nothing.
            guard activity.content.state != content else { return }
            Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
        } else {
            start(host: pick.host, session: pick.session, content: content)
        }
    }

    private func start(host: String, session: String, content: SessionActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }
        let attributes = SessionActivityAttributes(host: host, session: session)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: content, staleDate: nil),
            pushType: nil,
        )
        showing = activity == nil ? nil : (host, session)
    }

    private func end() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        showing = nil
    }
}

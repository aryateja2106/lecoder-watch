import Foundation
import ActivityKit
import UIKit

/// Runs the live card for whichever session currently deserves one.
///
/// Which session that is gets decided by `liveSessionPick`, not by the user pinning
/// one — the session that is blocked is the session you want on your wrist, and asking
/// someone to pick it in advance is asking them to predict which agent will get stuck.
///
/// Two things drive the card. The poll loop calls `sync(snapshot:)` while the app is
/// open, which is the only way an activity can be *started* from the app itself —
/// ActivityKit refuses `request` from the background. And meshd (0.5.0+, "laPush")
/// starts and updates it over APNs when the app is not open at all, using the two
/// tokens uploaded from here: one push-to-start token per device, and one update token
/// per running activity. The poll loop stays as reconciliation for everything the push
/// lane cannot see — a card whose session is gone, a fleet count that moved — and
/// because a machine on an older daemon has no push lane at all.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    /// Whether iOS will run Live Activities for this app at all, kept current by
    /// `activityEnablementUpdates`. Consulted before every `request`, so someone who
    /// switches the permission on mid-session gets a card on the next poll instead of
    /// having to relaunch. Settings watches the same system stream to say so out loud.
    private(set) var activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

    /// Hands a push token to every paired machine. Set by the app at launch — this
    /// type deliberately knows nothing about the machine list.
    var uploadToken: ((_ kind: MeshClient.LATokenKind, _ token: String, _ session: String?) async -> Void)?

    private var activity: Activity<SessionActivityAttributes>?
    private var showing: (host: String, session: String)?

    /// The tokens we have been given, kept so a machine paired *after* ActivityKit
    /// handed them over can still be told. Otherwise a freshly paired Mac has no way to
    /// start a card until the token happens to rotate, or the app is relaunched.
    /// In memory only: a token that outlived the app's process is not one this device
    /// still owns, and re-offering a dead token would just get it rejected.
    private var lastStartToken: String?
    private var lastUpdateToken: (session: String, token: String)?

    /// One task per stream, each cancelled when what it was watching goes away.
    private var enablementTask: Task<Void, Never>?
    private var pushToStartTask: Task<Void, Never>?
    private var activityStateTask: Task<Void, Never>?
    private var updateTokenTask: Task<Void, Never>?
    private var pushStartedTask: Task<Void, Never>?

    /// How long a card may go without an update before iOS greys it out.
    ///
    /// Not `nil`, which is what it used to be: a card with no stale date claims to be
    /// current forever, so a phone that loses the tailnet keeps showing "waiting on
    /// you" from an hour ago with total confidence. Fifteen minutes is longer than any
    /// healthy gap (the poll is 8s, a push is immediate) and short enough that a card
    /// which outlived its truth looks like one.
    private static let staleAfter: TimeInterval = 15 * 60

    private init() {}

    // MARK: - Lifecycle

    /// Called once at launch, before the first poll.
    ///
    /// Adopting first matters: an app that was killed with a card on screen comes back
    /// with that card still live and no reference to it. Starting a second activity
    /// then leaves two cards for one session, and the orphan can never be ended because
    /// nothing holds it — it sits on the Lock Screen until iOS ages it out eight hours
    /// later. `Activity.activities` is the only way back to it.
    func begin() {
        reconcile(keeping: nil)
        watchEnablement()
        watchPushToStartTokens()
        watchPushStartedActivities()
    }

    /// Exactly one card, always — and not only at launch. meshd starts cards over APNs
    /// while the app is suspended, and those arrive with no reference held here; this
    /// used to run once per cold process, so they were swept only after a crash or a
    /// reboot. Now every snapshot keeps the card for `pick` (adopting it, which uploads
    /// the update token that is the daemon's only way to end it) and ends the rest.
    /// With no pick, the first existing card is the one kept.
    private func reconcile(keeping pick: (host: String, session: String)?) {
        let existing = Activity<SessionActivityAttributes>.activities
        let keep: Activity<SessionActivityAttributes>?
        if let pick {
            keep = existing.first {
                $0.attributes.session == pick.session && hostNamesMatch($0.attributes.host, pick.host)
            }
        } else {
            keep = existing.first
        }
        for extra in existing where extra.id != keep?.id {
            if activity?.id == extra.id { forget(extra) }
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
        if let keep, activity?.id != keep.id {
            attach(keep, host: keep.attributes.host, session: keep.attributes.session)
        }
    }

    /// Cards meshd starts while the app is open land on this stream with nothing here
    /// holding them. Reconcile against the card already shown: adopt if there is none,
    /// end the newcomer if there is.
    private func watchPushStartedActivities() {
        pushStartedTask?.cancel()
        pushStartedTask = Task { [weak self] in
            for await _ in Activity<SessionActivityAttributes>.activityUpdates {
                guard !Task.isCancelled, let self else { return }
                self.reconcile(keeping: self.showing)
            }
        }
    }

    /// Take ownership of an activity: hold it, follow its state, and register its
    /// update token with the fleet.
    private func attach(_ adopted: Activity<SessionActivityAttributes>, host: String, session: String) {
        activityStateTask?.cancel()
        updateTokenTask?.cancel()
        activity = adopted
        showing = (host, session)

        // The card can end without us: the user swipes it away, or iOS ages it out.
        // Holding a stale reference after that is what makes `update` calls vanish into
        // nothing and the next `sync` decline to start a replacement.
        activityStateTask = Task { [weak self] in
            for await state in adopted.activityStateUpdates {
                guard !Task.isCancelled else { return }
                switch state {
                case .ended, .dismissed:
                    self?.forget(adopted)
                    return
                default:
                    // .active and .stale both mean the card is still ours.
                    continue
                }
            }
        }

        // Update tokens rotate in place; meshd replaces the one it holds for this
        // session. Without this the daemon can start a card but never change it.
        updateTokenTask = Task { [weak self] in
            for await tokenData in adopted.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                self?.lastUpdateToken = (session, token)
                await self?.uploadToken?(.update, token, session)
            }
        }
    }

    /// Drop a reference to an activity that has ended, but only if it is still the one
    /// we are holding — a late callback from a card we already replaced must not clear
    /// the live one out from under its successor.
    private func forget(_ ended: Activity<SessionActivityAttributes>) {
        guard activity?.id == ended.id else { return }
        activityStateTask?.cancel()
        updateTokenTask?.cancel()
        activityStateTask = nil
        updateTokenTask = nil
        activity = nil
        showing = nil
    }

    private func watchEnablement() {
        enablementTask?.cancel()
        enablementTask = Task { [weak self] in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                guard !Task.isCancelled else { return }
                self?.activitiesEnabled = enabled
            }
        }
    }

    /// The push-to-start token is per device, not per activity, and it is what lets
    /// meshd raise a card for an agent that got stuck while the app was closed — the
    /// case the whole feature exists for. It rotates; each new value replaces the last
    /// on every machine.
    private func watchPushToStartTokens() {
        pushToStartTask?.cancel()
        pushToStartTask = Task { [weak self] in
            for await tokenData in Activity<SessionActivityAttributes>.pushToStartTokenUpdates {
                guard !Task.isCancelled else { return }
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                self?.lastStartToken = token
                await self?.uploadToken?(.start, token, nil)
            }
        }
    }

    /// Offer the tokens we already hold to the fleet again. Called after pairing: the
    /// machine that just joined was not in the list when ActivityKit handed these over,
    /// so without this it cannot start or update a card until the next launch.
    func resendTokens() async {
        if let lastStartToken {
            await uploadToken?(.start, lastStartToken, nil)
        }
        if let lastUpdateToken {
            await uploadToken?(.update, lastUpdateToken.token, lastUpdateToken.session)
        }
    }

    // MARK: - Reconciliation

    /// Called with each fresh snapshot.
    func sync(snapshot: MeshSnapshot) {
        guard let pick = liveSessionPick(from: snapshot) else {
            // Nothing deserves a card: end every card, not just the held one. A
            // push-started card for a session that has since gone quiet is exactly the
            // stale card nothing else will ever end.
            for orphan in Activity<SessionActivityAttributes>.activities where orphan.id != activity?.id {
                Task { await orphan.end(nil, dismissalPolicy: .immediate) }
            }
            Task { await end() }
            return
        }
        reconcile(keeping: (pick.host, pick.session))
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
            // Dedupe: ActivityKit budgets updates, and most polls change nothing. The
            // stale date still has to move, so a card whose content is unchanged but
            // whose data is fresh does not grey out — that is a separate update, and
            // the cheapest way to avoid it is to let an unchanged poll leave the old
            // stale date alone and rely on the next real change. A card only greys out
            // after fifteen minutes of *nothing* happening, which is the honest signal.
            guard activity.content.state != content else { return }
            Task {
                await activity.update(
                    ActivityContent(state: content, staleDate: Date(timeIntervalSinceNow: Self.staleAfter)))
            }
        } else {
            start(host: pick.host, session: pick.session, content: content)
        }
    }

    private func start(host: String, session: String, content: SessionActivityAttributes.ContentState) {
        guard activitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }
        let attributes = SessionActivityAttributes(host: host, session: session)
        // `.token` rather than nil: the activity gets an APNs update token, which is
        // the only way meshd can move the card once the app is closed. Asking for one
        // costs nothing when no daemon can use it — the token is simply never uploaded
        // anywhere that wants it, because `uploadLAToken` refuses hosts without
        // "laPush".
        let started = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: content,
                                     staleDate: Date(timeIntervalSinceNow: Self.staleAfter)),
            pushType: .token,
        )
        guard let started else {
            activity = nil
            showing = nil
            return
        }
        attach(started, host: host, session: session)
    }

    private func end() async {
        guard let activity else { return }
        activityStateTask?.cancel()
        updateTokenTask?.cancel()
        activityStateTask = nil
        updateTokenTask = nil
        self.activity = nil
        showing = nil
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}

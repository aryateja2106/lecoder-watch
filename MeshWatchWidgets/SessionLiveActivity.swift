import ActivityKit
import WidgetKit
import SwiftUI

/// A live card for the session that currently needs you: Lock Screen, Dynamic Island,
/// and the watch Smart Stack on watchOS 11 and later — the same activity, no extra
/// target. Tapping it deep-links to that session.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(deepLink(context.attributes))
        } dynamicIsland: { context in
            let status = context.state.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AgentBadge(type: context.state.agentType)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let resource = context.state.resourceText {
                        Text(resource).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.session).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        SessionStatusLabel(state: status)
                        Spacer()
                        Text(context.attributes.host)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: status.symbol).foregroundStyle(status.tint)
            } compactTrailing: {
                Circle().fill(status.tint).frame(width: 8, height: 8)
            } minimal: {
                Image(systemName: status.symbol).foregroundStyle(status.tint)
            }
            .widgetURL(deepLink(context.attributes))
            .keylineTint(status.tint)
        }
    }

    private func deepLink(_ attributes: SessionActivityAttributes) -> URL? {
        var components = URLComponents()
        components.scheme = "meshwatch"
        components.host = "session"
        // Percent-encoding via URLComponents, because session names are user-chosen and
        // a space or a slash in one would otherwise produce a URL that silently fails.
        components.path = "/\(attributes.host)/\(attributes.session)"
        return components.url
    }
}

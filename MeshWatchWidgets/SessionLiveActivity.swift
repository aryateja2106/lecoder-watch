import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity: the pinned session on the Lock Screen + Dynamic Island.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock Screen / banner.
            SessionLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let st = context.state.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AgentBadge(type: context.state.agentType)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let r = context.state.resourceText {
                        Text(r).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.session).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Circle().fill(st.tint).frame(width: 7, height: 7)
                        Text(st.cardLabel).font(.subheadline.weight(.medium)).foregroundStyle(st.tint)
                        Spacer()
                        Text(context.attributes.host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: st.symbol).foregroundStyle(st.tint)
            } compactTrailing: {
                Circle().fill(st.tint).frame(width: 8, height: 8)
            } minimal: {
                Image(systemName: st.symbol).foregroundStyle(st.tint)
            }
            .widgetURL(URL(string: "meshwatch://session/\(context.attributes.host)/\(context.attributes.session)"))
            .keylineTint(st.tint)
        }
    }
}

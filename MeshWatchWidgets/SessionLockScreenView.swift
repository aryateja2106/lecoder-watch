import SwiftUI

/// Lock Screen / banner presentation for the pinned session's Live Activity.
/// Reuses the shared AgentBadge + SessionState vocabulary so it matches the in-app cards.
struct SessionLockScreenView: View {
    let attributes: SessionActivityAttributes
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        let st = state.state
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    AgentBadge(type: state.agentType)
                    Text(attributes.session).font(.headline).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Circle().fill(st.tint).frame(width: 7, height: 7)
                    Text(st.cardLabel).font(.subheadline.weight(.medium)).foregroundStyle(st.tint)
                    if !state.lastLine.isEmpty {
                        Text("· \(state.lastLine)")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(attributes.host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if let r = state.resourceText {
                    Text(r).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

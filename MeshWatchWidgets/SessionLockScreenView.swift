import SwiftUI

/// The Lock Screen and banner presentation, and the same view the watch Smart Stack
/// renders. Reuses the shared badge and status vocabulary so it reads identically to
/// the rows inside the app.
struct SessionLockScreenView: View {
    let attributes: SessionActivityAttributes
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        let status = state.state
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    AgentBadge(type: state.agentType)
                    Text(attributes.session).font(.headline).lineLimit(1)
                }
                HStack(spacing: 6) {
                    SessionStatusLabel(state: status)
                    if !state.lastLine.isEmpty {
                        Text("· \(state.lastLine)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(attributes.host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if let resource = state.resourceText {
                    Text(resource).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

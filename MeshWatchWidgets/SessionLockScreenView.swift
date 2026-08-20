import SwiftUI

/// The Lock Screen and banner presentation, and the same view the watch Smart Stack
/// renders. Reuses the shared badge and status vocabulary so it reads identically to
/// the rows inside the app.
///
/// Two renderings, not one. A card that looks the same whether the agent is working or
/// stopped is a card you learn to ignore — and then you ignore the one that mattered.
/// Blocked gets the question as its headline and an amber wash you can read across a
/// room; running stays deliberately quiet.
struct SessionLockScreenView: View {
    let attributes: SessionActivityAttributes
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        if state.isBlocked {
            blocked
        } else {
            running
        }
    }

    // MARK: Blocked

    private var accent: Color { state.isRisky ? .red : .orange }

    private var blocked: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: state.isRisky ? "exclamationmark.triangle.fill" : "exclamationmark.bubble.fill")
                    .font(.caption2)
                    .foregroundStyle(accent)
                Text(state.isRisky ? "Needs a careful answer" : "Waiting on you")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(accent)
                Spacer(minLength: 6)
                if let since = state.blockedSince {
                    // Ticks by itself. An ActivityKit update per second would burn the
                    // budget the system meters us on.
                    Text(since, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            // The question, not the session name. The session name is the least useful
            // string on this card and it used to be the headline.
            Text(state.lastLine.isEmpty ? "\(attributes.session) is waiting" : state.lastLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let why = state.riskWhy {
                Text(why)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                AgentBadge(type: state.agentType)
                Text("\(attributes.session) · \(attributes.host)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(state.riskVerb ?? "Open")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent)
            }
        }
        .padding()
        .background(accent.opacity(0.14))
    }

    // MARK: Running

    private var running: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    AgentBadge(type: state.agentType)
                    Text(attributes.session).font(.headline).lineLimit(1)
                }
                HStack(spacing: 6) {
                    SessionStatusLabel(state: state.state)
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

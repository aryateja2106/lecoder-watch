import SwiftUI

// The shared vocabulary for "what is this session doing right now" — phone, watch,
// Lock Screen and Dynamic Island all say it the same way, so a glance means the same
// thing wherever you glance.
//
// SwiftUI-only (Color), which is why it is here and not in Models.swift: the headless
// self-checks compile Models.swift with bare swiftc and must stay free of SwiftUI.

extension SessionState {
    /// One word, in the user's language rather than the classifier's.
    var cardLabel: String {
        switch self {
        case .waiting: return "Needs you"
        case .running: return "Working"
        case .idle:    return "Idle"
        case .error:   return "Error"
        case .unknown: return "—"
        }
    }

    /// The single hue that carries meaning on a card (dot + status word).
    var tint: Color {
        switch self {
        case .waiting: return .orange
        case .running: return .green
        case .idle:    return .secondary
        case .error:   return .red
        case .unknown: return .gray
        }
    }

    /// Glyph for the Dynamic Island's compact and minimal regions, where no text fits.
    var symbol: String {
        switch self {
        case .waiting: return "questionmark.circle.fill"
        case .running: return "gearshape.2.fill"
        case .idle:    return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .unknown: return "circle.dashed"
        }
    }

}

/// The status to show when there is no live output to classify — most list rows.
/// Levels are the ones `mesh-hook` grades: warning means the agent asked a question.
func cardState(forLevel level: String?, attached: Bool) -> SessionState {
    let graded = cardStateForLevel(level)
    return graded == .unknown ? (attached ? .running : .idle) : graded
}

/// Canonical display name for an agent type, shared by the badge and notification copy
/// so the casing always agrees.
func displaySourceLabel(_ source: String?) -> String {
    let raw = (source ?? "").lowercased()
    switch raw {
    case "claude":             return "Claude"
    case "codex":              return "Codex"
    case "pi", "raspberry-pi": return "Pi"
    case "", "shell":          return "Shell"
    default:                   return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}

/// Small capsule badge for an agent type.
struct AgentBadge: View {
    let type: String?

    private var spec: (label: String, symbol: String, tint: Color) {
        switch (type ?? "").lowercased() {
        case "claude": return ("Claude", "sparkles", .blue)
        case "codex":  return ("Codex", "chevron.left.forwardslash.chevron.right", .purple)
        default:       return (displaySourceLabel(type), "terminal", .secondary)
        }
    }

    var body: some View {
        let s = spec
        Label(s.label, systemImage: s.symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(s.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(s.tint)
    }
}

/// Coloured status dot plus the word.
struct SessionStatusLabel: View {
    let state: SessionState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.tint).frame(width: 7, height: 7)
            Text(state.cardLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(state.tint)
        }
    }
}

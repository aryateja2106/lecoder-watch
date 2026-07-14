import SwiftUI

// Codync-style session vocabulary shared by phone, watch, and notification copy.
// SwiftUI-only (Color), so it lives here and NOT in Models.swift — the headless
// notification self-check compiles Models.swift/NotifPrefs.swift with bare swiftc
// and must stay free of SwiftUI.

extension SessionState {
    /// One-word status, Codync-toned.
    var cardLabel: String {
        switch self {
        case .waiting: return "Needs input"
        case .running: return "Working…"
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

    /// Glyph for the Dynamic Island compact/minimal regions (where text won't fit).
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

/// Map an event level to the status a card should show when there's no live
/// output to classify (most list cards). Reuses notifKind — no new classifier.
func cardState(forLevel level: String?, attached: Bool) -> SessionState {
    switch notifKind(for: level) {
    case .needsInput: return .waiting
    case .error:      return .error
    case .finished:   return .idle
    case nil:         return attached ? .running : .idle
    }
}

/// Canonical display name for an agent source/type, shared by the badge and the
/// notification title so casing always agrees.
func displaySourceLabel(_ source: String?) -> String {
    switch (source ?? "").lowercased() {
    case "claude":            return "Claude"
    case "codex":             return "Codex"
    case "pi", "raspberry-pi": return "Pi"
    case "", "shell":         return "Shell"
    default:                  return source!.capitalized
    }
}

/// Small capsule badge for an agent type (claude/codex/shell), Codync's model-badge stand-in.
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

/// Colored status dot + word, the Codync "Editing code / Idle / Needs input" line.
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

/// "Primary" pill shown on the pinned session (leads the Live Activity, pings on completion).
struct PrimaryPill: View {
    var body: some View {
        Label("Primary", systemImage: "pin.fill")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.18), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}

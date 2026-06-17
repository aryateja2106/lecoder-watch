import SwiftUI

// MARK: - MeshWatch Design System
//
// Rich-monochrome foundation: near-black surfaces, greyscale hierarchy, exactly ONE
// non-status accent (blue). Semantic status colors are reserved for STATE only:
//   green = working/ok · orange = needs input/auth · red = destructive/error · grey = idle/offline.
//
// ponytail: this is the shared base every later slice consumes (Add-Host, Vault, VNC,
// Terminal). VNC-only primitives (RemoteCanvas, ModifierKeyStrip, CommandDeck) live with
// the VNC slice; this file holds only what is reused across screens.

enum MW {
    // Surfaces (near-black → raised → control)
    static let base    = Color(hex: 0x0A0B0D)
    static let raised  = Color(hex: 0x15171A)
    static let control = Color(hex: 0x1E2125)
    static let hairline = Color(hex: 0x2A2D31)

    // Text hierarchy
    static let textPrimary   = Color(hex: 0xF5F6F7)
    static let textSecondary = Color(hex: 0x9BA0A6)
    static let textTertiary  = Color(hex: 0x5C6066)

    // The one accent.
    static let accent = Color(hex: 0x4DA3FF)

    // Semantic status — state only, never decoration.
    static let ok    = Color(hex: 0x34C759)
    static let warn  = Color(hex: 0xFF9F0A)
    static let error = Color(hex: 0xFF453A)
    static let idle  = Color(hex: 0x5C6066)
}

extension Color {
    /// `Color(hex: 0x4DA3FF)` — opaque RGB from a 24-bit literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Semantic status

/// The single source of truth for "what state is this in" → color + symbol.
enum MWStatus {
    case ok                 // working / connected / reachable
    case needsInput         // waiting on auth / a decision (orange)
    case error              // failed / destructive outcome
    case connecting         // in progress
    case offline            // idle / unreachable

    var color: Color {
        switch self {
        case .ok: return MW.ok
        case .needsInput: return MW.warn
        case .error: return MW.error
        case .connecting: return MW.accent
        case .offline: return MW.idle
        }
    }

    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .needsInput: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .offline: return "circle"
        }
    }

    var label: String {
        switch self {
        case .ok: return "Connected"
        case .needsInput: return "Needs input"
        case .error: return "Error"
        case .connecting: return "Connecting"
        case .offline: return "Offline"
        }
    }
}

// MARK: - GroupedInsetSection
//
// The one styling primitive: a rounded inset container with hairline-divided rows and an
// optional header/footer caption. Everything dense is built from this.

struct GroupedInsetSection<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MW.textTertiary)
                    .padding(.leading, 16)
            }
            VStack(spacing: 0) {
                _VariadicHairline { content }
            }
            .background(MW.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(MW.textTertiary)
                    .padding(.horizontal, 16)
            }
        }
    }
}

/// Inserts hairline dividers between a section's rows without each row knowing its neighbours.
/// ponytail: `_VariadicView` is the native way to walk children; no manual array plumbing.
private struct _VariadicHairline<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        _VariadicView.Tree(_HairlineLayout()) { content }
    }
}

private struct _HairlineLayout: _VariadicView_MultiViewRoot {
    @ViewBuilder func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            if child.id != last {
                Divider().overlay(MW.hairline).padding(.leading, 16)
            }
        }
    }
}

// MARK: - StatusPill
//
// Compact live state, also doubles as a sheet Done affordance (`.done` style).

struct StatusPill: View {
    let status: MWStatus
    var text: String? = nil       // override the default label; nil = symbol-only chip
    var style: Style = .chip

    enum Style { case chip, done }

    var body: some View {
        switch style {
        case .done:
            // Trailing circular Done check pill (native sheet vocabulary).
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MW.base)
                .frame(width: 30, height: 30)
                .background(MW.accent, in: Circle())
                .accessibilityLabel("Done")
        case .chip:
            HStack(spacing: 5) {
                Image(systemName: status.symbol)
                    .font(.caption2.weight(.semibold))
                if let text {
                    Text(text).font(.caption.weight(.medium))
                }
            }
            .foregroundStyle(status.color)
            .padding(.horizontal, text == nil ? 0 : 8)
            .padding(.vertical, text == nil ? 0 : 4)
            .background(
                text == nil ? Color.clear : status.color.opacity(0.14),
                in: Capsule()
            )
            .accessibilityLabel(text ?? status.label)
        }
    }
}

// MARK: - KeyValueRow / DisclosureRow
//
// The read-vs-act split lives here: facts use KeyValueRow (no chevron); settings/actions
// use DisclosureRow (chevron → presents a picker).

struct KeyValueRow: View {
    let label: String
    let value: String
    var secondary: String? = nil   // e.g. "(RTT ~56ms)" beneath the value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(MW.textPrimary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundStyle(MW.textSecondary)
                    .multilineTextAlignment(.trailing)
                if let secondary {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(MW.textTertiary)
                }
            }
        }
        .font(.body)
        .accessibilityElement(children: .combine)
    }
}

struct DisclosureRow: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).foregroundStyle(MW.textPrimary)
                Spacer()
                Text(value).foregroundStyle(MW.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MW.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }
}

// MARK: - KeyCap
//
// One key in a modifier strip. ≥44pt. Sticky modifiers latch with a persistent accent border.

struct KeyCap: View {
    let label: String
    var systemImage: String? = nil
    var state: KeyState = .normal
    let action: () -> Void

    enum KeyState { case normal, pressed, latched, disabled }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(label)
                }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(foreground)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(state == .latched ? MW.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(state == .disabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(state == .latched ? [.isSelected] : [])
    }

    private var foreground: Color {
        switch state {
        case .disabled: return MW.textTertiary
        case .latched: return MW.accent
        default: return MW.textPrimary
        }
    }

    private var background: Color {
        switch state {
        case .pressed: return MW.accent.opacity(0.2)
        case .latched: return MW.accent.opacity(0.12)
        default: return MW.control
        }
    }
}

// MARK: - SessionListCard
//
// The reusable host / vault-identity / key / session row: accent icon · title · subtitle ·
// trailing accessory. Active / connecting / offline variants via `status`.

struct SessionListCard: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var status: MWStatus = .ok
    var trailingText: String? = nil     // e.g. "2 sess"
    var showChevron: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        let row = HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(MW.accent)
                .frame(width: 34, height: 34)
                .background(MW.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(MW.textPrimary).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(MW.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailingText {
                Text(trailingText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(status.color)
            } else {
                Image(systemName: status.symbol)
                    .font(.subheadline)
                    .foregroundStyle(status.color)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MW.textTertiary)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

#if DEBUG
#Preview("Foundation") {
    ScrollView {
        VStack(spacing: 20) {
            GroupedInsetSection(header: "Connection", footer: "Stored in Apple Keychain.") {
                KeyValueRow(label: "Desktop Size", value: "2560 × 1440")
                KeyValueRow(label: "Estimated Speed", value: "7938 kbit/s", secondary: "(RTT ~56ms)")
                DisclosureRow(label: "Picture Quality", value: "Automatic") {}
            }
            GroupedInsetSection {
                SessionListCard(symbol: "desktopcomputer", title: "arya-mac", subtitle: "meshd active · bridge · hooks", status: .ok, trailingText: "2 sess")
                SessionListCard(symbol: "pc", title: "dataflowagents", subtitle: "token needed", status: .needsInput, trailingText: "token")
            }
            HStack(spacing: 8) {
                KeyCap(label: "ctrl", state: .latched) {}
                KeyCap(label: "esc") {}
                KeyCap(label: "del", state: .disabled) {}
                Spacer()
                StatusPill(status: .ok, style: .done)
            }
        }
        .padding()
    }
    .background(MW.base)
    .preferredColorScheme(.dark)
}
#endif

import SwiftUI

// MARK: - TerminalSurface
//
// The lively layer: a framed mono scrollback card on near-black with ANSI-style green/amber/red
// line tones, a blinking cursor, and a jump-to-latest chip. The shell around it stays monochrome;
// this is where the life is. Replaces the plain black output box.

struct TerminalSurface: View {
    let lines: [String]
    var isLive: Bool = true

    @State private var blink = false
    private let bottomID = "terminal-bottom"

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        if lines.isEmpty {
                            Text("No output yet.")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(MW.textTertiary)
                        } else {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Self.tone(for: line))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        // Blinking block cursor on the prompt line.
                        HStack(spacing: 0) {
                            Text("▋")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(MW.ok)
                                .opacity(blink ? 1 : 0.15)
                            Spacer()
                        }
                        .id(bottomID)
                    }
                    .padding(12)
                }
                .onChange(of: lines.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo(bottomID, anchor: .bottom) }
                // Jump-to-latest chip — taps back to the live tail after scrolling up.
                .overlay(alignment: .bottomTrailing) {
                    Button { withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) } } label: {
                        Label("Latest", systemImage: "arrow.down.to.line")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(MW.control, in: Capsule())
                            .foregroundStyle(MW.accent)
                            .overlay(Capsule().strokeBorder(MW.hairline, lineWidth: 0.5))
                    }
                    .padding(10)
                    .accessibilityLabel("Jump to latest output")
                }
            }
        }
        .frame(minHeight: 160, maxHeight: 320)
        .background(MW.base, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(MW.ok.opacity(isLive ? 0.35 : 0.12), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { blink = true }
        }
    }

    /// Coarse ANSI-ish tone per line. Neutral phosphor by default; only state-bearing lines
    /// take a semantic color (the contract: green=ok, amber=needs input, red=error).
    static func tone(for line: String) -> Color {
        let l = line.lowercased()
        let err = ["error", "fatal", "panic", "command not found", "no such file",
                   "permission denied", "exception", "failed", "✗", "✘"]
        if err.contains(where: l.contains) { return MW.error }
        let warn = ["(y/n)", "[y/n]", "proceed?", "continue?", "do you want", "press enter",
                    "warning", "deprecated", "overwrite?"]
        if warn.contains(where: l.contains) { return MW.warn }
        let ok = ["✓", "✔", "passed", "success", "build succeeded", " ok", "done", "ready"]
        if ok.contains(where: l.contains) { return MW.ok }
        if let last = line.trimmingCharacters(in: .whitespaces).last, "$%#❯→".contains(last) { return MW.ok }
        return Color(hex: 0xC8D0D4)   // neutral phosphor
    }
}

// MARK: - InputBar
//
// Voice-first dual-mode bar: a mic (tap to dictate via the keyboard), a center field that
// raises the keyboard, and a send button that brightens with text. Replaces the dead split
// Reply/Command sheets — one always-visible place to talk to the session.

struct InputBar: View {
    @Binding var text: String
    var placeholder: String = "Message, paste, or dictate…"
    let onSend: () -> Void
    var onMic: (() -> Void)? = nil

    @FocusState private var focused: Bool

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if let onMic { onMic() } else { focused = true }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(MW.accent)
                    .frame(width: 44, height: 44)
                    .background(MW.control, in: Circle())
            }
            .accessibilityLabel("Dictate")

            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .foregroundStyle(MW.textPrimary)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MW.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .submitLabel(.send)
                .onSubmit { if hasText { onSend() } }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(hasText ? MW.accent : MW.textTertiary)
            }
            .disabled(!hasText)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

#if DEBUG
#Preview("TerminalSurface") {
    VStack(spacing: 0) {
        TerminalSurface(lines: [
            "$ git status",
            "On branch codex/redesign-exp-1",
            "error: failed to push some refs",
            "warning: 3 files changed",
            "✓ build succeeded",
            "arya@dataflowagents:~$ ",
        ])
        .padding()
        InputBar(text: .constant("continue"), onSend: {})
    }
    .background(MW.base)
    .preferredColorScheme(.dark)
}
#endif

import SwiftUI
import UIKit

// MARK: - Agent branding (cosmetic only — never gates behavior)

enum AgentCLIKind: String {
    case claude = "Claude Code"
    case codex = "ChatGPT Codex"
    case cursor = "Cursor Agent"
    case antigravity = "Antigravity"
    case hermes = "Hermes"
    case openclaw = "OpenClaw"
    case shell = "CLI Agent"

    static func detect(from name: String, agentType: String?) -> AgentCLIKind {
        let combined = "\(name) \(agentType ?? "")".lowercased()
        if combined.contains("claude") { return .claude }
        if combined.contains("codex") { return .codex }
        if combined.contains("cursor") { return .cursor }
        if combined.contains("agy") || combined.contains("antigravity") || combined.contains("omp") { return .antigravity }
        if combined.contains("hermes") { return .hermes }
        if combined.contains("claw") || combined.contains("openclaw") { return .openclaw }
        return .shell
    }

    var iconName: String {
        switch self {
        case .claude: return "sparkles"
        case .codex: return "cpu"
        case .cursor: return "cursorarrow.rays"
        case .antigravity: return "atom"
        case .hermes: return "paperplane"
        case .openclaw: return "hammer"
        case .shell: return "terminal"
        }
    }

    var brandColor: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.45, blue: 0.25)
        case .codex: return Color(red: 0.10, green: 0.65, blue: 0.50)
        case .cursor: return Color(red: 0.20, green: 0.50, blue: 0.95)
        case .antigravity: return Color(red: 0.60, green: 0.30, blue: 0.90)
        case .hermes: return Color(red: 0.95, green: 0.70, blue: 0.10)
        case .openclaw: return Color(red: 0.90, green: 0.25, blue: 0.35)
        case .shell: return .secondary
        }
    }
}

// MARK: - Artifact sentinels
//
// `native-app-builder` / `pwa-local-app-builder` (`.agents/skills/`) print an HTML
// comment when a build finishes: `<!-- APP_READY slug="…" name="…" -->` or
// `<!-- PWA_READY slug="…" name="…" url="…" -->`. This is the one piece of
// text-scanning kept from the original draft — everything else an agent might print
// (a `$ ` prompt, a `<thinking>` tag) is either not real or now carried structurally
// by `ChatMessage`, but no daemon route hands over "a build finished," so the
// sentinel is still the only signal there is.
enum ArtifactKind {
    case nativeApp
    case pwa
}

struct AgentArtifact: Identifiable, Equatable {
    var id: String { slug }
    var title: String
    var kind: ArtifactKind
    var slug: String
    /// PWA only — the real LAN URL the sentinel carried. Never fabricated: a native
    /// artifact has no preview URL, and a malformed PWA sentinel yields no artifact
    /// at all rather than a guessed `localhost` link nobody's phone can reach.
    var url: URL?
}

enum ArtifactSentinel {
    private static let appReady = #"<!--\s*APP_READY\s+slug=["']([^"']+)["']\s+name=["']([^"']+)["']\s*-->"#
    private static let pwaReady = #"<!--\s*PWA_READY\s+slug=["']([^"']+)["']\s+name=["']([^"']+)["']\s+url=["']([^"']+)["']\s*-->"#

    static func scan(_ text: String) -> AgentArtifact? {
        if let range = text.range(of: appReady, options: .regularExpression) {
            let tag = String(text[range])
            let slug = attribute(tag, "slug") ?? "app"
            let name = attribute(tag, "name") ?? "New App"
            return AgentArtifact(title: name, kind: .nativeApp, slug: slug, url: nil)
        }
        if let range = text.range(of: pwaReady, options: .regularExpression) {
            let tag = String(text[range])
            let slug = attribute(tag, "slug") ?? "app"
            let name = attribute(tag, "name") ?? "Web App"
            guard let raw = attribute(tag, "url"), let url = URL(string: raw) else { return nil }
            return AgentArtifact(title: name, kind: .pwa, slug: slug, url: url)
        }
        return nil
    }

    private static func attribute(_ tag: String, _ name: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\(name)=[\"']([^\"']+)[\"']") else { return nil }
        let ns = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}

// MARK: - Agent Chat View

/// The chat-shaped view of a session, alongside the raw terminal (`SessionPeekScreen`'s
/// `ViewMode` picker toggles between them). Structure comes from meshd's own
/// `GET /agents/:n/chat` (capability "chat") — a Claude Code / Codex transcript the
/// daemon already parsed — not from regex over polled terminal text. `SessionPeekScreen`
/// owns the poll (same adaptive cadence as the terminal view) and hands the result down.
struct AgentChatView: View {
    @EnvironmentObject var store: MeshStore
    let machine: Machine
    let session: Agent
    /// Structured transcript for this poll. Empty when the daemon lacks "chat", when
    /// it fell back to capture-pane text (`chatSource == "output"`), or before the
    /// first poll lands — `rawLines` carries the view in all three cases.
    let messages: [ChatMessage]
    let chatSource: String
    let rawLines: [String]
    let onSendText: (String) -> Void
    /// Named keys only (`"ctrl-c"`, `"enter"`, `"escape"`, …) — the same vocabulary
    /// `client.send(key:)` and `AgentNotification.command(for:typed:)` use. A raw
    /// control byte in a text field is not how this app tells a session to stop.
    let onSendKey: (String) -> Void
    let onOpenTerminal: () -> Void

    @State private var inputText = ""
    @State private var selectedArtifact: AgentArtifact?

    private var agentKind: AgentCLIKind {
        AgentCLIKind.detect(from: session.name, agentType: session.agentType)
    }

    /// Structured transcript wins once the daemon has produced one; a capture-pane
    /// fallback (or no chat capability yet) shows the same terminal block the
    /// Terminal tab does.
    private var showStructured: Bool { !messages.isEmpty && chatSource != "output" }

    /// The newest event this app holds for this session, matched the same tolerant
    /// way `WatchMeshStore.latestEvent` does — the daemon's name for a host is not
    /// always the name this app stored it under.
    private var latestEvent: AgentEvent? {
        store.events.last { event in
            guard let eventHost = event.host, event.session == session.name else { return false }
            return hostNamesMatch(eventHost, machine.host)
        }
    }

    /// The truth for "is this session blocked on a human", per meshd 0.5.0+
    /// ("sessionStatus"): the daemon's own verdict, not a `[y/n]` guess over text a
    /// TUI might never even print that way. `replyable == false` means the hook could
    /// not resolve a reply route — showing Allow/Deny then would answer nothing.
    private var awaitingDecision: Bool {
        session.status == "waiting" && latestEvent?.replyable != false
    }

    private var decisionText: String {
        messages.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text
            ?? rawLines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? "Waiting for your input."
    }

    private var decisionRisk: RiskVerdict { classifyRisk(decisionText) }

    var body: some View {
        VStack(spacing: 0) {
            agentBanner
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if showStructured {
                            ForEach(messages) { message in
                                messageRow(message).id(message.id)
                            }
                        } else {
                            TerminalFallbackBlock(lines: rawLines).id("fallback")
                        }
                        if awaitingDecision {
                            DecisionCard(
                                text: decisionText,
                                risk: decisionRisk,
                                onAllow: { onSendKey("enter") },
                                onDeny: { onSendKey("escape") }
                            )
                            .id("decision")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .onAppear { scrollToEnd(proxy, animated: false) }
                .onChange(of: messages.count) { _, _ in scrollToEnd(proxy, animated: true) }
                .onChange(of: rawLines.count) { _, _ in scrollToEnd(proxy, animated: true) }
                .onChange(of: awaitingDecision) { _, _ in scrollToEnd(proxy, animated: true) }
            }
            suggestionPills
            inputBar
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $selectedArtifact) { artifact in
            ArtifactDetailSheet(
                artifact: artifact,
                onOpen: {
                    guard let url = artifact.url else { return }
                    // Real Safari, not SFSafariViewController: Add to Home Screen only
                    // exists in the former.
                    UIApplication.shared.open(url)
                },
                onInstall: {
                    try await store.client(for: machine).installMeshApp(slug: artifact.slug, target: "device")
                }
            )
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        let anchor: String
        if awaitingDecision { anchor = "decision" }
        else if showStructured, let last = messages.last { anchor = last.id }
        else { anchor = "fallback" }
        if animated {
            withAnimation { proxy.scrollTo(anchor, anchor: .bottom) }
        } else {
            proxy.scrollTo(anchor, anchor: .bottom)
        }
    }

    // MARK: - Row rendering

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.role {
        case "thinking":
            if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ThinkingDisclosure(text: message.text, tint: agentKind.brandColor)
            }
        case "tool", "result":
            ToolResultCard(message: message)
        case "system":
            TerminalFallbackBlock(lines: [message.text])
        default:   // "user", "assistant", and anything future the daemon adds
            if let artifact = ArtifactSentinel.scan(message.text) {
                ArtifactCardView(artifact: artifact) { selectedArtifact = artifact }
            } else if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ChatBubble(text: message.text, isUser: message.role == "user", tint: agentKind.brandColor)
            }
        }
    }

    // MARK: - Subviews

    private var agentBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(agentKind.brandColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: agentKind.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(agentKind.brandColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agentKind.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(session.name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(machine.host)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { onOpenTerminal() } label: {
                Label("Terminal", systemImage: "terminal")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var suggestionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // No Team ID / bundle prefix baked in here: the skill derives those
                // from `mesh apps config` or asks, because this app ships to people
                // who are not its author.
                SuggestionChip(title: "Build a native iOS app", icon: "hammer.fill") {
                    onSendText("Build a native iOS app with SwiftUI and XcodeGen\n")
                }
                SuggestionChip(title: "Build a web app", icon: "globe") {
                    onSendText("Build a progressive web app with offline storage\n")
                }
                SuggestionChip(title: "Run tests", icon: "checkmark.circle.fill") {
                    onSendText("Run the project test suite\n")
                }
                SuggestionChip(title: "Status", icon: "questionmark.circle") {
                    onSendText("What is the current status of this task?\n")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask or command \(agentKind.rawValue)…", text: $inputText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .submitLabel(.send)
                .onSubmit { submit() }

            if inputText.isEmpty {
                Button { onSendText("y\n") } label: {
                    Text("Y")
                        .font(.subheadline.bold())
                        .frame(width: 34, height: 34)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(Circle())
                }
                Button { onSendKey("ctrl-c") } label: {
                    Image(systemName: "stop.fill")
                        .font(.subheadline)
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Circle())
                }
            } else {
                Button { submit() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(agentKind.brandColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func submit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSendText(trimmed + "\n")
        inputText = ""
    }
}

// MARK: - Decision card
//
// Replaces per-message `[y/n]` / "Allow?" text matching: shown once, driven by the
// session's own `status` field, not guessed from whatever a TUI happened to print.

private struct DecisionCard: View {
    let text: String
    let risk: RiskVerdict
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: risk.isDestructive ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                    .foregroundStyle(risk.isDestructive ? Color.red : Color.orange)
                Text("Waiting on you")
                    .font(.subheadline.bold())
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            if risk.isDestructive, let consequence = risk.consequence {
                Text(consequence)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                Button(action: onAllow) {
                    Text(risk.verb)
                        .font(.caption.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(risk.isDestructive ? Color.red : Color.green)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                Button(action: onDeny) {
                    Text("Deny")
                        .font(.caption.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(risk.isDestructive ? Color.red.opacity(0.08) : Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(risk.isDestructive ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Message rows

private struct ChatBubble: View {
    let text: String
    let isUser: Bool
    let tint: Color

    var body: some View {
        HStack {
            if isUser { Spacer() }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? tint : Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer() }
        }
    }
}

private struct ThinkingDisclosure: View {
    let text: String
    let tint: Color
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(tint)
                Text("Thinking")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One card for both a tool call in flight and its result — meshd sends them as
/// separate messages (role `tool`, then `result`), but they read as one event.
private struct ToolResultCard: View {
    let message: ChatMessage

    private var dotColor: Color {
        switch message.status {
        case "error": return .red
        case "running": return .orange
        default: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message.tool?.name ?? (message.role == "result" ? "Result" : "Tool"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Circle().fill(dotColor).frame(width: 6, height: 6)
            }
            let detail = message.tool?.input ?? message.text
            if !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// What renders before the first structured poll lands, when the daemon lacks
/// "chat", or when it fell back to capture-pane text (`source == "output"`) — the
/// same black monospace block `SessionPeekScreen`'s Terminal mode uses, so switching
/// the picker never changes what the text looks like, only how much of it groups.
private struct TerminalFallbackBlock: View {
    let lines: [String]

    private var text: String {
        var trimmed = Array(lines.suffix(60))
        while let first = trimmed.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { trimmed.removeFirst() }
        while let last = trimmed.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { trimmed.removeLast() }
        return trimmed.joined(separator: "\n")
    }

    var body: some View {
        Group {
            if text.isEmpty {
                Text("No output yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(.white)
    }
}

// MARK: - Artifact card + detail sheet

struct ArtifactCardView: View {
    let artifact: AgentArtifact
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(artifact.kind == .nativeApp ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: artifact.kind == .nativeApp ? "iphone.badge.play" : "globe.badge.chevron.backward")
                        .font(.title3)
                        .foregroundStyle(artifact.kind == .nativeApp ? Color.blue : Color.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(artifact.kind == .nativeApp ? "Native iOS app" : "Web app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct ArtifactDetailSheet: View {
    let artifact: AgentArtifact
    /// PWA only: opens `artifact.url` in real Safari.
    let onOpen: () -> Void
    /// Native only: `POST /apps/:slug/install`. Thrown errors and `{ok:false,error}`
    /// both surface as `installMessage` — a tap that silently did nothing is
    /// indistinguishable from one that worked, which is the one thing not to do here.
    let onInstall: () async throws -> MeshAppInstallResult
    @Environment(\.dismiss) private var dismiss
    @State private var installing = false
    @State private var installMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(artifact.kind == .nativeApp ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Image(systemName: artifact.kind == .nativeApp ? "app.badge.checkmark.fill" : "globe.americas.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(artifact.kind == .nativeApp ? Color.blue : Color.green)
                }
                .padding(.top, 24)

                VStack(spacing: 6) {
                    Text(artifact.title).font(.title2.bold())
                    Text(artifact.slug)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    if artifact.kind == .nativeApp {
                        infoRow(icon: "arrow.down.app", title: "Install", detail: "Straight to this iPhone")
                        infoRow(icon: "personalhotspot", title: "Requires", detail: "Paired over your network")
                    } else {
                        infoRow(icon: "internaldrive", title: "Storage", detail: "Local to this device")
                        infoRow(icon: "plus.app", title: "Add to Home Screen", detail: "From Safari's Share sheet")
                        infoRow(icon: "wifi.slash", title: "Offline", detail: "Only if the agent enabled a service worker")
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if let installMessage {
                    Text(installMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if artifact.kind == .nativeApp {
                    Button {
                        Task {
                            installing = true
                            do {
                                let result = try await onInstall()
                                installMessage = result.ok ? "Installed." : (result.error ?? "Install failed.")
                            } catch {
                                installMessage = "Couldn't reach the machine to install."
                            }
                            installing = false
                        }
                    } label: {
                        HStack {
                            if installing { ProgressView().tint(.white) }
                            Label(installing ? "Installing…" : "Install to iPhone", systemImage: "arrow.down.app.fill")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(installing)
                } else {
                    Button {
                        onOpen()
                        dismiss()
                    } label: {
                        Label("Open & Add to Home Screen", systemImage: "safari.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(artifact.url == nil)
                }
            }
            .padding(20)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func infoRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Helper views

struct SuggestionChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

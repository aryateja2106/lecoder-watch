import SwiftUI
import SafariServices

// MARK: - Agent Chat Model & Types

enum AgentRole: String, Codable {
    case user
    case assistant
    case system
}

enum ToolStatus: String, Codable {
    case running
    case success
    case failure
}

enum ArtifactType: String, Codable {
    case nativeApp
    case pwa
    case file
    case webPreview
}

struct AgentChatMessage: Identifiable, Equatable {
    let id: String
    var role: AgentRole
    var text: String
    var timestamp: Date
    var thinking: String?
    var toolCall: AgentToolCall?
    var approvalRequest: AgentApprovalRequest?
    var artifact: AgentArtifact?

    static func == (lhs: AgentChatMessage, rhs: AgentChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.text == rhs.text &&
        lhs.thinking == rhs.thinking &&
        lhs.toolCall == rhs.toolCall &&
        lhs.approvalRequest == rhs.approvalRequest &&
        lhs.artifact == rhs.artifact
    }
}

struct AgentToolCall: Equatable {
    var toolName: String
    var command: String?
    var output: String?
    var status: ToolStatus
}

struct AgentApprovalRequest: Equatable {
    var prompt: String
    var options: [String]
    var isDangerous: Bool
}

struct AgentArtifact: Identifiable, Equatable {
    var id: String { slug }
    var title: String
    var type: ArtifactType
    var slug: String
    var previewUrl: URL?
    var installUrl: URL?
}

// MARK: - Agent Output Parser

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

enum AgentOutputParser {
    static func parse(lines: [String], agentKind: AgentCLIKind) -> [AgentChatMessage] {
        var messages: [AgentChatMessage] = []
        var currentThinking: [String] = []
        var inThinking = false
        var accumulatedAssistantText: [String] = []

        func flushAssistant() {
            let joined = accumulatedAssistantText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                messages.append(AgentChatMessage(
                    id: "msg_\(messages.count)_\(UUID().uuidString.prefix(6))",
                    role: .assistant,
                    text: joined,
                    timestamp: Date(),
                    thinking: nil,
                    toolCall: nil,
                    approvalRequest: nil,
                    artifact: nil
                ))
                accumulatedAssistantText.removeAll()
            }
        }

        func flushThinking() {
            let joined = currentThinking.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                messages.append(AgentChatMessage(
                    id: "think_\(messages.count)_\(UUID().uuidString.prefix(6))",
                    role: .assistant,
                    text: "Thinking...",
                    timestamp: Date(),
                    thinking: joined,
                    toolCall: nil,
                    approvalRequest: nil,
                    artifact: nil
                ))
                currentThinking.removeAll()
            }
        }

        for rawLine in lines {
            let line = cleanAnsi(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // 1. Thinking markers
            if trimmed.contains("<thinking>") || trimmed.contains("Thinking...") {
                flushAssistant()
                inThinking = true
                currentThinking.append(trimmed.replacingOccurrences(of: "<thinking>", with: ""))
                continue
            }
            if trimmed.contains("</thinking>") {
                currentThinking.append(trimmed.replacingOccurrences(of: "</thinking>", with: ""))
                flushThinking()
                inThinking = false
                continue
            }
            if inThinking {
                currentThinking.append(trimmed)
                continue
            }

            // 2. Artifact: Native App Ready (from devcluster/mesh)
            if let readyMatch = trimmed.range(of: #"<!--\s*APP_READY\s+slug=["']([^"']+)["']\s+name=["']([^"']+)["']\s*-->"#, options: .regularExpression) {
                flushAssistant()
                let matchString = String(trimmed[readyMatch])
                let slug = extractAttribute(matchString, attr: "slug") ?? "app"
                let name = extractAttribute(matchString, attr: "name") ?? "New App"
                let installUrl = URL(string: "itms-services://?action=download-manifest&url=https://localhost/releases/\(slug)/manifest.plist")
                messages.append(AgentChatMessage(
                    id: "artifact_\(slug)",
                    role: .assistant,
                    text: "Built native iOS application: \(name)",
                    timestamp: Date(),
                    thinking: nil,
                    toolCall: nil,
                    approvalRequest: nil,
                    artifact: AgentArtifact(
                        title: name,
                        type: .nativeApp,
                        slug: slug,
                        previewUrl: nil,
                        installUrl: installUrl
                    )
                ))
                continue
            }

            // 3. Artifact: PWA / Local Web App Ready
            if let pwaMatch = trimmed.range(of: #"<!--\s*PWA_READY\s+slug=["']([^"']+)["']\s+name=["']([^"']+)["']\s*(?:url=["']([^"']+)["'])?\s*-->"#, options: .regularExpression) {
                flushAssistant()
                let matchString = String(trimmed[pwaMatch])
                let slug = extractAttribute(matchString, attr: "slug") ?? "app"
                let name = extractAttribute(matchString, attr: "name") ?? "Web App"
                let explicitUrl = extractAttribute(matchString, attr: "url")
                let previewUrl = URL(string: explicitUrl ?? "http://localhost:7777/apps/\(slug)/")
                messages.append(AgentChatMessage(
                    id: "pwa_\(slug)",
                    role: .assistant,
                    text: "Built progressive web app: \(name)",
                    timestamp: Date(),
                    thinking: nil,
                    toolCall: nil,
                    approvalRequest: nil,
                    artifact: AgentArtifact(
                        title: name,
                        type: .pwa,
                        slug: slug,
                        previewUrl: previewUrl,
                        installUrl: nil
                    )
                ))
                continue
            }

            // 4. Approval request patterns (e.g. Claude Code or Codex asking permission)
            if trimmed.contains("[y/n]") || trimmed.contains("(y/n)") || trimmed.hasSuffix("Allow?") || trimmed.contains("Do you want to proceed?") {
                flushAssistant()
                messages.append(AgentChatMessage(
                    id: "approval_\(messages.count)",
                    role: .assistant,
                    text: trimmed,
                    timestamp: Date(),
                    thinking: nil,
                    toolCall: nil,
                    approvalRequest: AgentApprovalRequest(
                        prompt: trimmed,
                        options: ["y", "n"],
                        isDangerous: trimmed.lowercased().contains("delete") || trimmed.lowercased().contains("rm ")
                    ),
                    artifact: nil
                ))
                continue
            }

            // 5. Tool execution patterns (e.g. Bash, Edit, Read)
            if trimmed.hasPrefix("$ ") || trimmed.hasPrefix("❯ ") || trimmed.hasPrefix("Run: ") {
                flushAssistant()
                let cmd = trimmed.replacingOccurrences(of: "$ ", with: "")
                    .replacingOccurrences(of: "❯ ", with: "")
                    .replacingOccurrences(of: "Run: ", with: "")
                messages.append(AgentChatMessage(
                    id: "tool_\(messages.count)",
                    role: .assistant,
                    text: "",
                    timestamp: Date(),
                    thinking: nil,
                    toolCall: AgentToolCall(
                        toolName: "Bash",
                        command: cmd,
                        output: nil,
                        status: .running
                    ),
                    approvalRequest: nil,
                    artifact: nil
                ))
                continue
            }

            // Default: accumulate conversational assistant text
            accumulatedAssistantText.append(trimmed)
        }

        if inThinking { flushThinking() }
        flushAssistant()

        // Fallback: If no structured messages were parsed, show latest lines as assistant message
        if messages.isEmpty && !lines.isEmpty {
            let summary = lines.suffix(16).map { cleanAnsi($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
            if !summary.isEmpty {
                messages.append(AgentChatMessage(
                    id: "fallback_latest",
                    role: .assistant,
                    text: summary,
                    timestamp: Date(),
                    thinking: nil,
                    toolCall: nil,
                    approvalRequest: nil,
                    artifact: nil
                ))
            }
        }

        return messages
    }

    private static func extractAttribute(_ tag: String, attr: String) -> String? {
        let pattern = "\(attr)=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: nsString.length)) else { return nil }
        return nsString.substring(with: match.range(at: 1))
    }

    private static func cleanAnsi(_ text: String) -> String {
        text.replacingOccurrences(of: #"\x1B\[[0-9;]*[a-zA-Z]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\x1B\([A-Z0-9]"#, with: "", options: .regularExpression)
    }
}

// MARK: - Agent Chat View

struct AgentChatView: View {
    let machine: Machine
    let session: Agent
    let rawLines: [String]
    let onSendText: (String) -> Void
    let onOpenTerminal: () -> Void

    @State private var inputText = ""
    @State private var isDictating = false
    @State private var showingVoiceRecording = false
    @State private var showingTranscriptionCorrection = false
    @State private var correctionText = ""
    @State private var selectedArtifact: AgentArtifact?
    @State private var showSafari = false
    @State private var safariUrl: URL?
    private var agentKind: AgentCLIKind {
        AgentCLIKind.detect(from: session.name, agentType: session.agentType)
    }

    private var parsedMessages: [AgentChatMessage] {
        AgentOutputParser.parse(lines: rawLines, agentKind: agentKind)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Agent Header
            agentBanner

            Divider()

            // Chat Messages Scroll
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(parsedMessages) { msg in
                            AgentMessageRow(message: msg, agentKind: agentKind, onAction: { action in
                                onSendText(action)
                            }, onOpenArtifact: { artifact in
                                handleArtifactOpen(artifact)
                            })
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .onAppear {
                    if let last = parsedMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: parsedMessages.count) { _, _ in
                    if let last = parsedMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Quick Suggestion Pills
            suggestionPills

            // Bottom Input Bar
            inputBar
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $selectedArtifact) { artifact in
            ArtifactDetailSheet(artifact: artifact, onInstall: {
                if let url = artifact.installUrl {
                    UIApplication.shared.open(url)
                }
            }, onPreview: {
                if let url = artifact.previewUrl {
                    safariUrl = url
                    showSafari = true
                }
            })
        }
        .sheet(isPresented: $showSafari) {
            if let url = safariUrl {
                SafariView(url: url)
            }
        }
        .sheet(isPresented: $showingVoiceRecording) {
            VoiceRecordingSheet(
                machineHost: machine.host,
                agentKind: agentKind,
                onFinish: { text in
                    correctionText = text
                    showingVoiceRecording = false
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        showingTranscriptionCorrection = true
                    }
                },
                onCancel: {
                    showingVoiceRecording = false
                }
            )
        }
        .sheet(isPresented: $showingTranscriptionCorrection) {
            TranscriptionCorrectionSheet(
                initialText: correctionText,
                agentKind: agentKind,
                onSend: { text in
                    showingTranscriptionCorrection = false
                    onSendText(text + "\n")
                },
                onCancel: {
                    showingTranscriptionCorrection = false
                }
            )
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

            Button {
                onOpenTerminal()
            } label: {
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
                SuggestionChip(title: "Build Native iOS App", icon: "hammer.fill") {
                    onSendText("Build native iOS app with SwiftUI and XcodeGen. Team ID: B5B87F7AXF\n")
                }
                SuggestionChip(title: "Build Progressive Web App", icon: "globe") {
                    onSendText("Build a Progressive Web App (PWA) with offline storage and manifest\n")
                }
                SuggestionChip(title: "Run Tests", icon: "checkmark.circle.fill") {
                    onSendText("Run project test suite\n")
                }
                SuggestionChip(title: "Explain Status", icon: "questionmark.circle") {
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
            TextField("Ask or command \(agentKind.rawValue)...", text: $inputText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .submitLabel(.send)
                .onSubmit {
                    submit()
                }

            if inputText.isEmpty {
                Button {
                    showingVoiceRecording = true
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.subheadline.bold())
                        .frame(width: 34, height: 34)
                        .background(agentKind.brandColor.opacity(0.18))
                        .foregroundStyle(agentKind.brandColor)
                        .clipShape(Circle())
                }

                Button {
                    // Quick confirmation keystroke Y
                    onSendText("y\n")
                } label: {
                    Text("Y")
                        .font(.subheadline.bold())
                        .frame(width: 34, height: 34)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(Circle())
                }

                Button {
                    // Quick abort Ctrl+C
                    onSendText("\u{03}")
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.subheadline)
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Circle())
                }
            } else {
                Button {
                    submit()
                } label: {
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

    private func handleArtifactOpen(_ artifact: AgentArtifact) {
        selectedArtifact = artifact
    }
}

// MARK: - Message Row Component

struct AgentMessageRow: View {
    let message: AgentChatMessage
    let agentKind: AgentCLIKind
    let onAction: (String) -> Void
    let onOpenArtifact: (AgentArtifact) -> Void

    @State private var thinkingExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Thinking block
            if let thinking = message.thinking {
                DisclosureGroup(isExpanded: $thinkingExpanded) {
                    Text(thinking)
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
                            .foregroundStyle(agentKind.brandColor)
                        Text("Reasoning / Thinking")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }

            // 2. Tool call card
            if let tool = message.toolCall {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(tool.toolName)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Circle()
                            .fill(tool.status == .running ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                    }

                    if let cmd = tool.command {
                        Text(cmd)
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

            // 3. Approval Request Card
            if let approval = message.approvalRequest {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: approval.isDangerous ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                            .foregroundStyle(approval.isDangerous ? Color.red : Color.orange)
                        Text("Permission Required")
                            .font(.subheadline.bold())
                    }

                    Text(approval.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            onAction("y\n")
                        } label: {
                            Text("Allow (y)")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }

                        Button {
                            onAction("n\n")
                        } label: {
                            Text("Deny (n)")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.red.opacity(0.85))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(14)
                .background(approval.isDangerous ? Color.red.opacity(0.08) : Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(approval.isDangerous ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                )
            }

            // 4. Artifact Card (Native App or PWA)
            if let artifact = message.artifact {
                ArtifactCardView(artifact: artifact) {
                    onOpenArtifact(artifact)
                }
            }

            // 5. Conversational text
            if !message.text.isEmpty && message.artifact == nil {
                HStack {
                    if message.role == .user { Spacer() }

                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        Text(message.text)
                            .font(.subheadline)
                            .foregroundStyle(message.role == .user ? .white : .primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? agentKind.brandColor : Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    if message.role != .user { Spacer() }
                }
            }
        }
    }
}

// MARK: - Artifact Card View

struct ArtifactCardView: View {
    let artifact: AgentArtifact
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(artifact.type == .nativeApp ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: artifact.type == .nativeApp ? "iphone.badge.play" : "globe.badge.chevron.backward")
                        .font(.title3)
                        .foregroundStyle(artifact.type == .nativeApp ? Color.blue : Color.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(artifact.type == .nativeApp ? "Native iOS App • TestFlight/OTA" : "Progressive Web App • Offline Storage")
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

// MARK: - Artifact Detail Sheet

struct ArtifactDetailSheet: View {
    let artifact: AgentArtifact
    let onInstall: () -> Void
    let onPreview: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingWirelessGuide = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(artifact.type == .nativeApp ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Image(systemName: artifact.type == .nativeApp ? "app.badge.checkmark.fill" : "globe.americas.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(artifact.type == .nativeApp ? Color.blue : Color.green)
                }
                .padding(.top, 24)

                VStack(spacing: 6) {
                    Text(artifact.title)
                        .font(.title2.bold())
                    Text(artifact.slug)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    if artifact.type == .nativeApp {
                        infoRow(icon: "signature", title: "Signing", detail: "Apple Team ID: B5B87F7AXF")
                        infoRow(icon: "arrow.down.circle", title: "Distribution", detail: "Wireless OTA / TestFlight")
                        infoRow(icon: "link", title: "Deep Link", detail: "com.aryateja.\(artifact.slug)://")
                    } else {
                        infoRow(icon: "internaldrive", title: "Storage", detail: "Local Browser (IndexedDB / SQLite)")
                        infoRow(icon: "plus.app", title: "Installation", detail: "Add to Home Screen (Safari)")
                        infoRow(icon: "wifi.slash", title: "Offline", detail: "Service Worker Cached")
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Button {
                    showingWirelessGuide = true
                } label: {
                    Label("How wireless installation works without cables", systemImage: "questionmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                if artifact.type == .nativeApp {
                    Button {
                        onInstall()
                        dismiss()
                    } label: {
                        Label("Install on this Device", systemImage: "arrow.down.app.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Button {
                        onPreview()
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
                }
            }
            .padding(20)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Application Artifact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingWirelessGuide) {
                WirelessInstallGuideView()
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

// MARK: - Helper Views

struct SuggestionChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Voice Recording & Transcription Correction Sheets

struct VoiceRecordingSheet: View {
    let machineHost: String
    let agentKind: AgentCLIKind
    let onFinish: (String) -> Void
    let onCancel: () -> Void

    @State private var transcriber = VoiceTranscriber.shared
    @State private var animationScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                // Engine selector
                Picker("Transcription Engine", selection: $transcriber.selectedEngine) {
                    ForEach(TranscriptionEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // Audio Waveform Visualization
                ZStack {
                    Circle()
                        .fill(agentKind.brandColor.opacity(0.12))
                        .frame(width: 140 * animationScale, height: 140 * animationScale)
                        .animation(.easeInOut(duration: 0.2), value: animationScale)

                    Circle()
                        .fill(agentKind.brandColor.opacity(0.25))
                        .frame(width: 100, height: 100)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(agentKind.brandColor)
                }

                // Live Streaming Transcript Box
                VStack(spacing: 8) {
                    Text("Listening to your voice...")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(transcriber.recognizedText.isEmpty ? "Speak your prompt or instructions to \(agentKind.rawValue)..." : transcriber.recognizedText)
                            .font(.body)
                            .foregroundStyle(transcriber.recognizedText.isEmpty ? .secondary : .primary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)

                Spacer()

                // Stop Recording Button
                HStack(spacing: 24) {
                    Button {
                        transcriber.cancelRecording()
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .font(.subheadline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }

                    Button {
                        Task {
                            await transcriber.stopRecording(machineHost: machineHost)
                            onFinish(transcriber.recognizedText)
                        }
                    } label: {
                        Label("Stop & Review", systemImage: "stop.fill")
                            .font(.headline)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Voice Input")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await transcriber.startRecording(machineHost: machineHost)
            }
            .onChange(of: transcriber.state) { _, newState in
                if case .recording(let level, _) = newState {
                    animationScale = 1.0 + CGFloat(level) * 0.4
                }
            }
        }
    }
}

struct TranscriptionCorrectionSheet: View {
    let initialText: String
    let agentKind: AgentCLIKind
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var editableText: String = ""

    private let commonKeywords = [
        "SwiftUI", "XcodeGen", "PWA", "IndexedDB", "TestFlight", "xcodebuild", "git status", "run tests"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review and correct transcription before sending to \(agentKind.rawValue):")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $editableText)
                        .font(.body)
                        .padding(10)
                        .frame(maxHeight: .infinity)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Quick keyword chips to insert
                VStack(alignment: .leading, spacing: 6) {
                    Text("Insert keywords:")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commonKeywords, id: \.self) { kw in
                                Button {
                                    editableText = editableText.isEmpty ? kw : "\(editableText) \(kw)"
                                } label: {
                                    Text(kw)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        onCancel()
                    } label: {
                        Text("Discard")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        let trimmed = editableText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSend(trimmed)
                    } label: {
                        Label("Send to Agent", systemImage: "arrow.up.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(agentKind.brandColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Transcription Review")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                editableText = initialText
            }
        }
    }
}

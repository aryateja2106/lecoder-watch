import SwiftUI
import UIKit

/// First-run setup. Three jobs: say what this app is, get `meshd` onto one machine,
/// and connect to it — before asking for any system permission.
struct OnboardingView: View {
    @EnvironmentObject var store: MeshStore
    // Launch arguments land in UserDefaults, so `simctl launch … -onboardingStep 2`
    // opens straight to a screen. Absent key reads 0 → .welcome, so this is inert in production.
    @State private var step: Step = Step(rawValue: UserDefaults.standard.integer(forKey: "onboardingStep")) ?? .welcome

    enum Step: Int, CaseIterable { case welcome, install, connect, notifications }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome:       WelcomeStep(next: { step = .install })
                case .install:       InstallStep(next: { step = .connect })
                case .connect:       ConnectStep(next: { step = .notifications })
                case .notifications: NotificationsStep(done: { store.completeOnboarding() })
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Always escapable — a setup flow you can't leave is a trap when
                    // the machine half of it lives in another room.
                    Button("Skip") { store.completeOnboarding() }
                        .font(.subheadline)
                }
            }
            .safeAreaInset(edge: .bottom) { StepDots(current: step) }
        }
    }
}

// MARK: - Chrome

private struct StepDots: View {
    let current: OnboardingView.Step

    var body: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingView.Step.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= current.rawValue ? Color.meshAccent : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.bottom, 10)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(OnboardingView.Step.allCases.count)")
    }
}

extension Color {
    /// Mint from the app icon, so the flow and the icon read as one product.
    static let meshAccent = Color(red: 0.37, green: 0.92, blue: 0.83)
}

private struct MeshGlyph: View {
    var size: CGFloat = 96

    var body: some View {
        Image(systemName: "point.3.filled.connected.trianglepath.dotted")
            .font(.system(size: size * 0.52, weight: .medium))
            .foregroundStyle(Color.meshAccent)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.11, blue: 0.29),
                                                  Color(red: 0.04, green: 0.06, blue: 0.13)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .accessibilityHidden(true)
    }
}

private struct StepScaffold<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).font(.body).foregroundStyle(.secondary)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            VStack(spacing: 10) { actions }
                .padding(.horizontal, 24)
                .padding(.top, 12)
        }
    }
}

// MARK: - 1. Welcome

private struct WelcomeStep: View {
    let next: () -> Void

    private let points: [(String, String, String)] = [
        ("terminal", "Every session, one list",
         "Claude Code, Codex and plain shells across all your machines."),
        ("bolt.horizontal", "Answer from your wrist",
         "Approve a prompt or send \"continue\" without opening your laptop."),
        ("bell.badge", "Know when you're the blocker",
         "Alerts when an agent needs input or a usage limit resets."),
    ]

    var body: some View {
        StepScaffold(title: "MeshWatch",
                     subtitle: "Your coding agents, on your wrist.") {
            VStack(alignment: .leading, spacing: 20) {
                MeshGlyph()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                ForEach(points, id: \.1) { icon, title, detail in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.headline)
                            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: icon)
                            .foregroundStyle(Color.meshAccent)
                            .font(.title3)
                            .frame(width: 28)
                    }
                }
            }
        } actions: {
            Button(action: next) {
                Text("Get started").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - 2. Install

private struct InstallStep: View {
    let next: () -> Void
    @State private var copied = false

    var body: some View {
        StepScaffold(title: "Set up a machine",
                     subtitle: "Run this on any Mac or Linux box you want to reach. It installs meshd, which is what this app talks to.") {
            VStack(alignment: .leading, spacing: 16) {
                CommandBlock(command: MeshInstall.command, copied: $copied)

                VStack(alignment: .leading, spacing: 10) {
                    Requirement(icon: "network", text: "Install Tailscale on the machine and this iPhone to reach it from anywhere. On the same Wi-Fi you can skip it.")
                    Requirement(icon: "terminal", text: "The installer sets up bun and tmux for you, then starts meshd on port 8899.")
                    Requirement(icon: "key.fill", text: "When it finishes it prints an address and a token. Keep that output — the next step reads it.")
                }
            }
        } actions: {
            Button(action: next) {
                Text("I've run it").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("I'll do this later", action: next)
                .font(.subheadline)
        }
    }
}

private struct Requirement: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text).font(.footnote).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.meshAccent).font(.footnote).frame(width: 20)
        }
    }
}

private struct CommandBlock: View {
    let command: String
    @Binding var copied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(command)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            Button {
                UIPasteboard.general.string = command
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy command", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - 3. Connect

private struct ConnectStep: View {
    @EnvironmentObject var store: MeshStore
    let next: () -> Void

    @State private var name = ""
    @State private var address = ""
    @State private var port = "8899"
    @State private var token = ""
    @State private var bridgeURL: String?
    @State private var probe: MeshStore.ProbeResult?
    @State private var testing = false
    @State private var pasteFailed = false

    private var canTest: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        StepScaffold(title: "Connect it",
                     subtitle: "Paste the installer's output and we'll pull out the address and token for you.") {
            VStack(alignment: .leading, spacing: 18) {
                Button {
                    paste()
                } label: {
                    Label("Paste installer output", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if pasteFailed {
                    Label("Couldn't find an address and token in what you pasted. Fill them in below.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                VStack(spacing: 12) {
                    Field(label: "Name", placeholder: "work-laptop", text: $name)
                    Field(label: "Address", placeholder: "100.94.221.115", text: $address)
                    Field(label: "Port", placeholder: "8899", text: $port, keyboard: .numberPad)
                    Field(label: "Token", placeholder: "from the installer", text: $token, secure: true)
                }

                if let probe { ProbeBadge(result: probe) }
            }
        } actions: {
            Button {
                Task { await test() }
            } label: {
                HStack {
                    if testing { ProgressView().controlSize(.small) }
                    Text(testing ? "Testing…" : "Test connection")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!canTest || testing)

            Button {
                save()
                next()
            } label: {
                Text("Add machine").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canTest)

            Button("Skip for now", action: next).font(.subheadline)
        }
    }

    private func paste() {
        guard let text = UIPasteboard.general.string else { pasteFailed = true; return }
        let summary = parseInstallSummary(text)
        if let ip = summary.ip { address = ip }
        if let token = summary.token { self.token = token }
        if let p = summary.port { port = String(p) }
        bridgeURL = summary.bridgeURL
        pasteFailed = !summary.isUsable
        probe = nil
    }

    private func candidate() -> Machine {
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        return Machine(host: trimmedName.isEmpty ? trimmedAddress : trimmedName,
                       ip: trimmedAddress,
                       port: Int(port) ?? 8899,
                       token: token.trimmingCharacters(in: .whitespaces),
                       bridgeURL: bridgeURL)
    }

    private func test() async {
        testing = true
        defer { testing = false }
        let result = await MeshStore.probe(candidate())
        probe = result
        // Name the machine after whatever meshd calls itself, if the user left it blank.
        if case .ok(let host, _) = result, name.trimmingCharacters(in: .whitespaces).isEmpty, let host {
            name = host
        }
    }

    private func save() {
        let machine = candidate()
        store.addMachine(host: machine.host,
                         ip: machine.ip,
                         port: machine.port,
                         token: machine.token,
                         bridgeURL: bridgeURL)
    }
}

private struct ProbeBadge: View {
    let result: MeshStore.ProbeResult

    var body: some View {
        switch result {
        case .ok(let host, let sessions):
            Label("Connected to \(host ?? "meshd") · \(sessions) session\(sessions == 1 ? "" : "s")",
                  systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.green)
        case .unauthorized:
            Label("Reached the machine, but the token was rejected. Copy it again from the installer output.",
                  systemImage: "key.slash")
                .font(.footnote).foregroundStyle(.orange)
        case .unreachable(let why):
            Label("Can't reach it: \(why). Check both devices are on Tailscale, or on the same Wi-Fi.",
                  systemImage: "wifi.slash")
                .font(.footnote).foregroundStyle(.red)
        }
    }
}

private struct Field: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure: Bool = false

    var body: some View {
        HStack {
            Text(label).font(.subheadline).frame(width: 76, alignment: .leading)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text).keyboardType(keyboard)
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 4. Notifications

private struct NotificationsStep: View {
    let done: () -> Void

    var body: some View {
        StepScaffold(title: "Stay in the loop",
                     subtitle: "The point of a watch app is that it taps you when an agent is stuck. That needs notification permission.") {
            VStack(alignment: .leading, spacing: 14) {
                Requirement(icon: "hand.raised.fill", text: "An agent is waiting on a yes/no and has stopped working.")
                Requirement(icon: "clock.arrow.circlepath", text: "A usage limit reset, so a paused session can continue.")
                Requirement(icon: "exclamationmark.triangle", text: "A machine dropped off the mesh.")
                Text("You can change this any time in iPhone Settings.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
            }
        } actions: {
            Button {
                NotificationManager.shared.requestAuthorization()
                done()
            } label: {
                Text("Enable notifications").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Not now", action: done).font(.subheadline)
        }
    }
}

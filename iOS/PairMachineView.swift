import SwiftUI

/// Onboarding. Two fields, because everything else is derivable: the machine's address
/// and a code it prints. The code buys the real token over `/pair/claim`, and the
/// machine hands over the rest of its fleet at the same time, so a person with four
/// boxes pairs once.
///
/// Deliberately not "type your 64-character bearer token into a phone keyboard", which
/// is what this replaced.
struct PairMachineView: View {
    @EnvironmentObject var store: MeshStore
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var port = "8899"
    @State private var code = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var added: [PairedHost] = []

    /// A scanned `meshwatch://pair` QR arrives with all three fields known. They land
    /// as editable prefills, not an automatic claim — reading the code before tapping
    /// Pair is the human check that the QR came from the machine on the desk.
    init(prefill: MeshStore.PairTarget? = nil) {
        guard let prefill else { return }
        _address = State(initialValue: prefill.address)
        _port = State(initialValue: String(prefill.port))
        _code = State(initialValue: prefill.code)
    }

    static let installCommand =
        "curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh"

    private var canPair: Bool {
        !busy
            && !address.trimmingCharacters(in: .whitespaces).isEmpty
            && normalizedPairingCode(code).count >= 6
    }

    /// The address as it will actually be dialled, port and all — the thing being
    /// waited on, so a wait that fails has already shown what was tried.
    private var contactLabel: String {
        let host = address.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return "that machine" }
        return "\(host):\(Int(port) ?? 8899)"
    }

    var body: some View {
        NavigationStack {
            Form {
                if added.isEmpty {
                    instructions
                    fields
                    if let failure {
                        Section {
                            Label(failure, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    success
                }
            }
            .navigationTitle(added.isEmpty ? "Pair a machine" : "Paired")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(added.isEmpty ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if added.isEmpty {
                        Button("Pair") { Task { await pair() } }
                            .disabled(!canPair)
                    }
                }
            }
            .disabled(busy)
            .overlay {
                if busy {
                    // Named, because a bare spinner over a disabled form is
                    // indistinguishable from a frozen app — and this particular wait
                    // can run the full 10s claim timeout when the address is wrong,
                    // which is exactly when someone needs to be told what is being
                    // tried so they can see the typo.
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Contacting \(contactLabel)…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: Steps

    private var instructions: some View {
        Section {
            StepRow(number: 1, title: "Install the agent on that machine") {
                Text("Skip if you already did. One command, macOS or Linux:")
                CopyableCommand(text: Self.installCommand)
            }
            StepRow(number: 2, title: "Ask it for a code") {
                CopyableCommand(text: "mesh pair")
                Text("It prints a QR code — scan it with the Camera app and this form fills itself. There's also an eight-character code, good for ten minutes. If the terminal says command not found, open a new terminal or run ~/.mesh/bin/mesh pair.")
            }
        } header: {
            Text("On the machine")
        }
    }

    private var fields: some View {
        Section {
            LabeledContent("Address") {
                TextField("100.x.y.z", text: $address.shellSafe)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            LabeledContent("Port") {
                TextField("8899", text: $port.shellSafe)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
            LabeledContent("Code") {
                TextField("XXXX-XXXX", text: $code.shellSafe)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .font(.body.monospaced())
            }
        } header: {
            Text("On this phone")
        } footer: {
            Text("The code is single-use. Case and the dash don't matter.")
        }
    }

    private var success: some View {
        Section {
            ForEach(added, id: \.ip) { host in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(host.host).font(.headline)
                        Text("\(host.ip):\(String(host.port))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(added.count == 1 ? "Added 1 machine" : "Added \(added.count) machines")
        } footer: {
            Text(added.count > 1
                 ? "The machine you paired knew about the others, so they came along with their own tokens."
                 : "Your watch picks this up the next time the app is open on your wrist.")
        }
    }

    // MARK: Action

    private func pair() async {
        busy = true
        failure = nil
        defer { busy = false }
        do {
            added = try await store.pair(
                address: address.trimmingCharacters(in: .whitespaces),
                port: Int(port) ?? 8899,
                code: code,
            )
        } catch {
            failure = Self.explain(error)
        }
    }

    /// Say which of the three things went wrong, because the fix differs: a stale code
    /// means run `mesh pair` again, a timeout means the address or the network, and a
    /// 401 means this daemon predates pairing and needs upgrading.
    static func explain(_ error: Error) -> String {
        switch error {
        case MeshClient.MeshError.http(403):
            return "That code was wrong, already used, or older than ten minutes. Run mesh pair again."
        case MeshClient.MeshError.http(401), MeshClient.MeshError.http(404):
            return "That machine's agent is too old to pair. Re-run the install command on it, then try again."
        case MeshClient.MeshError.http(let code):
            return "The machine answered with HTTP \(code)."
        case MeshClient.MeshError.badURL:
            return "That address doesn't look like an address."
        case MeshClient.MeshError.decode:
            return "The machine answered, but with nothing usable."
        default:
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorTimedOut {
                return "No answer from \(ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String ?? "that address"). Check the address, and that iOS hasn't blocked Local Network access."
            }
            return ns.localizedDescription
        }
    }
}

// MARK: - Pieces

private struct StepRow<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(String(number))
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.tint))
                Text(title).font(.headline)
            }
            content
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// A command you are meant to run somewhere else, so the only useful control is Copy.
struct CopyableCommand: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(text)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? .green : .accentColor)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy command \(text)")
    }
}

/// Shown instead of an empty list, because "no machines" is a step, not an error.
struct NoMachinesView: View {
    var pair: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No machines yet", systemImage: "server.rack")
        } description: {
            Text("Install the agent on a Mac or Linux box, run mesh pair on it, and enter the code here. Everything stays on your own network.")
        } actions: {
            Button("Pair a machine", action: pair)
                .buttonStyle(.borderedProminent)
        }
    }
}

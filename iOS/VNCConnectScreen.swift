import SwiftUI

/// Pre-connect surface for a machine's VNC. Binds a Vault VNC identity (password stays in
/// Keychain), then opens the noVNC viewer. Models RealVNC's retry-with-grace: the noVNC page is
/// a WKWebView we can't introspect for protocol-level auth failures, so "grace" is delivered as
/// affordances — pick another identity, reveal/copy the password to paste, and after a couple of
/// connect attempts a remediation panel — rather than a brittle auto-detect.
struct VNCConnectScreen: View {
    @EnvironmentObject var store: MeshStore
    let machine: Machine

    @State private var boundCredentialId: UUID?
    @State private var revealPassword = false
    @State private var attempts = 0
    @State private var showVNC = false

    init(machine: Machine) {
        self.machine = machine
        _boundCredentialId = State(initialValue: machine.vncCredentialId)
    }

    private var vncCredentials: [Credential] { store.credentials.filter { $0.kind == .vnc } }
    private var bound: Credential? { vncCredentials.first { $0.id == boundCredentialId } }
    private var snap: MachineSnapshot? { store.snapshot?.machines.first { $0.host == machine.host } }
    private var password: String? { bound.flatMap { KeychainVault.secret(forCredential: $0.id) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                facts
                identitySection
                if attempts >= 2 { remediation }
                connectButton
            }
            .padding()
        }
        .background(MW.base)
        .navigationTitle(machine.host)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showVNC) {
            RemoteWebScreen(title: machine.host, urlString: machine.resolvedVNC)
        }
        .preferredColorScheme(.dark)
    }

    private var facts: some View {
        GroupedInsetSection(header: "Connection") {
            KeyValueRow(label: "Machine", value: machine.host)
            KeyValueRow(label: "VNC", value: machine.resolvedVNC)
            if let snap {
                HStack {
                    Text("Status").foregroundStyle(MW.textPrimary)
                    Spacer()
                    StatusPill(status: snap.vncReachable == true ? .ok : (snap.reachable ? .needsInput : .offline),
                               text: snap.vncReachable == true ? "Reachable" : (snap.vncError ?? "Unknown"))
                }
                .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        GroupedInsetSection(header: "VNC identity",
                            footer: "Stored in Apple Keychain. Reveal to type it into the VNC prompt — it's never put on the canvas URL.") {
            Menu {
                Button("None") { bind(nil) }
                ForEach(vncCredentials) { c in
                    Button(c.name.isEmpty ? c.username : c.name) { bind(c.id) }
                }
            } label: {
                HStack {
                    Text("Identity").foregroundStyle(MW.textPrimary)
                    Spacer()
                    Text(bound.map { $0.name.isEmpty ? $0.username : $0.name } ?? "None")
                        .foregroundStyle(MW.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption).foregroundStyle(MW.textTertiary)
                }
                .frame(minHeight: 44)
            }

            if let bound {
                KeyValueRow(label: "Username", value: bound.username)
                HStack {
                    Text("Password").foregroundStyle(MW.textPrimary)
                    Spacer()
                    Text(revealPassword ? (password ?? "—") : "••••••••")
                        .font(.callout.monospaced())
                        .foregroundStyle(revealPassword ? MW.warn : MW.textSecondary)
                        .onLongPressGesture(minimumDuration: 0.15, pressing: { revealPassword = $0 }, perform: {})
                    Button {
                        if let password { copySecret(password) }
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .tint(MW.accent)
                        .accessibilityLabel("Copy password (auto-clears)")
                }
                .frame(minHeight: 44)
            } else if vncCredentials.isEmpty {
                Text("No VNC identities yet. Add one in Settings → Credential Vault.")
                    .font(.caption).foregroundStyle(MW.textTertiary)
            }
        }
    }

    private var remediation: some View {
        GroupedInsetSection(header: "Still not connecting?") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Check that Screen Sharing / VNC is enabled on \(machine.host).",
                      systemImage: "display.trianglebadge.exclamationmark")
                Label("Try a different VNC identity above, or re-enter the password in the VNC prompt.",
                      systemImage: "key.horizontal")
                Label("The password is correct in Keychain — re-type it exactly if the page rejects it.",
                      systemImage: "checkmark.shield")
            }
            .font(.caption)
            .foregroundStyle(MW.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var connectButton: some View {
        Button {
            attempts += 1
            showVNC = true
        } label: {
            Label(attempts == 0 ? "Connect" : "Reconnect", systemImage: "display")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(MW.accent)
    }

    private func bind(_ id: UUID?) {
        boundCredentialId = id
        var m = machine
        m.vncCredentialId = id
        store.update(m)
    }
}

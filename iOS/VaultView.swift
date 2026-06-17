import SwiftUI

/// A named SSH or VNC identity. Non-secret metadata only — the password/private key lives in the
/// Keychain (KeychainVault, keyed by `id`). Persisted via MeshStore.credentials.
struct Credential: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kind: Kind
    var username: String

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case ssh, vnc
        var id: String { rawValue }
        var label: String { self == .ssh ? "SSH" : "VNC" }
        var symbol: String { self == .ssh ? "terminal" : "display" }
    }
}

/// The Credential Vault: add / name / inspect SSH & VNC identities, all backed by the Keychain.
/// Reached from Settings. The VNC retry-with-grace flow binds one of these per machine.
struct VaultView: View {
    @EnvironmentObject var store: MeshStore
    @State private var showingAdd = false

    private var ssh: [Credential] { store.credentials.filter { $0.kind == .ssh } }
    private var vnc: [Credential] { store.credentials.filter { $0.kind == .vnc } }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if store.credentials.isEmpty {
                    emptyState
                } else {
                    section("SSH identities", ssh, kind: .ssh)
                    section("VNC identities", vnc, kind: .vnc)
                }
            }
            .padding()
        }
        .background(MW.base)
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add credential")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddCredentialSheet().environmentObject(store)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func section(_ title: String, _ creds: [Credential], kind: Credential.Kind) -> some View {
        if !creds.isEmpty {
            GroupedInsetSection(header: title, footer: kind == .ssh
                ? "Stored in Apple Keychain (Secure Enclave). Never leaves this device."
                : nil) {
                ForEach(creds) { cred in
                    CredentialRow(cred: cred)
                }
            }
            // Swipe-to-delete needs a List; here a long-press menu deletes (kept on one surface).
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.horizontal.fill")
                .font(.largeTitle)
                .foregroundStyle(MW.accent)
            Text("No saved identities")
                .font(.headline).foregroundStyle(MW.textPrimary)
            Text("Add an SSH key or VNC password once. It's stored in Apple Keychain and reused across your machines — you never retype it.")
                .font(.callout)
                .foregroundStyle(MW.textSecondary)
                .multilineTextAlignment(.center)
            Button { showingAdd = true } label: {
                Label("Add Identity", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(MW.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// One identity row: symbol · name · "user · ••••" with reveal-while-held, and a delete action.
private struct CredentialRow: View {
    let cred: Credential
    @EnvironmentObject var store: MeshStore
    @State private var revealed = false

    private var shownSecret: String {
        revealed ? (KeychainVault.secret(forCredential: cred.id) ?? "—") : "••••••••"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: cred.kind.symbol)
                .font(.title3).foregroundStyle(MW.accent)
                .frame(width: 34, height: 34)
                .background(MW.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(cred.name.isEmpty ? cred.username : cred.name)
                    .font(.headline).foregroundStyle(MW.textPrimary)
                Text("\(cred.username) · \(shownSecret)")
                    .font(.caption.monospaced())
                    .foregroundStyle(revealed ? MW.warn : MW.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: revealed ? "eye.fill" : "eye.slash")
                .font(.subheadline)
                .foregroundStyle(MW.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        // Hold to reveal; releases back to masked. No secret ever hits the pasteboard.
        .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in revealed = pressing }, perform: {})
        .accessibilityLabel("\(cred.kind.label) identity \(cred.name), user \(cred.username). Hold to reveal secret.")
        .contextMenu {
            Button(role: .destructive) {
                if let idx = store.credentials.firstIndex(where: { $0.id == cred.id }) {
                    store.deleteCredentials(at: IndexSet(integer: idx))
                }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

/// Create a named identity. Secret goes straight to Keychain on save; nothing plaintext persists.
private struct AddCredentialSheet: View {
    @EnvironmentObject var store: MeshStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: Credential.Kind = .ssh
    @State private var name = ""
    @State private var username = ""
    @State private var secret = ""

    private var canSave: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !secret.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Type", selection: $kind) {
                        ForEach(Credential.Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    GroupedInsetSection(footer: kind == .ssh
                        ? "The private key or password is written to Apple Keychain and reused for SSH."
                        : "The VNC password is written to Apple Keychain and pre-filled when you connect.") {
                        field("Name", text: $name, placeholder: "optional label")
                        field("Username", text: $username, placeholder: kind == .ssh ? "user" : "vnc user")
                        HStack {
                            Text(kind == .ssh ? "Key / Password" : "Password").foregroundStyle(MW.textPrimary)
                            Spacer()
                            SecureField("required", text: $secret)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(MW.textSecondary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .frame(minHeight: 44)
                    }
                }
                .padding()
            }
            .background(MW.base)
            .navigationTitle("Add Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(MW.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        store.addCredential(name: name, kind: kind, username: username, secret: secret)
                        dismiss()
                    } label: { StatusPill(status: .ok, style: .done) }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.4)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label).foregroundStyle(MW.textPrimary)
            Spacer()
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(MW.textSecondary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .frame(minHeight: 44)
    }
}

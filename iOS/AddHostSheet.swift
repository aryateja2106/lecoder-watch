import SwiftUI

/// Drives `.sheet(item:)` presentation; carries optional pre-fill from a discovered peer.
struct AddHostPrefill: Identifiable {
    let id = UUID()
    var name = ""
    var ip = ""
}

/// Add a machine to the mesh. Replaces the old broken inline Settings add (which appended an
/// empty-IP placeholder that never resolved). Presented from the Machines tab and pre-filled
/// from a tapped Tailnet peer.
///
/// ponytail: token is a plain field here; the Keychain Vault slice moves the secret out of the
/// Machine model and binds a named credential instead. Seam: swap `token` for a credential picker.
struct AddHostSheet: View {
    @EnvironmentObject var store: MeshStore
    @Environment(\.dismiss) private var dismiss

    // Pre-fill (e.g. from a discovered peer). Empty = blank form.
    var prefillName: String = ""
    var prefillIP: String = ""

    @State private var name = ""
    @State private var ip = ""
    @State private var port = "8899"
    @State private var token = ""
    @State private var bridgeURL = ""
    @State private var vncURL = ""
    @State private var showOptional = false
    @State private var errorText: String?
    @FocusState private var ipFocused: Bool

    private var canSave: Bool { !ip.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GroupedInsetSection(footer: "The Tailscale IP (100.x.y.z) or MagicDNS name of the machine running meshd.") {
                        labeledField("Name", text: $name, placeholder: "optional", autocap: false)
                        labeledField("IP / Host", text: $ip, placeholder: "100.x.y.z", autocap: false, focus: $ipFocused)
                    }

                    GroupedInsetSection(header: "Credential", footer: "Paste the token printed by install.sh. Stored on-device; the Vault will move this into Apple Keychain.") {
                        secureLabeledField("Token", text: $token)
                    }

                    DisclosureGroup(isExpanded: $showOptional) {
                        GroupedInsetSection {
                            labeledField("Port", text: $port, placeholder: "8899", keyboard: .numberPad)
                            labeledField("Bridge", text: $bridgeURL, placeholder: "http://ip:7820", autocap: false)
                            labeledField("VNC", text: $vncURL, placeholder: "http://ip:6080/vnc.html", autocap: false)
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Advanced")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MW.textSecondary)
                    }
                    .tint(MW.accent)
                    .padding(.horizontal, 4)

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(MW.warn)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding()
            }
            .background(MW.base)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(MW.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        StatusPill(status: .ok, style: .done)
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.4)
                }
            }
            .onAppear {
                name = prefillName
                ip = prefillIP
                if ip.isEmpty { ipFocused = true }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        do {
            try store.addHost(
                name: name, ip: ip, port: Int(port) ?? 8899, token: token,
                bridgeURL: bridgeURL.isEmpty ? nil : bridgeURL,
                vncURL: vncURL.isEmpty ? nil : vncURL
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: field builders

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, placeholder: String,
                              autocap: Bool = true, keyboard: UIKeyboardType = .default,
                              focus: FocusState<Bool>.Binding? = nil) -> some View {
        HStack {
            Text(label).foregroundStyle(MW.textPrimary)
            Spacer()
            let field = TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(MW.textSecondary)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(autocap ? .sentences : .never)
            if let focus { field.focused(focus) } else { field }
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func secureLabeledField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).foregroundStyle(MW.textPrimary)
            Spacer()
            SecureField("paste token", text: text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(MW.textSecondary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .frame(minHeight: 44)
    }
}

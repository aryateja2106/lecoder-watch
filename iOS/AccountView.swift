// AccountView.swift — create or sign in to the optional LeSearch AI feedback account.
import SwiftUI

extension Notification.Name {
    static let cloudSessionChanged = Notification.Name("cloud.session.changed")
}

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email.shellSafe)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                Text("Use at least 8 characters.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Create account") { Task { await submit(create: true) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
                Button("Sign in") { Task { await submit(create: false) } }
                    .disabled(working)
                if working { ProgressView() }
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit(create: Bool) async {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter your email address."
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        working = true
        errorMessage = nil
        do {
            if create {
                try await LeSearchCloud.signUp(email: email, password: password)
            } else {
                try await LeSearchCloud.signIn(email: email, password: password)
            }
            NotificationCenter.default.post(name: .cloudSessionChanged, object: nil)
            dismiss()
        } catch let error as CloudError {
            errorMessage = error.reason
        } catch {
            errorMessage = error.localizedDescription
        }
        working = false
    }
}

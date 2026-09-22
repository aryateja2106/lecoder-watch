// FeedbackView.swift — report a problem from the phone: kind, title, what happened in your words, an optional screenshot or recording you pick, an optional contact email, and a redacted bundle (app build, machines, daemon versions, recent events, the last error) you can read before it goes anywhere — sent to LeSearch AI, or shared / saved on a paired machine.
//
// Nothing is sent by itself: "Send to LeSearch AI" is one explicit tap, and what leaves
// the phone is listed in the footer above it. The bundle is built on the phone from the
// snapshot the app already holds, never from the Keychain, and event bodies pass through
// the same secret patterns the daemon's redactor uses before anything is written down.
// Sent reports land in Supabase (insert-only for this app) and become GitHub issues via
// scripts/feedback-to-issues.ts; the older paths — share (Mail, AirDrop, Files) or save
// under `~/.mesh/feedback/` on a machine — stay for people who want to read it first.
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FeedbackView: View {
    @EnvironmentObject var store: MeshStore
    @State private var kind = "bug"
    @State private var title = ""
    @State private var whatHappened = ""
    @State private var includeEvents = true
    @State private var includeMachines = true
    @State private var includeBundle = true
    @State private var contactEmail = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var attachment: Attachment?
    @State private var attachmentError: String?
    @State private var loadingAttachment = false
    @State private var sending = false
    @State private var sendResult: String?
    @State private var bundle: String?
    @State private var saveTarget: Machine?
    @State private var saveResult: String?

    private struct Attachment {
        let data: Data
        let ext: String
        let mime: String
        let name: String
    }

    private struct PickedImage: Transferable {
        let data: Data
        let name: String
        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .image) { file in
                try Self(data: Data(contentsOf: file.file), name: file.file.lastPathComponent)
            }
        }
    }

    private struct PickedMovie: Transferable {
        let data: Data
        let name: String
        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .movie) { file in
                try Self(data: Data(contentsOf: file.file), name: file.file.lastPathComponent)
            }
        }
    }

    var body: some View {
        Form {
            Section("What kind") {
                Picker("Kind", selection: $kind) {
                    Text("Bug").tag("bug")
                    Text("Idea").tag("idea")
                    Text("Other").tag("other")
                }
                .pickerStyle(.segmented)
            }
            Section {
                TextField("Title", text: $title.shellSafe)
                    .onChange(of: title) { _, value in
                        if value.count > 200 { title = String(value.prefix(200)) }
                    }
                TextField("What were you doing, and what did you expect?", text: $whatHappened.shellSafe, axis: .vertical)
                    .lineLimit(3...8)
                    .onChange(of: whatHappened) { _, value in
                        if value.count > 20_000 { whatHappened = String(value.prefix(20_000)) }
                    }
            } header: {
                Text("What happened")
            }
            Section {
                Toggle("Recent events (last 50, secrets removed)", isOn: $includeEvents)
                Toggle("Machines and daemon versions", isOn: $includeMachines)
                Toggle("Include the diagnostic bundle", isOn: $includeBundle)
                PhotosPicker(selection: $pickedItem, matching: .any(of: [.images, .videos])) {
                    Label("Screenshot or screen recording (optional)", systemImage: "paperclip")
                }
                if loadingAttachment { ProgressView("Loading attachment…") }
                if let attachment {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(attachment.name)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { pickedItem = nil; self.attachment = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove attachment")
                    }
                }
                if let attachmentError { Text(attachmentError).font(.caption).foregroundStyle(.red) }
                TextField("Contact email (optional)", text: $contactEmail.shellSafe)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Attach")
            } footer: {
                Text("What leaves this phone: your note, app version and build, device and iOS version, the optional contact email, the optional attachment you picked, and the redacted diagnostic bundle when enabled. Tokens, file contents and screen frames never leave the phone.")
            }
            Section("Send") {
                Button {
                    Task { await send() }
                } label: {
                    if sending { ProgressView() } else { Text("Send to LeSearch AI") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending || loadingAttachment)
                if let sendResult { Text(sendResult).font(.caption).foregroundStyle(sendResult.hasPrefix("Sent.") ? Color.secondary : Color.red) }
            }
            Section {
                Button("Build the report") { bundle = FeedbackBundle.make(store: store, note: whatHappened, events: includeEvents, machines: includeMachines) }
                    .disabled(whatHappened.trimmingCharacters(in: .whitespaces).isEmpty)
                if let bundle {
                    ScrollView(.horizontal) {
                        Text(bundle).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }
                    .frame(maxHeight: 260)
                    ShareLink(item: bundle, subject: Text("LeSearch AI feedback"), message: Text(whatHappened)) {
                        Label("Share the report", systemImage: "square.and.arrow.up")
                    }
                    ForEach(store.machines) { machine in
                        Button {
                            saveTarget = machine
                            Task { await save(on: machine, bundle) }
                        } label: {
                            Label("Save on \(machine.host) (~/.mesh/feedback)", systemImage: "externaldrive")
                        }
                        .disabled(saveTarget != nil)
                    }
                    if let saveResult { Text(saveResult).font(.caption).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Other ways to send")
            } footer: {
                Text("Read it first. If something in it should not leave your phone, edit the note and rebuild, or don't send.")
            }
        }
        .navigationTitle("Report a problem")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if contactEmail.isEmpty { contactEmail = LeSearchCloud.currentSession()?.email ?? "" }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await loadAttachment(item) }
        }
    }

    private func send() async {
        sending = true
        sendResult = nil
        let diagnostic = includeBundle
            ? FeedbackBundle.make(store: store, note: whatHappened, events: includeEvents, machines: includeMachines)
            : nil
        let report = FeedbackReport(
            kind: kind,
            title: title,
            body: whatHappened,
            contactEmail: contactEmail.isEmpty ? nil : contactEmail,
            bundle: diagnostic,
            attachment: attachment.map { ($0.data, $0.ext, $0.mime) }
        )
        do {
            let id = try await LeSearchCloud.sendFeedback(report)
            sendResult = "Sent. Reference \(id.uuidString.lowercased().prefix(8)). We file real reports as GitHub issues; the reference lets you find yours."
        } catch let error as CloudError {
            sendResult = error.reason
        } catch {
            sendResult = "Couldn't send the report. \(error.localizedDescription)"
        }
        sending = false
    }

    private func loadAttachment(_ item: PhotosPickerItem) async {
        loadingAttachment = true
        attachment = nil
        attachmentError = nil
        defer { loadingAttachment = false }
        do {
            let type = item.supportedContentTypes.first ?? .data
            let result: Attachment
            if type.conforms(to: .movie) {
                guard let picked = try await item.loadTransferable(type: PickedMovie.self) else {
                    throw CloudError(reason: "That video could not be read.")
                }
                let mp4 = type.conforms(to: .mpeg4Movie)
                result = Attachment(data: picked.data, ext: mp4 ? "mp4" : "mov",
                                    mime: mp4 ? "video/mp4" : "video/quicktime",
                                    name: picked.name)
            } else if type.conforms(to: .png) {
                guard let picked = try await item.loadTransferable(type: PickedImage.self) else {
                    throw CloudError(reason: "That image could not be read.")
                }
                result = Attachment(data: picked.data, ext: "png", mime: "image/png", name: picked.name)
            } else {
                guard let picked = try await item.loadTransferable(type: PickedImage.self) else {
                    throw CloudError(reason: "That image could not be read.")
                }
                if type.conforms(to: .jpeg) {
                    result = Attachment(data: picked.data, ext: "jpg", mime: "image/jpeg", name: picked.name)
                } else if let jpeg = UIImage(data: picked.data)?.jpegData(compressionQuality: 0.85) {
                    result = Attachment(data: jpeg, ext: "jpg", mime: "image/jpeg",
                                        name: (picked.name as NSString).deletingPathExtension + ".jpg")
                } else {
                    throw CloudError(reason: "That image format could not be converted to JPEG.")
                }
            }
            guard result.data.count <= 50 * 1_024 * 1_024 else {
                throw CloudError(reason: "That attachment is over 50 MB. Choose a smaller file.")
            }
            attachment = result
        } catch let error as CloudError {
            attachmentError = error.reason
            pickedItem = nil
        } catch {
            attachmentError = "That attachment could not be loaded. \(error.localizedDescription)"
            pickedItem = nil
        }
    }

    private func save(on machine: Machine, _ text: String) async {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        do {
            try await store.client(for: machine).fsWrite(path: "~/.mesh/feedback/\(stamp).md", text: text)
            saveResult = "Saved on \(machine.host): ~/.mesh/feedback/\(stamp).md"
        } catch let error as MeshClient.MeshError {
            saveResult = error.reason ?? "\(machine.host) refused the write."
        } catch {
            saveResult = "Couldn't reach \(machine.host)."
        }
        saveTarget = nil
    }
}

/// The report as Markdown: readable by a person in Mail and by an agent from a file.
@MainActor
enum FeedbackBundle {
    static func make(store: MeshStore, note: String, events: Bool, machines: Bool) -> String {
        var out = "# LeSearch AI — problem report\n\n"
        out += "- When: \(ISO8601DateFormatter().string(from: Date()))\n"
        out += "- App: \(BuildInfo.summary)\n"
        out += "- iOS: \(UIDevice.current.systemVersion) on \(UIDevice.current.model)\n"
        out += "- Live Activities: \(LiveActivityController.shared.activitiesEnabled ? "enabled" : "off")\(LiveActivityController.shared.lastRequestFailure.map { " · push token refused: \($0)" } ?? "")\n"
        if let error = store.lastError {
            out += "- Last error the app saw: \(redact(error.message)) (\(ISO8601DateFormatter().string(from: error.at)))\n"
        }
        out += "\n## What happened\n\n\(redact(note))\n"
        if machines, let snap = store.snapshot {
            out += "\n## Machines\n\n| host | reachable | meshd | capabilities | sessions |\n|---|---|---|---|---|\n"
            for m in snap.machines {
                out += "| \(m.host) | \(m.reachable) | \(m.meshdVersion ?? "?") | \(m.capabilities?.count ?? 0) | \(m.agents.map { "\($0.name) (\($0.agentType ?? "shell"), \($0.status ?? "?"))" }.joined(separator: ", ")) |\n"
            }
        }
        if events {
            out += "\n## Recent events (newest first)\n\n"
            for e in store.events.suffix(50).reversed() {
                out += "- \(e.createdISO) · \(e.level ?? "info") · \(e.title) · \(e.host ?? "?")/\(e.session ?? "?")\(e.replyable == false ? " · not replyable" : "")"
                if let body = e.body, !body.isEmpty { out += " — \(redact(String(body.prefix(160))))" }
                out += "\n"
            }
        }
        return out
    }

    /// The shapes secrets take in agent text; the same families `redact.ts` scrubs on the
    /// daemon. Anything that matches is replaced by its kind, never by a prefix of itself.
    private static let patterns: [(String, String)] = [
        (#"sk-[A-Za-z0-9_-]{16,}"#, "[api-key]"),
        (#"vck_[A-Za-z0-9]{16,}"#, "[api-key]"),
        (#"ghp_[A-Za-z0-9]{20,}"#, "[github-token]"),
        (#"xox[abp]-[A-Za-z0-9-]{10,}"#, "[slack-token]"),
        (#"AKIA[0-9A-Z]{16}"#, "[aws-key]"),
        (#"Bearer\s+[A-Za-z0-9._-]{16,}"#, "Bearer [token]"),
        (#"\b[a-f0-9]{64}\b"#, "[hex-token]"),
        (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, "[private-key]"),
    ]

    static func redact(_ text: String) -> String {
        var s = text
        for (pattern, label) in patterns {
            s = s.replacingOccurrences(of: pattern, with: label, options: .regularExpression)
        }
        return s
    }
}

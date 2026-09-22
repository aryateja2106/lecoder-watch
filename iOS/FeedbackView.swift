// FeedbackView.swift — report a problem from the phone: what happened in your words, plus a redacted bundle (app build, machines, daemon versions, recent events, the last error) you can read before it goes anywhere.
//
// Nothing is sent by itself. The bundle is built on the phone, shown in full, and then
// either shared (Mail, AirDrop, Files) or saved on a paired machine under
// `~/.mesh/feedback/` where an agent can read it next time you ask "what went wrong".
// Tokens never enter it: the bundle is assembled from the snapshot the app already holds,
// never from the Keychain, and event bodies pass through the same secret patterns the
// daemon's redactor uses before anything is written down.
import SwiftUI

struct FeedbackView: View {
    @EnvironmentObject var store: MeshStore
    @Environment(\.dismiss) private var dismiss
    @State private var whatHappened = ""
    @State private var includeEvents = true
    @State private var includeMachines = true
    @State private var bundle: String?
    @State private var saveTarget: Machine?
    @State private var saveResult: String?

    var body: some View {
        Form {
            Section {
                TextField("What were you doing, and what did you expect?", text: $whatHappened, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("What happened")
            }
            Section {
                Toggle("Recent events (last 50, secrets removed)", isOn: $includeEvents)
                Toggle("Machines and daemon versions", isOn: $includeMachines)
                Text("Always included: app build, iOS version, the last error the app saw. Never included: tokens, file contents, screen frames.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Attach")
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
                Text("Report")
            } footer: {
                Text("Read it first. If something in it should not leave your phone, edit the note and rebuild, or don't send.")
            }
        }
        .navigationTitle("Report a problem")
        .navigationBarTitleDisplayMode(.inline)
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

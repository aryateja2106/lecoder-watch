// ChatSearchView.swift — search every paired machine's stored Claude Code and Codex conversations (meshd "chatSearch") and resume one as a new session.
import SwiftUI

/// One hit and the machine that answered it. The daemon's own `host` field is its
/// hostname, which need not match the name this phone paired it under — routing a
/// resume by it would miss, so the row keeps the `Machine` that was asked.
private struct FoundChat: Identifiable {
    let machine: Machine
    let hit: ChatSearchHit
    var id: String { "\(machine.id)/\(hit.runtime)/\(hit.id)" }
}

/// Pushed from the Terminal tab's toolbar. Each machine answers for itself
/// (`federate=0`); the phone already reaches all of them, so it merges the answers.
struct ChatSearchView: View {
    @EnvironmentObject var store: MeshStore
    @State private var query = ""
    @State private var found: [FoundChat] = []
    /// The query `found` and `unanswered` belong to; `searching` = not every machine yet.
    @State private var searched = ""
    @State private var searching = false
    @State private var unanswered: [String] = []

    private var searchable: [Machine] {
        store.machines.filter { store.supports("chatSearch", host: $0.host) }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            if store.machines.isEmpty {
                ContentUnavailableView("No machines", systemImage: "desktopcomputer",
                                       description: Text("Pair a machine from the Machines tab first."))
            } else if searchable.isEmpty {
                Section {
                    ContentUnavailableView("No machine can search yet", systemImage: "text.magnifyingglass",
                                           description: Text("Conversation search needs a newer meshd. Run this on each machine, then pull to refresh the Terminal tab."))
                    CopyableCommand(text: DaemonCapabilities.upgradeCommand)
                }
            } else if trimmed.isEmpty {
                ContentUnavailableView("Search past conversations", systemImage: "text.magnifyingglass",
                                       description: Text("Finds words in the Claude Code and Codex chats kept on \(searchable.map(\.host).joined(separator: ", ")), and resumes one where it stopped."))
            } else if found.isEmpty && !searching && searched == trimmed {
                // "No results" only when someone actually searched; silence is not absence.
                if unanswered.count >= searchable.count {
                    ContentUnavailableView("No machine answered", systemImage: "wifi.exclamationmark",
                                           description: Text("Nothing was searched: \(unanswered.joined(separator: ", ")) did not reply in time."))
                } else {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
            ForEach(found) { item in
                NavigationLink {
                    ChatHitDetail(found: item)
                } label: {
                    ChatHitRow(found: item)
                }
            }
            if !unanswered.isEmpty && !trimmed.isEmpty {
                Text("No answer from \(unanswered.joined(separator: ", ")).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Search chats")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Words from a conversation")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar {
            if searching { ProgressView().controlSize(.small) }
        }
        // `.task(id:)` cancels the previous run on every keystroke, so the sleep is the
        // debounce and a slow machine's late answer can never overwrite a newer query.
        .task(id: trimmed) {
            let q = trimmed
            guard !q.isEmpty else { found = []; unanswered = []; searched = ""; searching = false; return }
            // Back from a hit's detail the task runs again; the list already holds this
            // query's whole answer, and clearing it would lose the scroll position too.
            guard q != searched || searching else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await search(q)
        }
    }

    /// Rows go up as each machine answers, so an asleep machine costs its own deadline
    /// and nobody else's — waiting for all of them blanked the list for up to 16 s.
    /// Every write sits behind the cancellation check on the main actor, and the query
    /// changing cancels this run, so an older query's late answer never lands.
    private func search(_ q: String) async {
        let clients = searchable.map { store.client(for: $0) }
        found = []
        unanswered = []
        searched = q
        searching = true
        await withTaskGroup(of: (Machine, [ChatSearchHit]?).self) { group in
            for client in clients {
                group.addTask { (client.machine, await searchWithDeadline(client, q)) }
            }
            for await (machine, answer) in group {
                guard !Task.isCancelled else { return }
                if let answer {
                    // bm25: lower is the better match, on every machine alike.
                    found = (found + answer.map { FoundChat(machine: machine, hit: $0) })
                        .sorted { ($0.hit.score ?? 0) < ($1.hit.score ?? 0) }
                } else {
                    unanswered = (unanswered + [machine.host]).sorted()
                }
            }
        }
        guard !Task.isCancelled else { return }
        searching = false
    }
}

/// One machine's hits, or nil when it failed or had not answered by `deadline`. Only
/// the search is timed: left alone, an asleep machine holds on for the full request
/// timeout on each of its addresses. Cancelling the loser also stops `requestFrame`
/// from moving on to the next address.
private func searchWithDeadline(_ client: MeshClient, _ q: String,
                                deadline: Duration = .seconds(4)) async -> [ChatSearchHit]? {
    await withTaskGroup(of: [ChatSearchHit]?.self) { race in
        race.addTask { try? await client.searchChats(q) }
        race.addTask { try? await Task.sleep(for: deadline); return nil }
        let first = await race.next() ?? nil
        race.cancelAll()
        return first
    }
}

private struct ChatHitRow: View {
    let found: FoundChat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chatTitle(found.hit))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Label(chatSubtitle(found), systemImage: runtimeSymbol(found.hit.runtime))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let first = found.hit.excerpts?.first {
                Text(markedExcerpt(first.text))
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ChatHitDetail: View {
    @EnvironmentObject var store: MeshStore
    let found: FoundChat

    @State private var busy = false
    @State private var failure: String?
    @State private var note: String?
    /// A session that started but not as the original was (another folder, a new
    /// conversation): it waits for a tap so `note` is read before it is covered.
    @State private var started: MeshStore.SessionTarget?

    private var hit: ChatSearchHit { found.hit }

    var body: some View {
        List {
            Section {
                LabeledContent("Machine", value: found.machine.host)
                LabeledContent("Agent", value: runtimeLabel(hit.runtime))
                if let cwd = hit.cwd, !cwd.isEmpty {
                    LabeledContent("Folder") {
                        Text(cwd).font(.caption.monospaced()).lineLimit(2).truncationMode(.head)
                    }
                }
                if let when = relative(hit.lastTs) {
                    LabeledContent("Last active", value: when)
                }
            }
            if let excerpts = hit.excerpts, !excerpts.isEmpty {
                Section("Matches") {
                    ForEach(Array(excerpts.enumerated()), id: \.offset) { _, excerpt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text([excerpt.role == "assistant" ? runtimeLabel(hit.runtime) : "You", relative(excerpt.ts)]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(markedExcerpt(excerpt.text))
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Section {
                Button {
                    // Set here, not inside the Task: a second tap before the Task runs
                    // would otherwise start a second resume.
                    guard !busy else { return }
                    busy = true
                    Task { await resume() }
                } label: {
                    if busy {
                        HStack(spacing: 6) { ProgressView(); Text("Resuming…") }
                    } else {
                        Label("Resume on \(found.machine.host)", systemImage: "play.fill")
                    }
                }
                .disabled(busy)
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if let started {
                    Button {
                        store.deepLinkSession = started
                    } label: {
                        Label("Open session", systemImage: "terminal")
                    }
                }
            } footer: {
                if !beforeNote.isEmpty { Text(beforeNote) }
            }
        }
        .navigationTitle(chatTitle(hit))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// What will differ from the original, said before the tap rather than after.
    private var beforeNote: String {
        var lines: [String] = []
        if hit.cwdExists == false { lines.append("Its folder no longer exists, so it will start in the home folder.") }
        if hit.live == false {
            lines.append(hit.runtime == "claude"
                ? "Claude Code no longer has this transcript; meshd restores it from its history as a new conversation."
                : "Codex no longer has this conversation file, so resuming it may fail.")
        }
        return lines.joined(separator: " ")
    }

    /// Plan on the machine, launch it through the same `/agents/new` as New Session,
    /// then open it the way a notification tap does (`deepLinkSession`) — straight
    /// away when it is the conversation as it was, after a tap on "Open session" when
    /// it is not.
    private func resume() async {
        failure = nil
        note = nil
        started = nil
        defer { busy = false }
        let client = store.client(for: found.machine)
        do {
            let plan = try await client.resumeChat(runtime: hit.runtime, id: hit.id)
            do {
                try await client.newSession(name: plan.name, cmd: plan.cmd, cwd: plan.cwd)
            } catch let error as MeshClient.MeshError where error.statusCode == 409 {
                // Already running under the same `resume-<id>` name — resumed before, or a
                // restored Claude transcript, whose new id is the same every time: open that.
            }
            Task { await store.refresh() }
            let target = MeshStore.SessionTarget(host: found.machine.host, session: plan.name)
            var said: [String] = []
            if plan.cwdMissing == true { said.append("Started in \(plan.cwd) — the recorded folder is gone.") }
            if plan.restoredFrom != nil { said.append("Restored from meshd's history as a new conversation.") }
            if said.isEmpty {
                store.deepLinkSession = target
            } else {
                note = said.joined(separator: " ")
                started = target
            }
        } catch {
            failure = (error as? MeshClient.MeshError)?.reason ?? error.localizedDescription
        }
    }
}

private func chatTitle(_ hit: ChatSearchHit) -> String {
    let title = hit.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return title.isEmpty ? "(untitled)" : title
}

private func chatSubtitle(_ found: FoundChat) -> String {
    [found.machine.host, runtimeLabel(found.hit.runtime), relative(found.hit.lastTs)]
        .compactMap { $0 }.joined(separator: " · ")
}

private func runtimeLabel(_ runtime: String) -> String {
    switch runtime {
    case "claude": return "Claude"
    case "codex": return "Codex"
    default: return runtime.capitalized
    }
}

private func runtimeSymbol(_ runtime: String) -> String {
    runtime == "codex" ? "chevron.left.forwardslash.chevron.right" : "sparkle"
}

private func relative(_ iso: String?) -> String? {
    parseISO(iso).map { $0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)) }
}

/// The daemon marks each match as «word»; show it bold and drop the markers. An
/// unclosed « (the excerpt was cut mid-match) is kept as plain text.
private func markedExcerpt(_ text: String) -> AttributedString {
    var out = AttributedString()
    for (i, chunk) in text.components(separatedBy: "«").enumerated() {
        guard i > 0, let end = chunk.firstIndex(of: "»") else {
            out += AttributedString(i > 0 ? "«" + chunk : chunk)
            continue
        }
        var match = AttributedString(String(chunk[..<end]))
        match.inlinePresentationIntent = .stronglyEmphasized
        out += match
        out += AttributedString(String(chunk[chunk.index(after: end)...]))
    }
    return out
}

import Foundation
import SafariServices
import SwiftUI

// MARK: - Remote file browser

/// Walk a machine's filesystem from the phone.
///
/// This exists for one reason: "new session in the right directory". Typing an absolute
/// path on a phone keyboard is the step where people give up, and the recents chips only
/// help for folders some pane already happens to be sitting in. `/fs` has shipped on
/// every deployed 0.4.x daemon, so this needs no capability gate and works against the
/// whole fleet.
///
/// It is deliberately read-only apart from `mkdir`: listing and creating a folder are
/// what choosing a working directory needs, and every additional verb here would be a
/// remote-file-manager's worth of failure modes for no extra reach.
struct FileBrowserView: View {
    let machine: Machine
    /// Capabilities the daemon advertised, so the client this view builds is gated the
    /// same way every other caller's is. Nothing here is gated today — `/fs` predates
    /// the capability list — but a client constructed without them silently disables
    /// every future gated call, which is a bug that only shows up much later.
    var capabilities: [String]? = nil
    /// Non-nil turns this into a picker: the chosen directory goes here and the view
    /// closes itself. Nil is the standalone browser, which offers "New session here"
    /// instead of "Use this folder".
    var onPick: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    /// nil = "wherever the daemon calls home" — the one path we can always ask for
    /// without knowing anything about the machine.
    @State private var path: String?
    @State private var listing: FsListing?
    @State private var failure: String?
    @State private var loading = false
    @State private var creatingFolder = false
    @State private var folderName = ""
    @State private var startingSession = false
    /// Type-to-filter text. Client-side only — the daemon has no query param, and a
    /// big listing is at most a few thousand rows, cheap to filter on every keystroke.
    @State private var query = ""
    /// Dotfiles/dotfolders are noise on every machine (`.git`, `.cache`, `node_modules`
    /// siblings like `.DS_Store`) and hidden by default; persisted so the choice
    /// survives leaving and reopening the browser. Keyed like `AppLock.enabledKey`.
    @AppStorage("mesh.fileBrowser.showHidden.v1") private var showHidden = false

    private var client: MeshClient { MeshClient(machine: machine, capabilities: capabilities) }
    private var isPicker: Bool { onPick != nil }
    /// What the daemon says we are looking at, which is the only path worth sending
    /// back: it has been resolved, so "~" and a trailing slash cannot come back to bite.
    private var currentPath: String? { listing?.path ?? path }
    private var rows: [FsEntry] { listing?.rows ?? [] }
    /// `rows` after the hidden-file and search filters (`filterFsEntries` in
    /// Shared/Models.swift). A computed property, not cached state — a directory
    /// listing tops out in the low thousands, so filtering on every render is
    /// cheaper than keeping it in sync by hand.
    private var visibleRows: [FsEntry] {
        filterFsEntries(rows, showHidden: showHidden, query: query)
    }
    /// How many rows the hidden-files filter is holding back right now (query included,
    /// so "matches exist but they are hidden" is answerable). Zero when showing hidden.
    private var hiddenCount: Int {
        guard !showHidden else { return 0 }
        return filterFsEntries(rows, showHidden: true, query: query).count - visibleRows.count
    }

    var body: some View {
        List {
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button { Task { await load() } } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                }
            }

            Section {
                if let parent = listing?.parent {
                    Button { go(to: parent) } label: {
                        Label("Up", systemImage: "arrow.turn.left.up")
                    }
                }
                ForEach(visibleRows) { entry in row(entry) }
                if visibleRows.isEmpty, !loading, failure == nil {
                    emptyStateLabel
                }
                // A folder showing 12 of 40 entries must say so, or the filter reads
                // as data loss. One tappable line, inside the listing where the missing
                // rows would have been — not a toggle buried below the whole list.
                if hiddenCount > 0, !loading {
                    Button { showHidden = true } label: {
                        Label(
                            hiddenCount == 1 ? "1 hidden item" : "\(hiddenCount) hidden items",
                            systemImage: "eye.slash"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                breadcrumb
            }

            Section {
                Toggle("Show hidden files", isOn: $showHidden)
            }

            Section {
                Button {
                    folderName = ""
                    creatingFolder = true
                } label: {
                    Label("New folder", systemImage: "folder.badge.plus")
                }
                .disabled(currentPath == nil)

                if isPicker {
                    Button {
                        if let currentPath { onPick?(currentPath) }
                        dismiss()
                    } label: {
                        Label("Use this folder", systemImage: "checkmark.circle")
                    }
                    .disabled(currentPath == nil)
                } else {
                    Button { startingSession = true } label: {
                        Label("New session here", systemImage: "plus.circle")
                    }
                    .disabled(currentPath == nil)
                }
            }
        }
        .navigationTitle(isPicker ? "Choose a folder" : "Files on \(machine.host)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPicker {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: {
                    Image(systemName: loading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .disabled(loading)
            }
        }
        // Default placement, not .navigationBarDrawer(displayMode: .always): on this
        // app's iOS 26 floor the automatic iPhone placement bottom-aligns the field
        // where a thumb can reach it one-handed, and does not reserve permanent space.
        .searchable(text: $query, prompt: "Filter by name")
        .task(id: path) { await load() }
        .alert("New folder", isPresented: $creatingFolder) {
            TextField("name", text: $folderName.shellSafe)
            Button("Cancel", role: .cancel) { }
            Button("Create") { Task { await makeFolder() } }
        } message: {
            Text("Created inside \(currentPath ?? "the home folder")")
        }
        .sheet(isPresented: $startingSession) {
            NewSessionSheet(machine: machine, initialCwd: currentPath)
        }
    }

    // MARK: Rows

    /// Distinguishes "nothing here" from "something here, but filtered out" — a bare
    /// "Empty folder" would be a lie if the folder holds only dotfiles or a search
    /// that missed, and would leave the hidden toggle looking like it did nothing.
    @ViewBuilder
    private var emptyStateLabel: some View {
        if rows.isEmpty {
            Text("Empty folder")
                .foregroundStyle(.secondary)
        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("No files match \u{201c}\(query)\u{201d}")
                .foregroundStyle(.secondary)
        } else {
            Text("Only hidden files here")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(_ entry: FsEntry) -> some View {
        if entry.isDirectory {
            Button { go(to: entry.path) } label: {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(entry.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            HStack {
                // meshd reports symlinks and never follows them, so a link is shown as
                // what it is rather than pretending to be a folder you can enter.
                Image(systemName: entry.isSymlink ? "link" : "doc")
                    .foregroundStyle(.secondary)
                Text(entry.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(fileSizeLabel(entry.size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Every ancestor of the current folder, tappable. On a phone this beats an "Up"
    /// button pressed six times to get out of a node_modules.
    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(crumbs) { crumb in
                    Button(crumb.name) { go(to: crumb.path) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .disabled(crumb.path == currentPath)
                    if crumb.path != crumbs.last?.path {
                        Text("/")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if crumbs.isEmpty {
                    Text(currentPath ?? "home")
                        .font(.caption)
                }
            }
        }
        .textCase(nil)
    }

    /// One ancestor of the current folder. A struct rather than a tuple because a
    /// `ForEach` id has to be a key path, and Swift has no key paths into tuples.
    private struct Crumb: Identifiable, Hashable {
        var id: String { path }
        let name: String
        let path: String
    }

    private var crumbs: [Crumb] {
        guard let current = currentPath, current.hasPrefix("/") else { return [] }
        var out = [Crumb(name: "/", path: "/")]
        var accumulated = ""
        for part in current.split(separator: "/") {
            accumulated += "/" + part
            out.append(Crumb(name: String(part), path: accumulated))
        }
        return out
    }

    // MARK: Actions

    private func go(to newPath: String) {
        failure = nil
        // A filter typed for one folder must not silently filter the next: navigation
        // is in-place (same view instance, .task(id: path) refetches), so the query
        // survives unless cleared here. Files.app clears on navigation; so do we.
        query = ""
        path = newPath
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let fetched = try await client.fsList(path: path)
            if fetched.ok {
                listing = fetched
                failure = nil
            } else {
                // {ok:false} with a 200 is the daemon saying "that path, no" — keep the
                // listing we can still see rather than blanking the screen.
                failure = fetched.error ?? "could not read that folder"
            }
        } catch {
            failure = "\(machine.host): \(error)"
        }
    }

    private func makeFolder() async {
        guard let base = currentPath else { return }
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let target = base.hasSuffix("/") ? base + name : base + "/" + name
        do {
            try await client.fsMkdir(path: target)
            await load()
        } catch {
            failure = "could not create \(name): \(error)"
        }
    }
}

/// "18 KB" / "1.2 MB". Sizes are context, not data, so the rough number is the point.
func fileSizeLabel(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

// MARK: - Links found in terminal output

/// Something to open, wrapped so a sheet can be driven by it. `URL` is not Identifiable
/// and giving it that conformance app-wide would be a surprise in every other file.
struct LinkTarget: Identifiable {
    let id = UUID()
    let url: URL
}

/// Every http(s) link in some terminal output, in order, de-duplicated.
///
/// Agents print URLs constantly — a dev server, a PR, an auth callback — and on a phone
/// the alternative is reading one out of a monospaced wall and retyping it. Only http
/// and https survive the filter: a terminal is untrusted text, and a scheme that can
/// launch another app on tap is not a link, it is an instruction from whatever the agent
/// happened to print.
func detectedLinks(in lines: [String], limit: Int = 6) -> [URL] {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return []
    }
    var seen = Set<String>()
    var found: [URL] = []
    for line in lines {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        detector.enumerateMatches(in: line, options: [], range: range) { match, _, stop in
            guard let url = match?.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  seen.insert(url.absoluteString).inserted else { return }
            found.append(url)
            if found.count >= limit { stop.pointee = true }
        }
        if found.count >= limit { break }
    }
    return found
}

/// In-app Safari. A link an agent printed opens here rather than punting to the browser
/// app, so "open it, read it, come back" does not lose the session you were watching.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) { }
}

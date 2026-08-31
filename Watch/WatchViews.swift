import SwiftUI
import WatchKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Voice input

/// One tap to the microphone.
///
/// This used to be a bare `TextFieldLink`, which does NOT open dictation — it opens the
/// system text-input sheet, which is a *picker* (scribble, keyboard, emoji, dictation),
/// and watchOS reopens whichever mode you used last. So a button labelled "Dictate"
/// reliably landed on Scribble instead: "even when we type dictate its still expecting
/// me to scribble or type".
///
/// `presentTextInputController(withSuggestions:allowedInputMode:)` is the only API that
/// goes straight to the mic, and it does so precisely when the suggestions array is nil.
/// The documented tell is in WatchKit's own header, on the sibling overload that takes a
/// language handler: "will never go straight to dictation because allows for switching
/// input language". This overload therefore does.
///
/// There is no better option: the watchOS SDK ships no Speech.framework at all (verified
/// against WatchOS26.5.sdk — no SFSpeechRecognizer at any deployment target), so this
/// system controller is the only speech recognition the watch can reach. Anything with
/// custom vocabulary has to stream audio to the Mac; see docs/VOICE-INPUT-SPEC.md.
///
/// Falls back to the old sheet if WatchKit hands us no controller at all, so the button
/// can never become dead — better a picker than nothing.
///
/// Spoken text APPENDS, so a second thought never wipes the first, and the TextField
/// beside this stays the editable preview: nothing dispatches until the user confirms.
struct DictateLink: View {
    @Binding var draft: String

    /// Set only after WatchKit has actually handed us nothing to present from. It is
    /// never read to *choose* the affordance up front — see `dictate()` — because that
    /// choice cannot be made correctly at render time.
    @State private var noController = false

    var body: some View {
        if noController {
            TextFieldLink(prompt: Text("Dictate")) {
                Label("Dictate", systemImage: "mic.fill")
            } onSubmit: { append($0) }
        } else {
            Button(action: dictate) {
                Label("Dictate", systemImage: "mic.fill")
            }
        }
    }

    /// Resolve the controller HERE, at tap time — not in `body`.
    ///
    /// `body` runs while the sheet holding this button is still being presented, and
    /// during that instant `visibleInterfaceController` is nil. Branching on it there
    /// froze the button into whichever answer happened to be true first: on a sheet it
    /// rendered the `TextFieldLink` — the system input *picker*, which reopens whatever
    /// mode you used last and so lands on Scribble — and it stayed that way for the
    /// life of the sheet however many times the real controller came back. The value
    /// that matters is the one under the finger, so it is read under the finger.
    ///
    /// `rootInterfaceController` is the fallback: the app always has a root even when
    /// nothing counts as "visible", and presenting from it reaches the same mic. Only
    /// when both are nil do we give up the mic and swap in the picker, with a haptic —
    /// a tap that produces neither speech nor a buzz reads as a broken button.
    private func dictate() {
        guard let controller = WKApplication.shared().visibleInterfaceController
                ?? WKApplication.shared().rootInterfaceController else {
            noController = true
            WKInterfaceDevice.current().play(.failure)
            return
        }
        controller.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
            guard let spoken = results?.first as? String else { return }   // nil == cancelled
            Task { @MainActor in append(spoken) }
        }
    }

    private func append(_ spoken: String) {
        let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = draft.isEmpty ? trimmed : draft + " " + trimmed
    }
}

// MARK: - Root

struct WatchRootView: View {
    @StateObject private var store = WatchMeshStore()

    var body: some View {
        // Single root NavigationStack (watchOS forbids nested wrapped nav).
        NavigationStack {
            MachinesListView()
                .environmentObject(store)
                .navigationTitle("Mesh")
        }
        .onAppear {
            store.start()
            // Approve / Decline / Reply / Stop from a notification take the same route
            // as the in-app buttons — including the pane the event named — so a failure
            // surfaces as `store.lastError` instead of disappearing silently.
            WatchNotifications.shared.onAgentAction = { [weak store] host, session, pane, text, key in
                store?.respondToAgent(host: host, session: session, pane: pane, text: text, key: key)
            }
            WatchNotifications.shared.requestAuthorizationOncePaired(hasMachines: !store.machines.isEmpty)
        }
        .onChange(of: store.machines.count) { _, count in
            // The watch learns its machines from the phone, seconds after launch — so
            // the moment it has one is the moment the ask makes sense.
            WatchNotifications.shared.requestAuthorizationOncePaired(hasMachines: count > 0)
        }
    }
}

// MARK: - Machines

struct MachinesListView: View {
    @EnvironmentObject var store: WatchMeshStore

    var body: some View {
        List {
            if store.hasNoMachines { noMachines }
            // Above even "Needs you": if the link is down, every row below is a memory
            // rather than a fact, and answering an agent from a stale row is the one
            // mistake this screen can make on your behalf. Silence here used to be the
            // only signal — you had to scroll to the Link section at the bottom and
            // read a debug line to find out.
            connectionBanner
            // The reason to look at your wrist. Above machines, above limits, above
            // everything — an agent that is blocked is the only thing here that is
            // costing you time right now.
            if !store.hasNoMachines, !store.needsAttention.isEmpty {
                Section {
                    ForEach(store.needsAttention, id: \.self) { item in
                        AttentionRow(item: item)
                    }
                } header: {
                    Label("Needs you", systemImage: "exclamationmark.bubble.fill")
                        .foregroundStyle(.orange)
                }
            } else if !store.hasNoMachines {
                // Say "nothing is waiting" out loud. Rendering nothing makes an all-clear
                // look exactly like a dead poll, and on a glance surface that ambiguity
                // is the whole failure — you cannot tell whether to trust the silence.
                Section {
                    Label("Nothing waiting on you", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let glance = limitsGlance {
                Section {
                    ForEach(glance, id: \.providerId) { row in
                        HStack {
                            Image(systemName: row.blocked ? "flame.fill" : "checkmark.circle")
                                .foregroundStyle(row.blocked ? .red : .green)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title).font(.caption)
                                Text(row.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                            // Resume the pinned session straight from the glance once the
                            // limit clears — the wrist action a mirrored notification tap can't do.
                            if let pin = store.pinnedLimitSessions.first(where: { $0.providerId.lowercased() == row.providerId.lowercased() }) {
                                Spacer()
                                // `.mini` drew a ~24pt tall control, well under the 44pt
                                // Apple asks for and roughly a fingertip's width short of
                                // usable — on a button that resumes a paid agent session.
                                Button("Continue") { store.sendToPinned(pin) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .frame(minHeight: WatchTouch.minHeight)
                                    .disabled(row.blocked)
                            }
                        }
                    }
                } header: {
                    Text("Limits")
                }
            }
            // Driving the Mac is the headline feature; it should not live four taps
            // deep under Sessions › Monitor.
            if !controllable.isEmpty {
                Section {
                    ForEach(controllable) { m in
                        NavigationLink {
                            RemoteView(machine: m).environmentObject(store)
                        } label: {
                            Label("Control \(shortName(m.host))", systemImage: "cursorarrow.motionlines")
                        }
                    }
                }
            }
            ForEach(store.snaps.activeFirst()) { m in
                NavigationLink {
                    SessionsView(host: m.host).environmentObject(store)
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(statusColor(m)).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shortName(m.host)).font(.headline)
                            if let auth = m.authError {
                                Text(auth).font(.caption2).foregroundStyle(.orange)
                            } else if let s = m.stats {
                                Text("CPU \(Int(s.cpuPct))% · \(Int(s.mem.pct))% mem · \(m.agents.count) sess · \(store.routeLabel(for: m.host))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else if m.reachable {
                                Text("\(m.agents.count) session\(m.agents.count == 1 ? "" : "s") · \(store.routeLabel(for: m.host))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text(store.routeLabel(for: m.host)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !store.hasNoMachines {
                NavigationLink {
                    UsageView().environmentObject(store)
                } label: {
                    Label("Usage", systemImage: "gauge.with.dots.needle.67percent")
                }
                NavigationLink {
                    EventsView().environmentObject(store)
                } label: {
                    Label("Events", systemImage: "bell")
                }
            }
            // The watch reaches the mesh through the phone, so when something is wrong
            // the first question is always "is the phone answering". Answer it in place
            // rather than making someone guess from an absence.
            Section {
                Text(store.linkStatusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Link")
            }
        }
        .overlay {
            // "Connecting…" forever is what an unpaired watch used to show, because an
            // empty list and an unanswered poll looked the same from here. The
            // no-machines case is a row now, not an overlay: as an overlay it was drawn
            // straight over the live Usage and Events rows and they showed through it.
            if !store.hasNoMachines && store.snaps.isEmpty {
                ProgressView("Connecting…")
            }
        }
        // ponytail: pull-to-refresh instead of a toolbar button — on watchOS a bare
        // .toolbar Button renders as a full-width top button that covered the first
        // machine and showed no managed spinner. .refreshable self-dismisses.
        .refreshable { await store.refresh() }
    }

    /// "Is what I am looking at still true?" — answered in place, at the top, whenever
    /// the answer is no. Nothing is drawn while the link is live: a permanent status
    /// band is wallpaper, and wallpaper is exactly what stops being read.
    @ViewBuilder
    private var connectionBanner: some View {
        switch store.connectionState {
        case .live, .waiting:
            // .waiting is a cold start; `noMachines` and the "Connecting…" overlay
            // already say so, and two of them saying it is noise.
            EmptyView()
        case .reconnecting:
            Section {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Reconnecting…").font(.caption.weight(.semibold))
                        Text("Showing the last snapshot.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        case .offline:
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Offline").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        Text("Out of touch with your iPhone. Everything below is old.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Why there is nothing here, and the one button that might change it.
    @ViewBuilder
    private var noMachines: some View {
        let reason = store.emptyStateReason
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(reason.title, systemImage: "iphone.gen3")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(reason.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Retry") { Task { await store.refresh() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(.vertical, 2)
        }
    }

    /// Machines whose meshd advertises input injection and answered this poll.
    private var controllable: [Machine] {
        store.machines.filter { machine in
            guard let snap = store.snaps.first(where: { $0.host == machine.host }) else { return false }
            return snap.reachable && snap.authError == nil && (snap.capabilities?.contains("input") ?? false)
        }
    }

    private struct LimitGlanceRow {
        var providerId: String
        var title: String
        var detail: String
        var blocked: Bool
    }

    private var limitsGlance: [LimitGlanceRow]? {
        guard let providers = store.effectiveUsage?.providers else { return nil }
        let rows = ["claude", "codex"].compactMap { id -> LimitGlanceRow? in
            guard let p = providers.first(where: { $0.id.lowercased() == id }),
                  let limit = p.limits.first(where: { LimitHelpers.isSessionLimit(label: $0.label) }) else { return nil }
            let blocked = LimitHelpers.isBlocked(limit)
            let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) ?? "—"
            let left = LimitHelpers.remainingPct(usedPct: limit.usedPct).map { "\($0)% left" } ?? "—"
            return LimitGlanceRow(providerId: id,
                                  title: "\(p.displayName) session",
                                  detail: blocked ? "Limit reached · \(countdown)" : "\(left) · \(countdown)",
                                  blocked: blocked)
        }
        return rows.isEmpty ? nil : rows
    }
}

/// One blocked agent, and the answer to it.
///
/// The previous version put the Continue button *inside* a `NavigationLink`'s label.
/// A ~24pt affirmative control nested in a full-row tap target, on a watch, wired to
/// press Return in a live shell: whichever of the two the system decided a given tap
/// belonged to, the user could not tell by looking. Now the actions are siblings of
/// the content and the row itself navigates nowhere — you reach the session through
/// the chevron, deliberately.
///
/// The question is also promoted from `.caption2`/`.secondary` to the visual payload
/// of the row. It was smaller and dimmer than the session name, which is the least
/// useful string here.
private struct AttentionRow: View {
    @EnvironmentObject var store: WatchMeshStore
    let item: LiveSessionPick
    @State private var answered = false
    /// This row's own copy of the failure, not the store's — `lastError` is
    /// mesh-wide, and three blocked agents all showing one machine's error is worse
    /// than none of them showing it.
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: item.state.symbol)
                    .font(.caption2)
                    .foregroundStyle(item.state.tint)
                Text(item.session).font(.caption.weight(.semibold)).lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
                Text(shortName(item.host)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if let since = item.blockedSince {
                    // Counts up on its own — no poll, and the number that says how
                    // long your Mac has been sitting there waiting for you.
                    Text(since, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !item.lastLine.isEmpty {
                Text(item.lastLine)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            }

            if item.risk.isDestructive, let why = item.risk.consequence {
                Label(why, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                // The affirmative control on the highest-stakes row in the app: it
                // presses Return in a live shell. It gets a full-height target, and
                // `respondToAgent` now reports what actually happened rather than
                // leaving "Sent" as an unbacked claim.
                Button(answered ? "Sent" : item.risk.verb) {
                    failure = nil
                    answered = true
                    store.respondToAgent(host: item.host, session: item.session,
                                         text: nil, key: "enter")
                }
                .buttonStyle(.borderedProminent)
                .tint(item.risk.isDestructive ? .red : .orange)
                .controlSize(.small)
                .disabled(answered)
                .frame(maxWidth: .infinity, minHeight: WatchTouch.minHeight)

                NavigationLink {
                    AgentLiveView(host: item.host, agent: item.session).environmentObject(store)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: WatchTouch.minWidth, height: WatchTouch.minHeight)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Open \(item.session)")
            }

            // Answering is the point of this row; the send failing is the other half of
            // that, and it used to go nowhere on this screen — the button said "Sent"
            // and the agent stayed blocked. Now the row un-answers itself so the tap
            // can be repeated, and says why it has to be.
            if let failure {
                Text(failure)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .onChange(of: store.lastError) { _, error in
            guard answered, let error else { return }
            failure = error
            answered = false
        }
    }
}

/// Fingertip minimums for the controls that sit inside list rows.
///
/// Apple asks for 44pt; a watch row cannot always give 44 in both directions without
/// eating the content it exists to show, so these are the floor the audit settled on —
/// wide enough that a chip is hit deliberately, tall enough that a thumb on a moving
/// wrist does not slide off it.
enum WatchTouch {
    static let minWidth: CGFloat = 42
    static let minHeight: CGFloat = 38
}

private func statusColor(_ snap: MachineSnapshot) -> Color {
    if snap.authError != nil { return .orange }
    return snap.reachable ? .green : .secondary
}

private func watchSessionSubtitle(_ agent: Agent, route: String) -> String {
    let kind = agent.isCmux ? "cmux" : "\(agent.windows) pane\(agent.windows == 1 ? "" : "s")"
    return "\(kind)\(agent.attached ? " · live" : "") · \(route)"
}

struct EventsView: View {
    @EnvironmentObject var store: WatchMeshStore

    var body: some View {
        List(store.events.reversed()) { event in
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline).lineLimit(2)
                if let body = event.body {
                    Text(body).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
                Text([event.host, event.source].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                // The agent printed a link and the wrist is where you read it. Pushing
                // it to the Mac's own browser is the only useful thing to do with it
                // from here — and the button only exists when that Mac can honour it.
                OpenOnMacButton(host: store.knownHost(for: event.host),
                                url: firstLink(in: [event.body, event.title]
                                    .compactMap { $0 }.joined(separator: "\n")))
            }
            .padding(.vertical, 1)
        }
        .navigationTitle("Events")
        .overlay { if store.events.isEmpty { Text("No events").foregroundStyle(.secondary) } }
    }
}

/// "Open on Mac", or nothing at all.
///
/// Renders itself away when there is no link, no known machine for it, or a daemon
/// without the `openUrl` capability — meshd gained `/open` in 0.5.0, and a button that
/// 404s against the 0.4.1 daemons still in the field would read as a network fault.
struct OpenOnMacButton: View {
    @EnvironmentObject var store: WatchMeshStore
    let host: String?
    let url: URL?
    @State private var confirming = false

    var body: some View {
        if let host, let url, store.canOpenOnMac(host: host) {
            Button {
                confirming = true
            } label: {
                // The link is scraped from whatever the agent printed, and this opens it
                // in the Mac's logged-in browser. Name the destination on the button —
                // "Open on Mac" alone asks the user to trust text they never saw. The
                // iPhone does the same thing at TerminalView's link row.
                Label("Open \(url.host ?? "link")", systemImage: "safari")
                    .font(.caption2)
                    .frame(minHeight: WatchTouch.minHeight)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint(url.absoluteString)
            .confirmationDialog("Open on \(host)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Open") { store.openOnMac(host: host, url: url) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(url.absoluteString)
            }
        }
    }
}

/// A session's state as a glyph AND a word.
///
/// Never colour alone: outdoors the tint is washed out, and for roughly one man in
/// twelve red and green are the same dot. The symbol and the label come from the same
/// shared vocabulary the phone, the Lock Screen card and the widgets use, so "Needs
/// you" means one thing everywhere.
struct SessionStateChip: View {
    let state: SessionDisplayState

    var body: some View {
        let bridged = state.sessionState
        HStack(spacing: 3) {
            Image(systemName: bridged.symbol).font(.caption2)
            Text(bridged.cardLabel).font(.caption2.weight(.medium))
        }
        .foregroundStyle(bridged.tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bridged.cardLabel)
    }
}

// MARK: - Sessions on a machine

private struct SessionRoute: Identifiable, Hashable {
    var host: String
    var agent: String
    var id: String { "\(host):\(agent)" }
}

struct SessionsView: View {
    @EnvironmentObject var store: WatchMeshStore
    let host: String

    @State private var taskAgent = "claude"
    @State private var taskText = ""
    @State private var showTask = false
    @State private var showCustom = false
    @State private var customCmd = ""
    @State private var customCwd = ""
    @State private var showHelp = false
    @State private var openAgent: SessionRoute?

    private var snap: MachineSnapshot? { store.snaps.first { $0.host == host } }

    var body: some View {
        List {
            Section("Sessions (\(snap?.agents.count ?? 0))") {
                ForEach(snap?.agents ?? []) { a in
                    NavigationLink {
                        AgentLiveView(host: host, agent: a.name).environmentObject(store)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: a.attached ? "dot.radiowaves.left.and.right" : "terminal")
                                .foregroundStyle(a.attached ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.displayName).lineLimit(1)
                                // What this session is DOING — the daemon's own verdict
                                // when it has one (meshd 0.5.0), derived from the newest
                                // event we hold otherwise. "attached" is a fact about a
                                // terminal multiplexer, not an answer to "is it stuck?".
                                SessionStateChip(state: store.displayState(of: a, host: host))
                                Text(watchSessionSubtitle(a, route: store.routeLabel(for: host)))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if (snap?.agents ?? []).isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snap?.authError != nil ? "Token needed" : "No sessions")
                        Text(emptySessionHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if snap?.authError != nil {
                Section("Fix") {
                    Text("Open LeSearch Mesh on your iPhone and copy the install command for this machine.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Then refresh the watch.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Monitor") {
                NavigationLink {
                    ScreenPeekView(host: host).environmentObject(store)
                } label: {
                    Label("Screen peek", systemImage: "display")
                }
                .disabled(snap?.reachable != true || snap?.authError != nil)
                if let machine = store.machines.first(where: { $0.host == host }), supportsInput {
                    NavigationLink {
                        RemoteView(machine: machine).environmentObject(store)
                    } label: {
                        Label("Control Mac", systemImage: "cursorarrow.motionlines")
                    }
                    .disabled(snap?.reachable != true || snap?.authError != nil)
                }
            }
            Section("New") {
                Button { openNewSession(cmd: nil) } label: {
                    Label("Shell", systemImage: "terminal")
                }
                Button { openNewSession(cmd: "claude") } label: {
                    Label("Claude", systemImage: "sparkles")
                }
                Button { openNewSession(cmd: "codex") } label: {
                    Label("Codex", systemImage: "curlybraces")
                }
                Button { taskAgent = "claude"; showTask = true } label: {
                    Label("Claude task", systemImage: "text.bubble")
                }
                Button { taskAgent = "codex"; showTask = true } label: {
                    Label("Codex task", systemImage: "text.badge.checkmark")
                }
                Button { taskAgent = "pi"; showTask = true } label: {
                    Label("Pi task", systemImage: "brain")
                }
                // The three buttons above cover three programs. Anything else the machine
                // can run — herdr, tmux, a REPL, a script — needed a shell session plus a
                // typed command, which nothing in the UI told you was possible.
                Button { showCustom = true } label: {
                    Label("Command…", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .disabled(snap?.reachable != true || snap?.authError != nil)
            if let s = snap?.stats {
                Section("Machine") {
                    Text(store.routeLabel(for: host))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    GaugeRow(label: "CPU", value: s.cpuPct, text: "\(Int(s.cpuPct))%")
                    GaugeRow(label: "Mem", value: s.mem.pct, text: "\(Int(s.mem.usedMB/1024))/\(Int(s.mem.totalMB/1024))G")
                    GaugeRow(label: "Disk", value: s.disk.pct, text: "\(Int(s.disk.usedGB))/\(Int(s.disk.totalGB))G")
                }
            }
        }
        .navigationTitle(shortName(host))
        .toolbar {
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("What is this?")
        }
        .navigationDestination(item: $openAgent) { route in
            AgentLiveView(host: route.host, agent: route.agent).environmentObject(store)
        }
        .sheet(isPresented: $showTask) { taskSheet }
        .sheet(isPresented: $showCustom) { customSheet }
        .sheet(isPresented: $showHelp) { helpSheet }
    }

    /// Launch any program the machine has, in any directory it is already working in.
    private var customSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Run a command")
                        .font(.headline)
                    // `git status` is not `Git status`. watchOS capitalises the first
                    // letter of every field by default and autocorrectionDisabled() does
                    // not touch that, so every command typed here arrived shifted and had
                    // to be un-shifted by hand — four extra taps on a 45mm screen.
                    TextField("herdr, tmux, python3…", text: $customCmd)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    DictateLink(draft: $customCmd)

                    let folders = store.workspaceSuggestions(host: host)
                    if !folders.isEmpty {
                        Text("Start in")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        // Tapping beats typing a path on a 45mm screen, and these are the
                        // directories this machine's panes are already sitting in.
                        ForEach(folders, id: \.self) { path in
                            Button {
                                customCwd = (customCwd == path) ? "" : path
                            } label: {
                                HStack {
                                    Image(systemName: customCwd == path ? "checkmark.circle.fill" : "folder")
                                    Text(lastPathBit(path)).lineLimit(1)
                                }
                            }
                            .accessibilityLabel("Start in \(path)")
                        }
                    }

                    Button("Start") {
                        let cmd = customCmd.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cmd.isEmpty else { return }
                        let name = store.newSession(host: host, cmd: cmd,
                                                    cwd: customCwd.isEmpty ? nil : customCwd)
                        showCustom = false
                        customCmd = ""
                        openAgent = SessionRoute(host: host, agent: name)
                    }
                    .disabled(customCmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// The "?" the owner said was missing. Plain words, no jargon, no scrolling hunt.
    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    helpLine("Sessions", "Programs left running on this machine. They keep running when the watch sleeps — reopen one and you are back where you were.")
                    helpLine("Shell / Claude / Codex", "Start a new session running that program.")
                    helpLine("Command…", "Start a new session running anything else — herdr, tmux, python3 — optionally in a folder you are already working in.")
                    helpLine("Open terminal", "The full screen of a session, with the key bar. Turn the Digital Crown to scroll back.")
                    helpLine("Reader / Raw", "The first chip in the key bar. Reader wraps every line to the screen — best for questions, prose and errors. Raw keeps the Mac's own line breaks and lets you drag sideways — best for diffs and tables.")
                    helpLine("Reply", "Type or dictate text, then send it. Nothing is sent until you tap Send.")
                    helpLine("Insert iPhone clipboard", "Types whatever is on your iPhone's clipboard into the session, so a URL or a key never has to be scribbled. Your iPhone must be open on LeSearch Mesh at the time.")
                    helpLine("Open on Mac", "Appears when an agent has printed a link. Opens it in the Mac's own browser.")
                    helpLine("Key bar", "Enter, arrows, Tab, Escape, Page up/down, Home, End, Backspace and Ctrl-D — enough to drive a full-screen program. Text size lives under the … chip at the end.")
                    helpLine("Interrupt", "Ctrl-C, to stop whatever is running.")
                    helpLine("Screen peek", "A still picture of the Mac's screen, with a Refresh button. To zoom into it, open Control Mac and tap the expand chip — that is the screen you can move around.")
                    helpLine("Control Mac", "Move the pointer and click, like a trackpad. The expand chip on the preview opens Inspect: the screen full size, Crown to move down the page, tap the sides to move across, tap the middle to come back.")
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("What is this?")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func helpLine(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).bold()
            Text(body).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// meshd advertises "input" only on macOS hosts that ship the injector.
    private var supportsInput: Bool { snap?.capabilities?.contains("input") ?? false }

    private var emptySessionHint: String {
        if snap?.authError != nil { return "Open LeSearch Mesh on your iPhone, fix the token, then refresh." }
        if snap?.reachable == true { return "Start Shell, Claude, or Codex below." }
        return "Open LeSearch Mesh on your iPhone, or refresh when the Mac is nearby."
    }

    private func openNewSession(cmd: String?, initialText: String? = nil) {
        let name = store.newSession(host: host, cmd: cmd, initialText: initialText)
        openAgent = SessionRoute(host: host, agent: name)
    }

    private var taskSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("\(taskAgent.capitalized) task")
                    .font(.headline)
                // Same shift-key tax as the command field: this text is pasted straight
                // into an agent prompt where paths and flags are case-sensitive.
                TextField("Build/fix/check…", text: $taskText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                DictateLink(draft: $taskText)
                Button("Start") {
                    if let name = store.newTask(host: host, agent: taskAgent, task: taskText) {
                        openAgent = SessionRoute(host: host, agent: name)
                    }
                    taskText = ""
                    showTask = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showTask = false } } }
        }
    }
}

// MARK: - Live agent view (see + respond)

/// Keeps `following` true only while the last line is actually on screen.
///
/// The terminal auto-scrolls to the tail on every poll, which is right when you are
/// watching an agent work and exactly wrong when you have scrolled back to read
/// something: at a 1.5s poll the view was yanked to the bottom before a sentence could
/// be finished. Rather than tracking drag gestures by hand, this reads the scroll
/// view's own geometry — the reader "unfollows" by scrolling up and "refollows" by
/// scrolling back down, with no button to discover and no mode to get stuck in.
///
/// `onScrollGeometryChange` is watchOS 11; the app targets 10. On a watchOS 10 device
/// the modifier is simply absent and `following` stays true — that is today's
/// always-follow behaviour, not a broken one.
private struct FollowsTail: ViewModifier {
    @Binding var following: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(watchOS 11.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geo in
                // 24pt of slack ≈ one 13pt monospaced line plus the 4pt bottom padding,
                // so "the newest line is visible" counts as being at the bottom.
                geo.visibleRect.maxY >= geo.contentSize.height - 24
            } action: { _, atBottom in
                if following != atBottom { following = atBottom }
            }
        } else {
            content
        }
    }
}

struct AgentLiveView: View {
    @EnvironmentObject var store: WatchMeshStore
    @Environment(\.dismiss) private var dismiss
    let host: String
    let agent: String

    @State private var reply = ""
    @State private var showReply = false
    @State private var showMore = false
    @State private var confirmInterrupt = false
    @State private var fontSize: CGFloat = 13
    @State private var selectedPane: String?
    /// Whether new output should yank the view to the bottom. False the moment the
    /// reader scrolls up, true again when they land back on the last line — see
    /// `FollowsTail`. Reset on every open so a fresh terminal always starts at "now".
    @State private var followTail = true

    private var currentAgent: Agent? {
        store.snaps.first { $0.host == host }?.agents.first { $0.name == agent }
    }

    private var panes: [Pane] {
        currentAgent?.panes ?? []
    }

    private var currentPane: Pane? {
        panes.first { $0.paneId == selectedPane }
            ?? panes.first { $0.active }
            ?? panes.first
    }

    private var meaningfulLines: [String] {
        store.output.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // Terminal display source: keep interior blank lines so TUI output stays aligned;
    // trim only the empty lines at the top/bottom of the window.
    private var terminalLines: [String] {
        var lines = store.output
        while let f = lines.first, f.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.removeFirst() }
        while let l = lines.last, l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.removeLast() }
        return lines
    }

    private var previewLines: [String] {
        Array(terminalLines.suffix(8))
    }

    private var statusText: String {
        if store.sending { return "sending…" }
        if let providerId = LimitHelpers.providerId(for: currentAgent?.agentType),
           store.isProviderBlocked(providerId) {
            if let limit = sessionLimit(for: providerId),
               let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) {
                return "Limit reached · \(countdown)"
            }
            return "Limit reached · wait for reset"
        }
        if meaningfulLines.isEmpty { return "waiting for output" }
        return "\(sessionState(lines: meaningfulLines, attached: currentAgent?.attached ?? false).label) · \(meaningfulLines.count) lines"
    }

    private var continueBlocked: Bool {
        guard let providerId = LimitHelpers.providerId(for: currentAgent?.agentType) else { return false }
        return store.isProviderBlocked(providerId)
    }

    private func sessionLimit(for providerId: String) -> UsageLimit? {
        store.effectiveUsage?.providers
            .first { $0.id.lowercased() == providerId.lowercased() }?
            .limits.first { $0.label.lowercased().contains("session") }
    }

    var body: some View {
        List {
            if continueBlocked, let providerId = LimitHelpers.providerId(for: currentAgent?.agentType),
               let limit = sessionLimit(for: providerId) {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Session limit reached", systemImage: "flame.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        if let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) {
                            Text(countdown).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Continue is disabled until the limit resets.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Monitor") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(store.sending ? .orange : .green).frame(width: 8, height: 8)
                        Text("\(shortName(host)) · \(store.routeLabel(for: host))").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(currentAgent?.displayName ?? agent)
                        .font(.headline)
                        .lineLimit(1)
                    if let agent = currentAgent {
                        SessionStateChip(state: store.displayState(of: agent, host: host))
                    }
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let pane = currentPane {
                        Text(pane.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let error = store.lastError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Actions") {
                Button { store.send(text: "continue\n") } label: {
                    Label("Continue", systemImage: "play.fill")
                        .frame(minHeight: WatchTouch.minHeight)
                }
                .buttonStyle(.borderedProminent)
                .disabled(continueBlocked)
                Button { store.send(key: "enter") } label: {
                    Label("Enter", systemImage: "return")
                        .frame(minHeight: WatchTouch.minHeight)
                }
                .buttonStyle(.bordered)
                Button { showReply = true } label: {
                    Label("Reply", systemImage: "square.and.pencil")
                        .frame(minHeight: WatchTouch.minHeight)
                }
                .buttonStyle(.bordered)
                // The one thing a wrist cannot produce for itself: a URL, a stack
                // trace, a key. It is nearly always already on the phone in your
                // pocket, so fetch it from there rather than asking anyone to scribble
                // it. Inserted without a newline — you read it before you send it.
                Button { Task { await store.insertPhoneClipboard() } } label: {
                    Label("Insert iPhone clipboard", systemImage: "doc.on.clipboard")
                        .frame(minHeight: WatchTouch.minHeight)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Types whatever is on your iPhone's clipboard into this session")
                OpenOnMacButton(host: host, url: visibleLink)
                Button(role: .destructive) { confirmInterrupt = true } label: {
                    Label("Interrupt", systemImage: "xmark.octagon")
                        .frame(minHeight: WatchTouch.minHeight)
                }
                .buttonStyle(.bordered)
            }

            if !panes.isEmpty {
                Section("pane") {
                    ForEach(panes) { pane in
                        Button {
                            selectedPane = pane.paneId
                            store.watch(host: host, agent: agent, pane: pane.paneId)
                        } label: {
                            HStack {
                                Image(systemName: pane.paneId == currentPane?.paneId ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(pane.label).lineLimit(1)
                                    if let path = pane.currentPath, !path.isEmpty {
                                        Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section("Output") {
                if previewLines.isEmpty {
                    Text("No output yet. Use Reply only when you want the keyboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(previewLines.joined(separator: "\n"))
                        .font(.system(size: fontSize, design: .monospaced))
                        .lineLimit(10)
                        .focusable(false)
                }
                Button { showMore = true } label: {
                    Label("Open terminal", systemImage: "terminal")
                }
                .accessibilityHint("Full-screen, scrollable output with a key bar")
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Interrupt agent?", isPresented: $confirmInterrupt, titleVisibility: .visible) {
            Button("Send Ctrl-C", role: .destructive) { store.send(key: "ctrl-c") }
            Button("Kill session", role: .destructive) { store.killSession(host: host, agent: agent); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ctrl-C stops the current turn; Kill ends the whole session on \(currentAgent?.displayName ?? agent).")
        }
        .onAppear { selectDefaultPaneAndWatch() }
        .onChange(of: panes) { _, _ in
            if selectedPane == nil {
                selectDefaultPaneAndWatch()
            }
        }
        .onDisappear { store.stopWatching() }
        .sheet(isPresented: $showReply) { replySheet }
        .sheet(isPresented: $showMore) { terminalScreen }
    }

    private func selectDefaultPaneAndWatch() {
        if selectedPane == nil {
            selectedPane = currentPane?.paneId
        }
        store.watch(host: host, agent: agent, pane: selectedPane)
    }

    private var replySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Send to \(currentAgent?.displayName ?? agent)")
                        .font(.headline)
                        .lineLimit(1)
                    // Same shift-key tax as the command field, and this text lands on an
                    // agent's prompt line where `--no-verify` is not `--No-verify`.
                    // `axis: .vertical` because a reply is often two thoughts, and a
                    // single-line field showed only the tail of what you had dictated.
                    TextField("Say, scribble, or type…", text: $reply, axis: .vertical)
                        .lineLimit(1...4)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack(spacing: 6) {
                        DictateLink(draft: $reply)
                        // The only way to get a line break into the draft: watchOS
                        // dictation and scribble both end the field instead of inserting
                        // one, so a multi-line message was unreachable from the wrist.
                        Button { reply += "\n" } label: {
                            Image(systemName: "arrow.turn.down.left")
                        }
                        .accessibilityLabel("Add a line break, do not send")
                    }
                    // Send leaves the text sitting on the agent's input line — that is
                    // what you want when the next thing you press is a key-bar chip, or
                    // when the TUI is going to ask you to confirm. Send ⏎ submits it.
                    // Shape copied from the phone-control Type / Type ⏎ pair.
                    HStack(spacing: 6) {
                        Button("Send") { sendReply(withReturn: false) }
                            .buttonStyle(.bordered)
                        Button("Send ⏎") { sendReply(withReturn: true) }
                            .buttonStyle(.borderedProminent)
                    }
                    .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showReply = false } } }
        }
    }

    private func sendReply(withReturn: Bool) {
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.send(text: withReturn ? reply + "\n" : reply)
        reply = ""
        showReply = false
    }

    // A genuine terminal on the wrist: full-bleed monospaced output that the Digital
    // Crown scrolls and that auto-follows the newest line, with an always-present,
    // horizontally-scrollable key bar (matching the phone accessory bar). Every icon
    // control carries a VoiceOver label.
    private var terminalScreen: some View {
        NavigationStack {
            Group {
                if store.readerOutput { readerTerminal } else { rawTerminal }
            }
            .navigationTitle(currentAgent?.displayName ?? agent)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { terminalKeyBar }
        }
    }

    /// Reader: every line wrapped to the screen, nothing off to the right.
    ///
    /// This is the readable view and therefore the default — a watch is about 21
    /// monospaced columns wide, and prose that runs off the edge is prose you cannot
    /// read at all. When the daemon advertises "captureJoin" the store also asks it to
    /// un-wrap the physical lines tmux stored and strip the box-drawing and spinner
    /// glyphs, so what wraps here is a sentence rather than the ruins of a table.
    private var readerTerminal: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(terminalLines.isEmpty ? "waiting for output…" : terminalLines.joined(separator: "\n"))
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(terminalLines.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Terminal output, \(terminalLines.count) lines")
                    Color.clear.frame(height: 1).id("tail")
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
            .background(Color.black)
            .modifier(FollowsTail(following: $followTail))
            .onAppear { followTail = true; proxy.scrollTo("tail", anchor: .bottom) }
            .onChange(of: store.output) { _, _ in
                // Only while the reader is still at the bottom. This fired on every
                // 1.5s poll before, so scrolling back to read the error that scrolled
                // past was snatched away within a second-and-a-half, every time.
                guard followTail else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("tail", anchor: .bottom) }
            }
        }
    }

    /// Raw: the Mac's own line breaks, kept.
    ///
    /// Wrapping is exactly wrong for the other half of terminal output — a diff, a
    /// table, `git status`, a stack trace with aligned columns — where re-flowing to 21
    /// characters destroys the only structure the text had. So Raw refuses to wrap
    /// (`fixedSize` lets the text take whatever width it needs) and lets you pan
    /// instead: drag sideways to move across a long line, Crown up and down as usual.
    private var rawTerminal: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(terminalLines.isEmpty ? "waiting for output…" : terminalLines.joined(separator: "\n"))
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(terminalLines.isEmpty ? .secondary : .primary)
                        // The whole point of Raw: never re-flow, however far right it runs.
                        .fixedSize(horizontal: true, vertical: true)
                        .accessibilityLabel("Terminal output, unwrapped, \(terminalLines.count) lines")
                    Color.clear.frame(width: 1, height: 1).id("tail")
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
            .background(Color.black)
            .modifier(FollowsTail(following: $followTail))
            .onAppear { followTail = true; proxy.scrollTo("tail", anchor: .bottomLeading) }
            .onChange(of: store.output) { _, _ in
                guard followTail else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("tail", anchor: .bottomLeading) }
            }
        }
    }

    /// Every key meshd will accept, in the order a hand reaches for them.
    ///
    /// This used to stop after Down — six keys — while the daemon has always accepted
    /// fourteen and the phone already sent thirteen. The eight that were missing are
    /// exactly the ones an interactive TUI needs: left/right to move within a line or
    /// between panes, home/end and the page keys to move through history, ctrl-d to end
    /// a REPL, backspace to fix a typo without retyping the line. Without them a real
    /// program like herdr could be launched from the wrist but never driven, which is
    /// why the terminal read as "clean but unusable".
    ///
    /// The chips are 42×38 with 8pt between them. They were 28×28 at 6pt, which on a
    /// 40mm watch put Escape and Up close enough together that a thumb could not
    /// separate them — and every one of these sends a real keystroke to a real shell.
    /// Fewer chips fit per screen, so the two text-size chips moved to the overflow
    /// page: font size is set once, while Enter is pressed all day.
    private var terminalKeyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // First, because which view you are in changes what everything else
                // looks like — and it is the fix for "I cannot read this".
                keyChip(store.readerOutput ? "Raw view, do not wrap lines" : "Reader view, wrap lines",
                        store.readerOutput ? "arrow.left.and.right" : "text.alignleft") {
                    store.readerOutput.toggle()
                }
                keyChip("Reply", "text.bubble") { showReply = true }
                keyChip("Enter", "return") { store.send(key: "enter") }
                keyChip("Interrupt", "xmark.octagon", role: .destructive) { store.send(key: "ctrl-c") }
                keyChip("Tab", "arrow.right.to.line") { store.send(key: "tab") }
                keyChip("Escape", "escape") { store.send(key: "escape") }
                keyChip("Up", "arrow.up") { store.send(key: "up") }
                keyChip("Down", "arrow.down") { store.send(key: "down") }
                keyChip("Left", "arrow.left") { store.send(key: "left") }
                keyChip("Right", "arrow.right") { store.send(key: "right") }
                keyChip("Backspace", "delete.left") { store.send(key: "backspace") }
                keyChip("Page up", "arrow.up.to.line") { store.send(key: "page-up") }
                keyChip("Page down", "arrow.down.to.line") { store.send(key: "page-down") }
                keyChip("Home", "arrow.up.to.line.compact") { store.send(key: "home") }
                keyChip("End", "arrow.down.to.line.compact") { store.send(key: "end") }
                keyChip("End of input, control D", "control") { store.send(key: "ctrl-d") }
                // A push rather than a sheet: this bar already lives inside a presented
                // sheet, and watchOS does not present a second one over it reliably.
                NavigationLink {
                    terminalOptions
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: WatchTouch.minWidth, height: WatchTouch.minHeight)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Text size and view options")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(.ultraThinMaterial)
    }

    /// The settings that are chosen once and then left alone, off the hot path.
    private var terminalOptions: some View {
        List {
            Section("Text size") {
                HStack(spacing: 8) {
                    keyChip("Smaller text", "textformat.size.smaller") { fontSize = max(9, fontSize - 1) }
                    keyChip("Larger text", "textformat.size.larger") { fontSize = min(24, fontSize + 1) }
                    Spacer()
                    Text("\(Int(fontSize))pt")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Section("View") {
                Toggle("Wrap long lines", isOn: $store.readerOutput)
                    .font(.caption)
                Text(store.readerOutput
                     ? "Reader wraps everything to the screen. Best for prose, questions and errors."
                     : "Raw keeps the Mac's own line breaks. Best for diffs and tables — drag sideways to follow a long line.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if store.readerOutput && !store.supports("captureJoin", host: host) {
                    // Say which half of the job is being done. Wrapping is ours; the
                    // un-wrapping and glyph-stripping are the daemon's, and this one
                    // cannot do them.
                    Text("This machine's meshd is older than 0.5.0, so lines it already broke stay broken.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func keyChip(_ label: String, _ icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: icon).frame(width: WatchTouch.minWidth, height: WatchTouch.minHeight)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }

    /// A link the session has just printed, if any — newest first, and the event body
    /// as a fallback for a session whose output has already scrolled past it.
    private var visibleLink: URL? {
        if let url = lastLink(in: Array(terminalLines.suffix(40))) { return url }
        guard let event = store.latestEvent(host: host, session: agent) else { return nil }
        return firstLink(in: [event.body, event.title].compactMap { $0 }.joined(separator: "\n"))
    }
}

// MARK: - Screen peek

struct ScreenPeekView: View {
    @EnvironmentObject var store: WatchMeshStore
    let host: String

    /// When this view started asking. A spinner with no clock behind it is a promise
    /// nobody is keeping: the relay path can take a couple of seconds, but past that
    /// the honest thing is to say we are still trying rather than to keep spinning as
    /// if the next frame were imminent.
    @State private var askedAt = Date()
    @State private var slow = false

    private var imageData: Data? {
        store.screenHost == host ? store.screenJPEGData : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(shortName(host)) · \(store.routeLabel(for: host))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let imageData, let image = meshImage(from: imageData) {
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let error = store.screenError {
                    // The daemon's own words, not "something went wrong": Screen
                    // Recording not granted and the Mac being asleep are different
                    // problems with different fixes.
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if slow {
                    Label("No screen yet — still trying", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("Fetching screen…")
                }
                if let updated = resetText(store.screenUpdatedISO) {
                    Text(updated.replacingOccurrences(of: "resets ", with: "updated "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button {
                    ask()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(minHeight: WatchTouch.minHeight)
                }
                .buttonStyle(.borderedProminent)
                Text("Read only. Use iPhone for full terminal/VNC.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("Screen")
        .onAppear { ask() }
        .onChange(of: store.screenJPEGData) { _, data in
            if data != nil { slow = false }
        }
        .task(id: askedAt) {
            slow = false
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            if imageData == nil { slow = true }
        }
        .onDisappear { store.stopScreen() }
    }

    private func ask() {
        askedAt = Date()          // restarts the six-second clock
        store.requestScreen(host: host)
    }
}

// MARK: - Usage

struct UsageView: View {
    @EnvironmentObject var store: WatchMeshStore

    var body: some View {
        List(store.effectiveUsage?.providers ?? []) { p in
            Section("\(p.displayName) \(p.plan ?? "")") {
                if let today = p.today {
                    Text("Today \(today)").font(.caption)
                }
                if let last30 = p.last30 {
                    Text("30d \(last30)").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(p.limits) { l in
                    WatchLimitRow(limit: l)
                }
                if p.limits.isEmpty {
                    Text("No limit rows yet").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Usage")
        .overlay { if (store.effectiveUsage?.providers ?? []).isEmpty { Text("No usage data").foregroundStyle(.secondary) } }
    }
}

private struct WatchLimitRow: View {
    let limit: UsageLimit
    private var status: LimitStatus { LimitHelpers.status(usedPct: limit.usedPct) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(limit.label).font(.caption)
                Spacer()
                Text(status.label)
                    .font(.caption2)
                    .foregroundStyle(status == .blocked ? .red : (status == .warning ? .orange : .secondary))
            }
            if let pct = limit.usedPct {
                ProgressView(value: min(max(pct/100, 0), 1))
                    .tint(status == .blocked ? .red : .accentColor)
            }
            HStack {
                if let left = LimitHelpers.remainingPct(usedPct: limit.usedPct) {
                    Text(status == .blocked ? "0% left" : "\(left)% left")
                        .font(.caption2.monospacedDigit())
                }
                Spacer()
                if let countdown = LimitHelpers.resetCountdown(from: limit.resetsAtISO) {
                    Text(countdown).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Bits

struct GaugeRow: View {
    let label: String
    let value: Double
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(label).font(.caption); Spacer(); Text(text).font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
            ProgressView(value: min(max(value/100, 0), 1))
                .tint(value > 85 ? .red : value > 60 ? .orange : .green)
        }
    }
}

func shortName(_ host: String) -> String {
    host.replacingOccurrences(of: "arya-", with: "").replacingOccurrences(of: "agents", with: "")
}

/// A path's last two components — "lecoder-watch/Watch" out of a long absolute path.
/// A full path never fits a watch row, and the leaf alone is ambiguous across repos.
func lastPathBit(_ path: String) -> String {
    let parts = path.split(separator: "/").map(String.init)
    return parts.suffix(2).joined(separator: "/")
}

#if canImport(UIKit)
func meshImage(from data: Data) -> Image? {
    guard let image = UIImage(data: data) else { return nil }
    return Image(uiImage: image)
}
#else
func meshImage(from data: Data) -> Image? { nil }
#endif

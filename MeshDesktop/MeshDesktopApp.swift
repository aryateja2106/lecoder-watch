// MeshDesktopApp.swift — LeSearch Mesh in the Mac menu bar.
//
// Three jobs, and deliberately no fourth: show whether this machine's daemon is up,
// put every permission it needs behind one button, and print a pairing QR. No settings,
// no window to arrange, no state on disk beyond the Login Items registration macOS
// keeps for us.
//
// LSUIElement is true (project.yml), so there is no Dock icon and no main window — the
// menu bar item is the whole app.
import SwiftUI
import ServiceManagement
import AppKit

enum WindowID {
    static let permissions = "permissions"
    static let pair = "pair"
}

@main
struct MeshDesktopApp: App {
    @StateObject private var daemon = DaemonWatch()
    @StateObject private var login = LoginItem()

    var body: some Scene {
        // A filled dot when this Mac's daemon answered recently, a hollow one when it
        // has gone quiet. Nothing else belongs in the menu bar: a number there would be
        // read a hundred times a day and acted on once.
        MenuBarExtra("LeSearch Mesh", systemImage: daemon.up ? "circle.fill" : "circle") {
            MenuContent()
                .environmentObject(daemon)
                .environmentObject(login)
        }

        Window("Permissions", id: WindowID.permissions) {
            PermissionsView().environmentObject(daemon)
        }
        .defaultSize(width: 480, height: 560)
        .windowResizability(.contentSize)

        Window("Pair iPhone", id: WindowID.pair) {
            PairView()
        }
        .defaultSize(width: 360, height: 520)
        .windowResizability(.contentSize)
    }
}

private struct MenuContent: View {
    @EnvironmentObject var daemon: DaemonWatch
    @EnvironmentObject var login: LoginItem
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(daemon.statusLine)

        Divider()

        Button("Permissions…") { show(WindowID.permissions) }
        Button("Pair iPhone…") { show(WindowID.pair) }
        Button("Open web console") { NSWorkspace.shared.open(LocalDaemon.consoleURL) }

        Divider()

        Toggle("Start at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
        if let problem = login.problem {
            Text(problem)
        }

        Divider()

        Button("Quit LeSearch Mesh") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// An app with no Dock icon opens its windows behind whatever the user is looking
    /// at unless it asks to come forward first.
    private func show(_ id: String) {
        NSApp.activate()
        openWindow(id: id)
    }
}

/// The one place that decides whether this Mac's daemon is up.
///
/// Judged by the clock, never by a counter or by "the last request failed" — the rule
/// the phone and the watch both learned the expensive way (memory.md, "Connection state
/// is judged by the clock"). A single timed-out poll does not flip the dot; only
/// silence for longer than `offlineAfter` does. Polls are single-flight because a dead
/// host fails slower than the timer fires, so overlap is the normal case, not the edge.
@MainActor
final class DaemonWatch: ObservableObject {
    @Published private(set) var up = false
    @Published private(set) var health: LocalDaemon.Health?
    @Published private(set) var report: LocalDaemon.DoctorReport?
    @Published private(set) var reportError: String?
    @Published private(set) var fixing = false

    /// Two missed ten-second polls plus the three-second timeout, and a little slack.
    private static let offlineAfter: TimeInterval = 25
    private static let healthEvery: TimeInterval = 10
    /// /doctor spawns the input helper to test the grants, so it is polled lazily in the
    /// background. The Permissions window asks for it far more often while it is open.
    private static let doctorEvery: TimeInterval = 60

    private var lastContact: Date?
    private var lastDoctor: Date?
    private var pollingHealth = false
    private var pollingDoctor = false
    private var timer: Timer?

    init() {
        let t = Timer.scheduledTimer(withTimeInterval: Self.healthEvery, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        t.tolerance = 2
        timer = t
        Task { await tick() }
    }

    var statusLine: String {
        guard up else { return "daemon not running" }
        let version = health?.meshdVersion.map { "meshd \($0)" } ?? "meshd"
        guard let report else { return "\(version) · checking…" }
        return "\(version) · doctor \(report.passed)/\(report.total)"
    }

    private func tick() async {
        await pollHealth()
        if up, Date().timeIntervalSince(lastDoctor ?? .distantPast) >= Self.doctorEvery {
            await refreshDoctor()
        }
    }

    private func pollHealth() async {
        guard !pollingHealth else { return }
        pollingHealth = true
        defer { pollingHealth = false; settle() }
        if let fresh = try? await LocalDaemon.health(), fresh.ok {
            health = fresh
            lastContact = Date()
        }
    }

    /// Ask /doctor now. Safe to call from a view timer — overlapping calls are dropped.
    func refreshDoctor() async {
        guard !pollingDoctor else { return }
        pollingDoctor = true
        defer { pollingDoctor = false; settle() }
        do {
            report = try await LocalDaemon.doctor()
            reportError = nil
            lastContact = Date()
        } catch {
            report = nil
            reportError = error.localizedDescription
        }
        lastDoctor = Date()
    }

    /// POST /doctor/fix, then read the result back. The fix itself happens inside the
    /// daemon's own processes — that is the only place macOS will accept the request.
    func grantEverything() async {
        guard !fixing else { return }
        fixing = true
        defer { fixing = false; settle() }
        do {
            report = try await LocalDaemon.doctorFix()
            reportError = nil
            lastContact = Date()
        } catch {
            reportError = error.localizedDescription
        }
        lastDoctor = Date()
    }

    private func settle() {
        let age = lastContact.map { Date().timeIntervalSince($0) } ?? .infinity
        up = age <= Self.offlineAfter
    }
}

/// "Start at login", which is the one permission this app asks for in its own name:
/// registering here is what puts LeSearch Mesh in System Settings › General › Login
/// Items, where the user can revoke it.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var problem: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        // macOS can accept the registration and still park it until the user says yes.
        // Saying nothing here would look like the toggle simply did not work.
        if status == .requiresApproval {
            problem = "Approve it in System Settings › General › Login Items"
        }
    }
}

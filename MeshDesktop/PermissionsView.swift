// PermissionsView.swift — one window that answers "what does this Mac still need?".
//
// This window is an honest front end to GET /doctor and POST /doctor/fix. It never
// claims a grant on the daemon's behalf, because it cannot: macOS gives Accessibility
// and Screen Recording to the process that asks for them, so a GUI app that popped
// those dialogs would collect permissions for itself and leave meshd exactly as broken
// as before. Pressing "Grant everything" tells the daemon to ask, in its own processes,
// which is the only version of this button that works.
import SwiftUI
import AppKit
import UserNotifications

struct PermissionsView: View {
    @EnvironmentObject var daemon: DaemonWatch
    @StateObject private var notifications = NotificationPermission()

    /// While this window is open the report is worth a few seconds of staleness at
    /// most: the user is standing in System Settings flipping switches and expects the
    /// rows to catch up on their own.
    private static let refreshEvery: Duration = .seconds(4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let report = daemon.report {
                        ForEach(report.orderedChecks, id: \.name) { item in
                            CheckRow(name: item.name, check: item.check)
                        }
                    } else if let error = daemon.reportError {
                        DaemonDown(message: error)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Checking this Mac…").foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }

                    Divider().padding(.vertical, 2)
                    NotificationRow(permission: notifications)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 440, minHeight: 460)
        .task {
            await notifications.refresh()
            while !Task.isCancelled {
                await daemon.refreshDoctor()
                try? await Task.sleep(for: Self.refreshEvery)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Permissions").font(.title2.weight(.semibold))
                Spacer()
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }

            Button {
                Task { await daemon.grantEverything() }
            } label: {
                Label(daemon.fixing ? "Asking macOS…" : "Grant everything", systemImage: "hand.tap")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(daemon.fixing || daemon.report == nil)

            Text("macOS will show its own dialogs — click Allow on each. Screen Recording usually needs the switch turned on in System Settings as well; the buttons below open the right page.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var subtitle: String {
        guard let report = daemon.report else { return "" }
        return "\(report.host) · meshd \(report.version)"
    }
}

/// One row of /doctor, in words rather than route names.
private struct CheckRow: View {
    let name: String
    let check: LocalDaemon.DoctorReport.Check

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(check.ok ? Color.green : Color.orange)
                .font(.title3)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title(for: name)).font(.headline)
                Text(check.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !check.ok, let fix = check.fix {
                    Text(fix)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !check.ok, let settings = Self.settingsPane(for: name) {
                    Button(settings.label) { NSWorkspace.shared.open(settings.url) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "input" and "mux" are what the daemon calls them. Nobody standing in front of
    /// this window is thinking in route names.
    private static func title(for name: String) -> String {
        switch name {
        case "token": return "Token"
        case "input": return "Keyboard and mouse"
        case "screen": return "Screen recording"
        case "mux": return "Agent sessions"
        case "push": return "Push alerts"
        default: return name.capitalized
        }
    }

    /// The two grants that live in a System Settings pane the user has to find. Deep
    /// links, because "Privacy & Security › Accessibility" is four clicks away.
    private static func settingsPane(for name: String) -> (label: String, url: URL)? {
        switch name {
        case "input":
            return ("Open Accessibility settings",
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        case "screen":
            return ("Open Screen Recording settings",
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        default:
            return nil
        }
    }
}

/// This app's own notification grant — asked for here, honestly, in its own name. It is
/// what lets the Mac raise a desktop alert when an agent is waiting on you.
private struct NotificationRow: View {
    @ObservedObject var permission: NotificationPermission

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: permission.granted ? "checkmark.circle.fill" : "bell.badge")
                .foregroundStyle(permission.granted ? Color.green : Color.orange)
                .font(.title3)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications on this Mac").font(.headline)
                Text(permission.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if permission.canAsk {
                    Button("Allow notifications") { Task { await permission.request() } }
                        .buttonStyle(.link)
                        .font(.caption)
                } else if !permission.granted {
                    Button("Open Notifications settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Nothing is running, so say that instead of drawing five grey rows.
private struct DaemonDown: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "bolt.horizontal.circle")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Install it, or start it again, with one line in Terminal:")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(LocalDaemon.installCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(LocalDaemon.installCommand, forType: .string)
                }
            }
        }
    }
}

@MainActor
final class NotificationPermission: ObservableObject {
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published private(set) var failure: String?

    var granted: Bool { status == .authorized || status == .provisional }
    var canAsk: Bool { status == .notDetermined }

    var detail: String {
        if let failure { return failure }
        switch status {
        case .authorized, .provisional: return "Allowed — agent alerts can reach you here."
        case .denied: return "Turned off. Alerts still land on your phone and watch."
        default: return "Not asked yet. Used for agent alerts on this Mac."
        }
    }

    func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func request() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        await refresh()
    }
}

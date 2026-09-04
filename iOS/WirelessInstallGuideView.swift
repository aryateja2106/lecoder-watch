import SwiftUI

public struct WirelessInstallGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: InstallTab = .wirelessOTA

    enum InstallTab: String, CaseIterable, Identifiable {
        case wirelessOTA = "Wireless OTA"
        case testFlight = "TestFlight"
        case pwa = "Web App (PWA)"

        var id: String { rawValue }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Installation Method", selection: $selectedTab) {
                    ForEach(InstallTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .wirelessOTA:
                            wirelessOTAGuide
                        case .testFlight:
                            testFlightGuide
                        case .pwa:
                            pwaGuide
                        }

                        permissionsChecklist
                    }
                    .padding(18)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Install Apps Without Cable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Method 1: Wireless OTA

    private var wirelessOTAGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "wifi")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wireless Over-The-Air (OTA)")
                        .font(.headline)
                    Text("Install native IPAs over Wi-Fi directly to Home Screen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("You do NOT need a USB cable. When your Mac agent finishes building an app, it publishes a wireless manifest.plist.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Step-by-step
            VStack(spacing: 12) {
                stepRow(number: "1", title: "Tap Install in LeSearch Mesh", detail: "When an agent outputs an app, tap 'Install on this Device'. iOS will display: '[your-mac] would like to install <App>'. Tap Install.")

                stepRow(number: "2", title: "Enable iOS Developer Mode (One-Time)", detail: "On iOS 16/17/18+: Open iPhone Settings → Privacy & Security → scroll to bottom → Developer Mode → Turn On. iPhone will restart.")

                stepRow(number: "3", title: "Trust Developer Certificate (One-Time)", detail: "Open iPhone Settings → General → VPN & Device Management → tap Developer App ('B5B87F7AXF') → Trust.")
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Mock iOS system dialog
            VStack(alignment: .leading, spacing: 8) {
                Text("What iOS will ask you:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: "app.badge.checkmark.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\"127.0.0.1:7777\" would like to install \"HabitTracker\"")
                            .font(.footnote.weight(.semibold))
                        Text("System prompt from SpringBoard • Over-The-Air install")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Method 2: TestFlight

    private var testFlightGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "airplane")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple TestFlight")
                        .font(.headline)
                    Text("Zero UDID registration • Official Apple Beta Channel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Best for sharing apps with colleagues or when you don't want to manage device UDIDs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                stepRow(number: "1", title: "Connect App Store Connect Key", detail: "Save your ASC API Key ID and Issuer ID in your Mac Keychain or mesh config.")
                stepRow(number: "2", title: "Agent Uploads via asc CLI", detail: "The agent runs xcodebuild archive and uploads directly to TestFlight in the background.")
                stepRow(number: "3", title: "Install via TestFlight App", detail: "You receive an instant push notification from Apple's TestFlight app on your iPhone. Tap Update / Install.")
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Method 3: PWA

    private var pwaGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "globe")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Progressive Web App (PWA)")
                        .font(.headline)
                    Text("Zero Apple developer fees • Installs in 2 seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("No Apple Developer account needed. The app runs full-screen without Safari browser bars and stores data directly on your phone using IndexedDB.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                stepRow(number: "1", title: "Tap 'Preview PWA' in Chat", detail: "LeSearch Mesh opens the local web application in Safari.")
                stepRow(number: "2", title: "Tap Share Button ⎋", detail: "At the bottom toolbar of Safari, tap the Share icon (square with arrow pointing up).")
                stepRow(number: "3", title: "Select 'Add to Home Screen' ⊞", detail: "Tap Add in the top right. The app will appear as a standalone icon on your iPhone home screen.")
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Permissions Checklist

    private var permissionsChecklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iPhone Permission Status")
                .font(.headline)

            VStack(spacing: 10) {
                permissionRow(title: "Local Network Access", detail: "Required to reach your Mac over LAN / Wi-Fi", isGranted: true)
                permissionRow(title: "Microphone Access", detail: "Used for voice dictation and speech-to-text", isGranted: true)
                permissionRow(title: "Speech Recognition", detail: "Enables on-device neural transcription", isGranted: true)
                permissionRow(title: "Push Notifications", detail: "Alerts you when agents ask for decisions", isGranted: true)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open iPhone Settings", systemImage: "gearshape")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Helper Views

    private func stepRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15))
                .foregroundStyle(Color.accentColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(title: String, detail: String, isGranted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

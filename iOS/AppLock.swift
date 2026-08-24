import Foundation
import LocalAuthentication
import SwiftUI

/// Biometric gate in front of the app.
///
/// The app holds tokens that open a shell on the user's machines, so an unlocked
/// phone left on a desk should not be enough. Uses `deviceOwnerAuthentication`
/// (Face ID / Touch ID with passcode fallback) so a failed scan can never lock
/// someone out of their own machines.
@MainActor
final class AppLock: ObservableObject {
    @Published private(set) var isLocked: Bool
    @Published private(set) var lastError: String?
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if !enabled { isLocked = false }
        }
    }

    private static let enabledKey = "mesh.requireBiometrics.v1"
    /// Short trips out of the app (copying a token, reading a doc) shouldn't
    /// demand a re-scan; a real "put the phone down" gap should.
    private static let graceInterval: TimeInterval = 180
    private var backgroundedAt: Date?

    init() {
        // On by default: the tokens are worth gating, and the passcode fallback
        // means the gate can never lock the owner out. Settings > Security turns
        // it off for anyone who disagrees.
        let on = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        enabled = on
        // Fail open when the device has no passcode or biometry enrolled — there is
        // no security boundary to enforce, and locking would just brick the app.
        isLocked = on && Self.isAvailable
    }

    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// "Face ID" / "Touch ID" / "your passcode" — for button and prompt copy.
    static var methodName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return "your passcode"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "your passcode"
        }
    }

    func unlock() async {
        guard isLocked else { return }
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock LeSearch Mesh to reach your machines"
            )
            if ok {
                isLocked = false
                lastError = nil
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
            lastError = nil   // user backed out on purpose; not a failure to report
        } catch {
            lastError = error.localizedDescription
        }
    }

    func didEnterBackground() {
        backgroundedAt = Date()
    }

    func willEnterForeground() {
        defer { backgroundedAt = nil }
        guard enabled, Self.isAvailable, let left = backgroundedAt else { return }
        if Date().timeIntervalSince(left) >= Self.graceInterval { isLocked = true }
    }
}

struct LockScreen: View {
    @EnvironmentObject var lock: AppLock

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 6) {
                Text("LeSearch Mesh is locked").font(.title2.bold())
                Text("Your machine tokens are protected by \(AppLock.methodName).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let error = lock.lastError {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                Text("Unlock with \(AppLock.methodName)").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .task { await lock.unlock() }   // offer the prompt immediately on appear
    }
}

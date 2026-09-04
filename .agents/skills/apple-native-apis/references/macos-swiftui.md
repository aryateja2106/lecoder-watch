# macOS 14/15+ Native APIs (MacBook & Mac Studio)

Comprehensive reference for building macOS applications using modern SwiftUI, MenuBarExtra, Keychain, and Process execution.

---

## 1. MenuBarExtra (Always-On Menu Bar Status)

```swift
import SwiftUI

@main
struct MeshDesktopApp: App {
    @State private var isOnline = true

    var body: some Scene {
        WindowGroup {
            MainDashboardView()
        }

        MenuBarExtra("LeSearch Mesh", systemImage: isOnline ? "atom" : "atom.badge.slash") {
            VStack {
                Button("Open Workspace") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
                Button("Start Local Model") {
                    // Start local daemon or model server
                }
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView()
        }
    }
}
```

---

## 2. Process Execution (Running CLI Agents & Compilers)

```swift
import Foundation

public final class LocalProcessRunner {
    public static func run(command: String, arguments: [String], cwd: String? = nil) async throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}
```

---

## 3. macOS Keychain Secure Storage

```swift
import Security
import Foundation

public enum MacKeychain {
    public static func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &dataTypeRef) == errSecSuccess {
            return dataTypeRef as? Data
        }
        return nil
    }
}
```

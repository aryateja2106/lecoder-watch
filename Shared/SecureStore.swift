import Foundation
import Security

/// Keychain storage for anything that grants access to a user's machines.
///
/// A meshd token is shell access to someone's computer. `UserDefaults` is an
/// unencrypted plist inside the app container and is included in device backups,
/// so tokens must not live there — this is the replacement, on the phone and the
/// watch alike (both cache the machine list, tokens included).
///
/// Items use `AfterFirstUnlockThisDeviceOnly`: never synced to iCloud and never
/// restored onto a different device. Not `WhenUnlocked`, deliberately — the
/// background usage poll (BGAppRefreshTask) runs while the phone is locked in a
/// pocket, and a token it cannot read is a limit alert that never fires. The
/// at-rest encryption before first unlock is what actually protects a stolen
/// powered-off phone either way.
enum SecureStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.lecoder.meshwatch"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    @discardableResult
    static func save(_ data: Data, for key: String) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var insert = baseQuery(key)
        insert.merge(attributes) { current, _ in current }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func load(_ key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    /// Move a value written by an older build out of UserDefaults and into the
    /// Keychain, exactly once. Returns the data either way so callers can keep
    /// reading through a single path.
    static func migrateFromUserDefaults(key: String, defaults: UserDefaults = .standard) -> Data? {
        if let existing = load(key) {
            // Clear the plaintext copy on every launch that sees one, not only on the
            // launch that happened to perform the migration. The early return used to
            // skip this, so a device whose Keychain was already populated kept an
            // unencrypted, backed-up copy of every machine token forever — which is the
            // exact thing this type exists to prevent. Measured on a real phone.
            defaults.removeObject(forKey: key)
            return existing
        }
        guard let legacy = defaults.data(forKey: key) else { return nil }
        // Only drop the plaintext copy once the Keychain write is confirmed.
        if save(legacy, for: key) {
            defaults.removeObject(forKey: key)
        }
        return legacy
    }

    /// Same, for a value an older build stored with `set(_: String, forKey:)`.
    /// Those come back through `string(forKey:)` — `data(forKey:)` returns nil for
    /// a plist string, so the Data-shaped migration above would silently skip it
    /// and leave the plaintext behind.
    static func migrateStringFromUserDefaults(key: String, defaults: UserDefaults = .standard) -> String? {
        if let existing = string(key) {
            defaults.removeObject(forKey: key)   // same leak, same fix
            return existing
        }
        guard let legacy = defaults.string(forKey: key), !legacy.isEmpty else { return nil }
        if save(legacy, for: key) {
            defaults.removeObject(forKey: key)
        }
        return legacy
    }

    /// String convenience for single-value secrets.
    static func string(_ key: String) -> String? {
        load(key).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        save(Data(value.utf8), for: key)
    }
}

import Foundation
import Security

/// Local-first secret store backed by the iOS Keychain (Secure Enclave-protected, available
/// after first unlock, never synced off-device). Secrets keyed by an arbitrary account string so
/// the same vault holds the meshd token *and* (later) multiple named SSH/VNC identities:
///   "<machineUUID>/token"  ·  "<machineUUID>/ssh/<credUUID>"  ·  "<machineUUID>/vnc/<credUUID>"
///
/// ponytail: iOS Keychain *is* the local vault — no dependency. The clean seam for a future
/// cross-device OSS sync-vault is exactly this account-string API; layer sync under it, don't
/// rebuild it.
enum KeychainVault {
    private static let service = "com.lecoder.meshwatch.vault"

    @discardableResult
    static func set(_ secret: String, account: String) -> Bool {
        let data = Data(secret.utf8)
        // Upsert: delete any existing item, then add fresh with our accessibility class.
        delete(account: account)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func secret(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: meshd token convenience

    static func tokenAccount(_ machineID: UUID) -> String { "\(machineID.uuidString)/token" }
    static func token(for machineID: UUID) -> String? { secret(account: tokenAccount(machineID)) }
    static func setToken(_ token: String, for machineID: UUID) { set(token, account: tokenAccount(machineID)) }
    static func deleteToken(for machineID: UUID) { delete(account: tokenAccount(machineID)) }

    // MARK: named SSH/VNC credential convenience

    static func credentialAccount(_ id: UUID) -> String { "cred/\(id.uuidString)" }
    static func secret(forCredential id: UUID) -> String? { secret(account: credentialAccount(id)) }
    static func setSecret(_ value: String, forCredential id: UUID) { set(value, account: credentialAccount(id)) }
    static func deleteSecret(forCredential id: UUID) { delete(account: credentialAccount(id)) }
}

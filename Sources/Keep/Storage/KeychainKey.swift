import CryptoKit
import Foundation
import Security

/// Loads the snapshot key from the Keychain, creating a 256-bit key the first time.
enum KeychainKey {
    private static let service = "com.keep.snapshot"
    private static let account = "snapshot-key"

    static func loadOrCreate() -> SymmetricKey? {
        if let existing = load() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key.withUnsafeBytes { Data($0) }
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecDuplicateItem ? (load() ?? key) : nil
    }

    private static func load() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return SymmetricKey(data: data)
    }
}

import Foundation
import Security

enum APIKeyStore {
    private static let service = "com.keke.api-keys"
    private static let account = "ai_api_keys"
    private static var cache: [String: String]?

    static func allKeys() -> [String: String] {
        if let cache = cache { return cache }
        if let data = readKeychain(),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
            return dict
        }
        let legacy = (UserDefaults.standard.dictionary(forKey: "ai_api_keys") as? [String: String]) ?? [:]
        if !legacy.isEmpty {
            writeKeychain(legacy)
            UserDefaults.standard.removeObject(forKey: "ai_api_keys")
        }
        cache = legacy
        return legacy
    }

    static func setAllKeys(_ keys: [String: String]) {
        cache = keys
        writeKeychain(keys)
    }

    static func key(for providerId: String) -> String {
        allKeys()[providerId] ?? ""
    }

    static func setKey(_ key: String, for providerId: String) {
        var keys = allKeys()
        keys[providerId] = key
        setAllKeys(keys)
    }

    static func hasKey(for providerId: String) -> Bool {
        !key(for: providerId).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Keychain

    private static func readKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func writeKeychain(_ keys: [String: String]) {
        guard let data = try? JSONEncoder().encode(keys) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

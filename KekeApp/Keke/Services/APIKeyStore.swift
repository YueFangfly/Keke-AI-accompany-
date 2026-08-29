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

    // MARK: - 非 AI 提供方的密钥

    /// ElevenLabs、GitHub 这类不是「AI 提供方」但同样是密钥的东西。
    /// 它们原本明文存在 UserDefaults 里——那份是可以被备份、被同步、被翻出来的。
    ///
    /// 复用同一个 keychain 条目，用 `service:` 前缀跟提供方 id 分开：
    /// 自定义提供方的 id 是 UUID，不会带冒号，撞不上
    enum Secret: String, CaseIterable {
        case elevenLabs = "service:elevenlabs"
        case github = "service:github"

        /// 迁移用：这个密钥以前存在 UserDefaults 的哪个键下
        var legacyDefaultsKey: String {
            switch self {
            case .elevenLabs: return "eleven_api_key"
            case .github: return "gh_token"
            }
        }
    }

    /// 读。第一次读到空值时会去 UserDefaults 里捞一把老数据，捞到就搬进 keychain
    /// 并把明文那份删掉——用户不用做任何操作，升级一次就迁完了
    static func secret(_ secret: Secret) -> String {
        if let existing = allKeys()[secret.rawValue], !existing.isEmpty { return existing }
        let legacy = UserDefaults.standard.string(forKey: secret.legacyDefaultsKey) ?? ""
        guard !legacy.isEmpty else { return "" }
        setSecret(legacy, for: secret)
        UserDefaults.standard.removeObject(forKey: secret.legacyDefaultsKey)
        return legacy
    }

    static func setSecret(_ value: String, for secret: Secret) {
        setKey(value, for: secret.rawValue)
        // 存新值的同时把可能还残留的明文抹掉，不然改过一次 key 之后
        // UserDefaults 里那份旧的还躺着
        UserDefaults.standard.removeObject(forKey: secret.legacyDefaultsKey)
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

import FXMicCore
import Foundation
import Security
import os

/// API keys of the LLM providers, in the login Keychain (TDD voice command agent §4). The config
/// only holds the item's name (`LLMProvider.apiKeyRef`); keys are never logged or written to disk.
enum KeychainStore {
    static let service = "com.fxmicbridge.llm"
    private static let log = Logger(subsystem: "com.fxmicbridge", category: "keychain")
    /// Read once per run: every read of an item can show a macOS prompt after a rebuild.
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func key(_ account: String?) -> String? {
        guard let account else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[account] { return cached }
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound { log.error("read \(account, privacy: .public) failed: \(status, privacy: .public)") }
            return nil
        }
        cache[account] = key
        return key
    }

    static func hasKey(_ account: String?) -> Bool { key(account) != nil }

    @discardableResult
    static func setKey(_ key: String, for account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let data = Data(key.utf8)
        var status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = data
            q[kSecAttrLabel as String] = "CUE-2350 MIC · \(account)"
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            log.error("write \(account, privacy: .public) failed: \(status, privacy: .public)")
            return false
        }
        cache[account] = key
        return true
    }

    static func deleteKey(_ account: String) {
        lock.lock()
        defer { lock.unlock() }
        SecItemDelete(query(account) as CFDictionary)
        cache[account] = nil
    }
}

extension AppConfig.LLM {
    /// The client for the provider in use, with its key from the Keychain.
    var client: OpenAICompatibleClient { client(apiKey: KeychainStore.key(active.apiKeyRef)) }
}

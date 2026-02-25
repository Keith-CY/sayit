import Foundation
import Security

public final class KeychainStore: @unchecked Sendable {
    private let service: String
    private var cache: [String: String] = [:]
    private var loadedAllItems = false
    private var bulkLoadDisabled = false
    private let lock = NSLock()

    public init(service: String = "com.sayit.credentials") {
        self.service = service
    }

    public func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addAttrs = query
            addAttrs[kSecValueData as String] = data
            addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SayItError.storage("Failed to save keychain item \(key), status=\(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            throw SayItError.storage("Failed to update keychain item \(key), status=\(updateStatus)")
        }

        lock.lock()
        cache[key] = value
        lock.unlock()
    }

    public func get(_ key: String) throws -> String? {
        if let cached = cachedValue(for: key) {
            return cached
        }

        ensureAllLoaded()
        if let cached = cachedValue(for: key) {
            return cached
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SayItError.storage("Failed to read keychain item \(key), status=\(status)")
        }

        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SayItError.storage("Invalid keychain payload for \(key)")
        }

        lock.lock()
        cache[key] = value
        lock.unlock()
        return value
    }

    public func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        lock.lock()
        cache.removeValue(forKey: key)
        lock.unlock()
    }

    private func cachedValue(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    private func ensureAllLoaded() {
        lock.lock()
        if loadedAllItems || bulkLoadDisabled {
            lock.unlock()
            return
        }
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecParam {
            // Some keychain configurations reject broad service-wide queries.
            // Fall back to account-specific lookups instead of blocking callers.
            lock.lock()
            bulkLoadDisabled = true
            lock.unlock()
            return
        }
        if status != errSecSuccess && status != errSecItemNotFound {
            // Best-effort cache warm-up only; caller will do account-specific read.
            return
        }

        var loaded: [String: String] = [:]
        if status == errSecSuccess {
            if let entries = result as? [[String: Any]] {
                for entry in entries {
                    guard
                        let account = entry[kSecAttrAccount as String] as? String,
                        let data = entry[kSecValueData as String] as? Data,
                        let value = String(data: data, encoding: .utf8)
                    else { continue }
                    loaded[account] = value
                }
            } else if let entry = result as? [String: Any] {
                if
                    let account = entry[kSecAttrAccount as String] as? String,
                    let data = entry[kSecValueData as String] as? Data,
                    let value = String(data: data, encoding: .utf8)
                {
                    loaded[account] = value
                }
            }
        }

        lock.lock()
        for (k, v) in loaded {
            cache[k] = v
        }
        loadedAllItems = true
        lock.unlock()
    }
}

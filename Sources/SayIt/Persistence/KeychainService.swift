import Foundation
import Security

enum KeychainServiceError: Error, LocalizedError {
    case invalidData
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Failed to convert key data."
        case let .unhandled(status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "\(message) (OSStatus: \(status))"
            }
            return "Unhandled Keychain error (OSStatus: \(status))"
        }
    }
}

/// Lightweight helper for storing provider API keys in the system Keychain.
/// Keys are stored as generic passwords scoped to the SayIt keychain namespace.
final class KeychainService {
    static let shared = KeychainService()

    private let service = AppIdentity.keychainService
    private let legacyService = AppIdentity.legacyKeychainService
    private let account = AppIdentity.keychainAccount

    private init() {}

    // MARK: - Public API

    func storeKey(_ key: String, for providerID: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var keys = try loadStoredKeys()
        keys[providerID] = trimmed
        try self.saveStoredKeys(keys)
    }

    func fetchKey(for providerID: String) throws -> String? {
        let keys = try loadStoredKeys()
        return keys[providerID]
    }

    func deleteKey(for providerID: String) throws {
        var keys = try loadStoredKeys()
        guard keys.removeValue(forKey: providerID) != nil else { return }
        try self.saveStoredKeys(keys)
    }

    func containsKey(for providerID: String) -> Bool {
        guard let keys = try? loadStoredKeys() else { return false }
        return keys[providerID] != nil
    }

    func allProviderIDs() throws -> [String] {
        return try self.loadStoredKeys().keys.sorted()
    }

    func fetchAllKeys() throws -> [String: String] {
        try self.loadStoredKeys()
    }

    func storeAllKeys(_ values: [String: String]) throws {
        try self.saveStoredKeys(values)
    }

    func legacyProviderEntries() throws -> [String: String] {
        var result: [String: String] = [:]
        let services = [self.service, self.legacyService]

        for service in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnAttributes as String: true,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]

            var items: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &items)

            switch status {
            case errSecSuccess:
                guard let attributesArray = items as? [[String: Any]] else { continue }
                for attributes in attributesArray {
                    guard let providerID = attributes[kSecAttrAccount as String] as? String,
                          providerID != self.account,
                          let data = attributes[kSecValueData as String] as? Data,
                          let key = String(data: data, encoding: .utf8)
                    else {
                        continue
                    }
                    result[providerID] = key
                }
            case errSecItemNotFound:
                continue
            default:
                throw KeychainServiceError.unhandled(status)
            }
        }

        return result
    }

    func removeLegacyEntries(providerIDs: [String] = []) throws {
        let targetProviderIDs: [String]
        if providerIDs.isEmpty {
            targetProviderIDs = Array(try self.legacyProviderEntries().keys)
        } else {
            targetProviderIDs = providerIDs
        }

        for providerID in targetProviderIDs {
            for service in [self.service, self.legacyService] {
                let status = SecItemDelete(
                    credentialQuery(for: service, providerID: providerID) as CFDictionary
                )
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw KeychainServiceError.unhandled(status)
                }
            }
        }
    }

    // MARK: - Private helpers

    private func loadStoredKeys() throws -> [String: String] {
        let keys = try fetchStoredKeys(from: self.service)
        if !keys.isEmpty {
            return keys
        }

        let legacyKeys = try fetchStoredKeys(from: self.legacyService)
        if legacyKeys.isEmpty {
            return [:]
        }

        do {
            try self.saveStoredKeys(legacyKeys)
        } catch {
            return legacyKeys
        }

        return legacyKeys
    }

    private func fetchStoredKeys(from service: String) throws -> [String: String] {
        var query = aggregatedQuery(for: service)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainServiceError.invalidData
            }
            if data.isEmpty {
                return [:]
            }
            do {
                return try JSONDecoder().decode([String: String].self, from: data)
            } catch {
                throw KeychainServiceError.invalidData
            }
        case errSecItemNotFound:
            return [:]
        default:
            throw KeychainServiceError.unhandled(status)
        }
    }

    private func saveStoredKeys(_ keys: [String: String]) throws {
        let data = try JSONEncoder().encode(keys)

        var attributes = aggregatedQuery(for: self.service)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            try self.removeLegacyEntries()
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                aggregatedQuery(for: self.service) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainServiceError.unhandled(updateStatus)
            }
            try self.removeLegacyEntries()
        default:
            throw KeychainServiceError.unhandled(status)
        }
    }

    private func aggregatedQuery(for service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: self.account,
        ]
    }

    private func credentialQuery(for service: String, providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
        ]
    }
}

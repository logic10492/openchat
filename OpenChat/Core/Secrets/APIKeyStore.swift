import Foundation
import Security

protocol APIKeyStore: Sendable {
    func readKey(endpointId: String) throws -> String?
    func saveKey(_ key: String, endpointId: String) throws
    func deleteKey(endpointId: String) throws
}

enum APIKeyStoreError: LocalizedError, Sendable {
    case invalidKeyData
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKeyData:
            "Stored API key data is invalid."
        case .keychainFailure(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}

struct KeychainAPIKeyStore: APIKeyStore {
    private let service: String

    init(service: String = "fukujusou.openchat.api-keys") {
        self.service = service
    }

    func readKey(endpointId: String) throws -> String? {
        var query = baseQuery(endpointId: endpointId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw APIKeyStoreError.keychainFailure(status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw APIKeyStoreError.invalidKeyData
        }
        return key
    }

    func saveKey(_ key: String, endpointId: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw APIKeyStoreError.invalidKeyData
        }

        var query = baseQuery(endpointId: endpointId)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw APIKeyStoreError.keychainFailure(updateStatus)
        }

        for (key, value) in attributes {
            query[key] = value
        }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychainFailure(addStatus)
        }
    }

    func deleteKey(endpointId: String) throws {
        let status = SecItemDelete(baseQuery(endpointId: endpointId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainFailure(status)
        }
    }

    private func baseQuery(endpointId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: endpointId,
        ]
    }
}

final class InMemoryAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: String] = [:]

    func readKey(endpointId: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return keys[endpointId]
    }

    func saveKey(_ key: String, endpointId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        keys[endpointId] = key
    }

    func deleteKey(endpointId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        keys.removeValue(forKey: endpointId)
    }
}

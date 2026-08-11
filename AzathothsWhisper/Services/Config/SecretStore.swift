import Foundation
import Security

// Token 儲存抽象。生產走 Keychain，測試走 InMemory（Plan §4.9：測試禁讀真實 .env / 真實 Keychain）。
protocol SecretStore: Sendable {
    func read(_ key: String) throws -> String?
    func write(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

enum SecretStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case malformedData
}

struct KeychainStore: SecretStore {
    let service: String

    init(service: String = "com.ibridgezhao.azathothswhisper") {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func read(_ key: String) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw SecretStoreError.malformedData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    func write(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else { throw SecretStoreError.malformedData }
        let query = baseQuery(key)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound { throw SecretStoreError.unexpectedStatus(updateStatus) }

        var insert = query
        insert[kSecValueData as String] = data
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecretStoreError.unexpectedStatus(addStatus) }
    }

    func delete(_ key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }
}

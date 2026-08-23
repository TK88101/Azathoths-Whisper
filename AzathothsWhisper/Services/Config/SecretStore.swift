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

/// 記憶體內的 secret 儲存。生產路徑一律走 `KeychainStore`——本型別有兩個用途：
///
/// 1. **單元測試 host 的 app 啟動**（見 `AppModel.isUnitTestHost`）：TEST_HOST 是完整 app，
///    啟動即組裝 live 依賴；若走真實 Keychain，ad-hoc 重簽後的 ACL 失配會彈授權框
///    並阻塞啟動（2026-08-23 A1 根因）。
/// 2. **測試的依賴注入**：取代原 `Tests/Support/InMemorySecretStore`（兩者逐行同構，
///    後者的 `writeCount`／`init(initial:)` 零呼叫點，已合併刪除）。
///
/// 定義在主 target 而非 Tests/：用途 1 是生產組裝路徑，編譯不到測試 target 的型別。
final class EphemeralSecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func read(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func write(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}

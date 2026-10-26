import Foundation
import Security

/// 按鈕③：Keychain 寫入隨機測試值 → 讀回比對 → 刪除。測試值只在記憶體與 Keychain 內，不顯示、不記錄。
enum KeychainProbe {
    static let service = "com.ibridgezhao.yse.probe.test"
    private static let account = "n5-probe"

    static func run() -> KeychainReport {
        let expected = randomHex()
        _ = delete()   // 清掉上次中斷可能殘留的項目；狀態碼不納入判定
        let writeStatus = write(expected)
        guard writeStatus == errSecSuccess else {
            return KeychainReport(expected: expected, writeStatus: writeStatus, readStatus: nil, readValue: nil, deleteStatus: nil)
        }
        let (readStatus, readValue) = read()
        let deleteStatus = delete()
        return KeychainReport(expected: expected, writeStatus: writeStatus, readStatus: readStatus,
                              readValue: readValue, deleteStatus: deleteStatus)
    }

    private static var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private static func write(_ value: String) -> Int32 {
        var query = baseQuery
        query[kSecValueData] = Data(value.utf8)
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil)
    }

    private static func read() -> (Int32, String?) {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return (status, nil) }
        return (status, String(data: data, encoding: .utf8))
    }

    private static func delete() -> Int32 {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static func randomHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

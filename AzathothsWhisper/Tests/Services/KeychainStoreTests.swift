import Foundation
import Testing

@testable import AzathothsWhisper

// KeychainStore 的真實 Keychain 往返測試。
// 使用測試專用 service 名（絕不碰生產條目 com.ibridgezhao.azathothswhisper），每次測完清除。
@Suite(.serialized)
struct KeychainStoreTests {
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "com.ibridgezhao.azathothswhisper.tests.\(UUID().uuidString)")
    }

    @Test func writeReadUpdateDeleteRoundTrip() throws {
        let store = makeStore()
        let key = "GENIUS_ACCESS_TOKEN"
        defer { try? store.delete(key) }

        #expect(try store.read(key) == nil, "未寫入時回 nil，不拋錯")

        try store.write("fake-token-1", for: key)
        #expect(try store.read(key) == "fake-token-1")

        try store.write("fake-token-2", for: key)
        #expect(try store.read(key) == "fake-token-2", "同一鍵重複寫入應更新而非重複新增")

        try store.delete(key)
        #expect(try store.read(key) == nil)
    }

    @Test func deleteIsIdempotent() throws {
        let store = makeStore()
        try store.delete("never-written")
        try store.delete("never-written")
    }

    @Test func storesUnicodeValues() throws {
        let store = makeStore()
        let key = "unicode"
        defer { try? store.delete(key) }
        try store.write("トークン・令牌・töken", for: key)
        #expect(try store.read(key) == "トークン・令牌・töken")
    }

    @Test func servicesAreIsolated() throws {
        let a = makeStore()
        let b = makeStore()
        defer {
            try? a.delete("k")
            try? b.delete("k")
        }

        try a.write("fake-a", for: "k")
        #expect(try b.read("k") == nil, "不同 service 名互不可見")
        #expect(try a.read("k") == "fake-a")
    }

    // ConfigStore 走真實 Keychain 的整合路徑（其餘測試用 InMemory 替身）
    @Test func configStoreRoundTripsThroughKeychain() throws {
        let suiteName = "AzathothsWhisperTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let keychain = makeStore()
        let store = ConfigStore(secrets: keychain, defaults: defaults)
        defer {
            try? keychain.delete(ConfigStore.Key.token)
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        try store.setToken("fake-keychain-token")
        #expect(store.token == "fake-keychain-token")
        try store.setToken("")
        #expect(store.token == "")
    }
}

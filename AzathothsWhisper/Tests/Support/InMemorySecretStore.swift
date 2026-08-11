import Foundation

@testable import AzathothsWhisper

// 測試用 SecretStore 替身（Plan §4.9：測試禁碰真實 Keychain / 真實 .env）
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    private(set) var writeCount = 0

    init(initial: [String: String] = [:]) {
        storage = initial
    }

    func read(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func write(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
        writeCount += 1
    }

    func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}

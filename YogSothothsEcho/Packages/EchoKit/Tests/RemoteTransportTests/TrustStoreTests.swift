import Foundation
import Testing
@testable import RemoteTransport

// S2 T5（sprint-2-detail.md §4.4）：信任紀錄綁定本機身分；協定只有 validRecords 一個讀取口

private func fp(_ byte: UInt8) -> Fingerprint { Fingerprint(bytes: Data(repeating: byte, count: 32))! }
private func record(_ peer: UInt8, local: UInt8, name: String = "iPad") -> PeerRecord {
    PeerRecord(peerID: UUID(), fingerprint: fp(peer), localFingerprint: fp(local), name: name,
               pairedAt: Date(timeIntervalSince1970: 1))
}

private func stores() -> [any TrustStore] {
    let suite = "yse.test.trust." + UUID().uuidString
    return [InMemoryTrustStore(), UserDefaultsTrustStore(suiteName: suite)]
}

struct TrustStoreTests {
    @Test(arguments: [0, 1]) func trustBoundToPreviousIdentityIsIgnored(kind: Int) throws {
        let store = stores()[kind]
        try store.add(record(1, local: 0xAA))
        #expect(store.validRecords(for: fp(0xAA)).count == 1)
        #expect(store.validRecords(for: fp(0xBB)).isEmpty)
    }

    @Test(arguments: [0, 1]) func addOverwritesSamePairAndKeepsOthers(kind: Int) throws {
        let store = stores()[kind]
        try store.add(record(1, local: 0xAA, name: "old"))
        try store.add(record(2, local: 0xAA))
        try store.add(record(1, local: 0xAA, name: "new"))
        let valid = store.validRecords(for: fp(0xAA))
        #expect(valid.count == 2)
        #expect(valid.first { $0.fingerprint == fp(1) }?.name == "new")
    }

    @Test(arguments: [0, 1]) func staleRecordsArePrunedOnNextWrite(kind: Int) throws {
        let store = stores()[kind]
        try store.add(record(1, local: 0xAA))
        try store.add(record(2, local: 0xBB))   // 本機身分換成 BB 之後的第一筆寫入
        #expect(store.validRecords(for: fp(0xAA)).isEmpty)
        #expect(store.validRecords(for: fp(0xBB)).count == 1)
    }

    @Test(arguments: [0, 1]) func revokingOnePeerKeepsOther(kind: Int) throws {
        let store = stores()[kind]
        let a = record(1, local: 0xAA), b = record(2, local: 0xAA)
        try store.add(a)
        try store.add(b)
        try store.remove(peerID: a.peerID)
        #expect(store.validRecords(for: fp(0xAA)) == [b])
        try store.removeAll()
        #expect(store.validRecords(for: fp(0xAA)).isEmpty)
    }

    @Test func userDefaultsPersistsAcrossInstances() throws {
        let suite = "yse.test.trust." + UUID().uuidString
        try UserDefaultsTrustStore(suiteName: suite).add(record(1, local: 0xAA))
        #expect(UserDefaultsTrustStore(suiteName: suite).validRecords(for: fp(0xAA)).count == 1)
    }

    @Test func corruptDataIsTreatedAsEmptyAndReported() {
        let suite = "yse.test.trust." + UUID().uuidString
        UserDefaults(suiteName: suite)!.set(Data("not json".utf8), forKey: UserDefaultsTrustStore.defaultKey)
        let audit = SpyAuditSink()
        let store = UserDefaultsTrustStore(suiteName: suite, audit: audit)
        #expect(store.validRecords(for: fp(0xAA)).isEmpty)
        #expect(audit.events == [.trustStoreCorrupt])
    }
}

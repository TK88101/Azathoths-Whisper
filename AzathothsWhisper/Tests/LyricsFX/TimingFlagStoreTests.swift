import Foundation
import Testing

@testable import AzathothsWhisper

// ⑪ 計劃 §4.2：「時間軸不準」標記的存檔。鍵＝(persistentID, lyricsHash)；讀不懂的檔不讀、不覆寫。歌詞為編造句
@Suite("TimingFlagStore")
struct TimingFlagStoreTests {
    static let pid = "0123456789ABCDEF"
    static let hashA = LyricsFingerprint.of("Lanterns over the river")
    static let hashB = LyricsFingerprint.of("Quiet harbor\nSalt on the glass")

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("azw-timing-flags-\(UUID().uuidString)")
    }

    static func flag(
        pid: String = pid, hash: LyricsFingerprint = hashA, markedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        positions: [Double] = [12.3], anchors: Int = 2
    ) -> TimingFlag {
        TimingFlag(
            persistentID: pid, lyricsHash: hash, markedAt: markedAt, positions: positions,
            applied: AppliedTiming(source: .lrclib, anchors: (0..<anchors).map { .init(index: $0, start: Double($0) * 2.5) }),
            stored: nil, provenance: .storeMissing
        )
    }

    private func key(_ hash: LyricsFingerprint = hashA) -> TimingFlagKey {
        TimingFlagKey(persistentID: Self.pid, lyricsHash: hash)
    }

    @Test func aFlagRoundTripsThroughTheFile() async throws {
        let directory = tempDirectory()
        let flag = Self.flag()
        try await TimingFlagStore(directory: directory).flag(flag)
        let reread = TimingFlagStore(directory: directory)
        #expect(await reread.isFlagged(key()))
        #expect(try await reread.all() == [flag])
    }

    @Test func aLowercasePersistentIDIsStoredCanonically() async throws {
        let store = TimingFlagStore(directory: tempDirectory())
        try await store.flag(Self.flag(pid: Self.pid.lowercased()))
        #expect(await store.isFlagged(key()))
        #expect(try await store.all().map(\.persistentID) == [Self.pid])
    }

    @Test(arguments: ["", "not-a-persistent-id", "../../etc/passwd"])
    func anInvalidPersistentIDIsRejected(pid: String) async {
        let store = TimingFlagStore(directory: tempDirectory())
        await #expect(throws: TimingFlagStore.StoreError.invalidPersistentID) { try await store.flag(Self.flag(pid: pid)) }
    }

    @Test func flaggingAgainAppendsPositionsKeepingTheLastTen() async throws {
        let store = TimingFlagStore(directory: tempDirectory())
        for second in 1...12 {
            try await store.flag(Self.flag(markedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(second)), positions: [Double(second)]))
        }
        let flags = try await store.all()
        #expect(flags.count == 1)
        #expect(flags.first?.positions == (3...12).map(Double.init))
        #expect(flags.first?.markedAt == Date(timeIntervalSince1970: 1_800_000_012))
    }

    @Test func flagsForOtherLyricsOfTheSameSongAreKeptApart() async throws {
        let store = TimingFlagStore(directory: tempDirectory())
        try await store.flag(Self.flag(hash: Self.hashA, positions: [1]))
        try await store.flag(Self.flag(hash: Self.hashB, positions: [2]))
        #expect(await store.isFlagged(key(Self.hashA)))
        #expect(await store.isFlagged(key(Self.hashB)))
        try await store.clear(key(Self.hashB))
        #expect(await store.isFlagged(key(Self.hashA)))
        #expect(!(await store.isFlagged(key(Self.hashB))))
        #expect(try await store.all().map(\.positions) == [[1]])
    }

    @Test func clearingAnUnflaggedKeyIsANoOp() async throws {
        let store = TimingFlagStore(directory: tempDirectory())
        try await store.clear(key())
        #expect(try await store.all().isEmpty)
    }

    @Test func writingDropsTheOldestFlagsUntilTheFileFits() async throws {
        let directory = tempDirectory()
        let store = TimingFlagStore(directory: directory, maxWriteBytes: 4096)
        let pids = (0..<20).map { String(format: "%016X", $0 + 1) }
        for (offset, pid) in pids.enumerated() {
            try await store.flag(Self.flag(pid: pid, markedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(offset)), anchors: 10))
        }
        let size = try #require(try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(TimingFlagStore.fileName).path)[.size] as? Int)
        #expect(size <= 4096)
        let kept = try await store.all().map(\.persistentID)
        #expect(!kept.isEmpty)
        #expect(kept == Array(pids.suffix(kept.count)).sorted())   // 只丟最舊的
        #expect(await store.isFlagged(TimingFlagKey(persistentID: pids.last!, lyricsHash: Self.hashA)))
    }

    @Test func aSingleFlagTooLargeToFitIsRejectedWithoutTouchingTheFile() async throws {
        let directory = tempDirectory()
        let store = TimingFlagStore(directory: directory, maxWriteBytes: 4096)
        try await store.flag(Self.flag(pid: "00000000000000AA", anchors: 2))
        let url = directory.appendingPathComponent(TimingFlagStore.fileName)
        let before = try Data(contentsOf: url)
        await #expect(throws: TimingFlagStore.StoreError.flagTooLarge) { try await store.flag(Self.flag(anchors: 2000)) }
        #expect(try Data(contentsOf: url) == before)
        #expect(!(await store.isFlagged(key())))
    }

    @Test func theNewFlagIsNeverTheOneTrimmed() async throws {
        let store = TimingFlagStore(directory: tempDirectory(), maxWriteBytes: 4096)
        // 新的那筆時間比既有的都早（時鐘被調過）：仍然保留新的，丟既有最舊者
        for index in 0..<10 {
            try await store.flag(Self.flag(pid: String(format: "%016X", index + 1), markedAt: Date(timeIntervalSince1970: 1_900_000_000 + Double(index)), anchors: 10))
        }
        try await store.flag(Self.flag(markedAt: Date(timeIntervalSince1970: 1_700_000_000), anchors: 10))
        #expect(await store.isFlagged(key()))
    }

    @Test func aStoreFilledToTheRealLimitStillReadsBack() async throws {
        let directory = tempDirectory()
        let store = TimingFlagStore(directory: directory)
        for index in 0..<400 {
            try await store.flag(Self.flag(pid: String(format: "%016X", index + 1), markedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), anchors: 200))
        }
        let size = try #require(try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(TimingFlagStore.fileName).path)[.size] as? Int)
        #expect(size <= TimingFlagStore.maxWriteBytes)
        #expect(TimingFlagStore.maxWriteBytes < TimingFlagStore.maxFileBytes)
        let reread = try await TimingFlagStore(directory: directory).all()
        #expect(reread.count > 1 && reread.count < 400)
        #expect(await TimingFlagStore(directory: directory).isFlagged(TimingFlagKey(persistentID: String(format: "%016X", 400), lyricsHash: Self.hashA)))
    }

    enum Unreadable: String, CaseIterable, Sendable {
        case corruptJSON, newerVersion, oversized, symbolicLink, invalidPersistentID, estimatedSource, tooManyPositions
    }

    @Test(arguments: Unreadable.allCases)
    func anUnreadableFileIsNeitherReadNorOverwritten(kind: Unreadable) async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(TimingFlagStore.fileName)
        switch kind {
        case .corruptJSON:
            try Data("{ not json".utf8).write(to: url)
        case .newerVersion:
            try Data(#"{"schemaVersion": 99, "flags": []}"#.utf8).write(to: url)
        case .oversized:
            try Data(repeating: 0x20, count: TimingFlagStore.maxFileBytes + 1).write(to: url)
        case .symbolicLink:
            let target = directory.appendingPathComponent("elsewhere.json")
            try Data(#"{"schemaVersion": 1, "flags": []}"#.utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        case .invalidPersistentID:
            try Self.file(with: Self.flag(pid: "not-a-pid")).write(to: url)
        case .estimatedSource:
            let flag = Self.flag(pid: "00000000000000BB")
            try Self.file(with: TimingFlag(
                persistentID: flag.persistentID, lyricsHash: flag.lyricsHash, markedAt: flag.markedAt, positions: flag.positions,
                applied: AppliedTiming(source: .estimated, anchors: []), stored: nil, provenance: .storeMissing
            )).write(to: url)
        case .tooManyPositions:
            try Self.file(with: Self.flag(pid: "00000000000000BB", positions: (0..<11).map(Double.init))).write(to: url)
        }
        let before = try? Data(contentsOf: url)
        let store = TimingFlagStore(directory: directory)
        #expect(!(await store.isFlagged(key())))
        await #expect(throws: TimingFlagStore.StoreError.unrecognizedFileOnDisk) { try await store.flag(Self.flag()) }
        await #expect(throws: TimingFlagStore.StoreError.unrecognizedFileOnDisk) { try await store.clear(key()) }
        #expect((try? Data(contentsOf: url)) == before)
    }

    /// 語法合法、內容不合規格的檔（被竄改或他版寫的）：同壞檔，不讀不覆寫（codex R2）
    private static func file(with flag: TimingFlag) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(flag), as: UTF8.self)
        return Data(#"{"schemaVersion": 1, "flags": [\#(json)]}"#.utf8)
    }

    @Test func theInMemoryStoreFollowsTheSameKeyRules() async throws {
        let store = InMemoryTimingFlagStore()
        try await store.flag(Self.flag(hash: Self.hashA))
        #expect(await store.isFlagged(key(Self.hashA)))
        #expect(!(await store.isFlagged(key(Self.hashB))))
        try await store.clear(key(Self.hashA))
        #expect(!(await store.isFlagged(key(Self.hashA))))
    }
}

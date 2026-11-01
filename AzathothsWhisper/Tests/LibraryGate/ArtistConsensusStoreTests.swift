import Foundation
import Testing

@testable import AzathothsWhisper

// 增補計劃 §4.2 快照（v0.5、R5）：共識表是可重建的衍生資料——版本不符、壞檔、指紋不符都當沒有；新掃描直接覆寫
@Suite("Artist consensus store")
struct ArtistConsensusStoreTests {
    private static let builtAt = Date(timeIntervalSince1970: 1_790_000_000)
    private static let table = ["paper harbour": AppleGenreConsensus(genreRows: .init(rowIDs: ["hardrock"], votes: 3, evidence: 4), genericRows: nil)]

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("azw-consensus-\(UUID().uuidString)")
    }

    private var fileName: String { ArtistConsensusStore.fileName }

    @Test func aSavedSnapshotLoadsBack() throws {
        let store = ArtistConsensusStore(directory: directory())
        try store.save(.init(builtAt: Self.builtAt, table: Self.table))
        #expect(store.load() == .init(builtAt: Self.builtAt, table: Self.table))
    }

    @Test func nothingOnDiskMeansNoSnapshot() {
        #expect(ArtistConsensusStore(directory: directory()).load() == nil)
    }

    @Test func aDifferentRowCatalogMakesTheSnapshotUnusable() throws {
        let dir = directory()
        try ArtistConsensusStore(directory: dir, fingerprint: "old").save(.init(builtAt: Self.builtAt, table: Self.table))
        #expect(ArtistConsensusStore(directory: dir, fingerprint: "new").load() == nil)
    }

    @Test func corruptOrNewerFilesAreIgnoredAndOverwritten() throws {
        for content in ["{ not json", #"{"schemaVersion": 99, "builtAt": "2026-10-28T00:00:00Z", "fingerprint": "x", "table": {}}"#] {
            let dir = directory()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(content.utf8).write(to: dir.appendingPathComponent(fileName))
            let store = ArtistConsensusStore(directory: dir)
            #expect(store.load() == nil)
            try store.save(.init(builtAt: Self.builtAt, table: Self.table))
            #expect(store.load()?.table == Self.table, "衍生資料：下次完整掃描直接覆寫")
        }
    }

    @Test func aSymbolicLinkIsNeitherReadNorWritten() throws {
        let dir = directory()
        let elsewhere = directory()
        try ArtistConsensusStore(directory: elsewhere).save(.init(builtAt: Self.builtAt, table: Self.table))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent(fileName), withDestinationURL: elsewhere.appendingPathComponent(fileName))
        let store = ArtistConsensusStore(directory: dir)
        #expect(store.load() == nil)
        #expect(throws: ArtistConsensusStore.StoreError.symbolicLink) { try store.save(.init(builtAt: Self.builtAt, table: [:])) }
    }

    /// 安全評審 L2：被竄改的檔可塞超大、重複或空的列清單，播放時每次都要逐一比對——載入時就丟掉
    @Test func malformedVotesAreDroppedOnLoad() throws {
        let store = ArtistConsensusStore(directory: directory())
        let huge = (0..<1_000).map { "row\($0)" }
        let table = [
            "empty": AppleGenreConsensus(genreRows: .init(rowIDs: [], votes: 2, evidence: 2), genericRows: nil),
            "duplicate": AppleGenreConsensus(genreRows: .init(rowIDs: ["gothic", "gothic"], votes: 2, evidence: 2), genericRows: nil),
            "huge": AppleGenreConsensus(genreRows: .init(rowIDs: huge, votes: 2, evidence: 2), genericRows: nil),
            "mixed": AppleGenreConsensus(genreRows: .init(rowIDs: [], votes: 2, evidence: 2), genericRows: .init(rowIDs: ["pop"], votes: 2, evidence: 3)),
        ]
        try store.save(.init(builtAt: Self.builtAt, table: table))
        let loaded = try #require(store.load()).table
        #expect(loaded == ["mixed": AppleGenreConsensus(genreRows: nil, genericRows: .init(rowIDs: ["pop"], votes: 2, evidence: 3))])
    }

    @Test func anOversizedFileIsIgnored() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: ArtistConsensusStore.maxFileBytes + 1).write(to: dir.appendingPathComponent(fileName))
        #expect(ArtistConsensusStore(directory: dir).load() == nil)
    }

    @Test func theFingerprintCoversRowOrderKeywordsGenericFlagAndPolicyVersion() {
        let rows = SongProfileResolver.keywordRows
        let generic = SongProfileResolver.genericRows
        let base = ArtistConsensusStore.fingerprint(rows: rows, genericRows: generic, policyVersion: 2)
        #expect(base == ArtistConsensusStore.fingerprint(rows: rows, genericRows: generic, policyVersion: 2), "固定格式，可重現")
        #expect(base != ArtistConsensusStore.fingerprint(rows: rows.reversed(), genericRows: generic, policyVersion: 2))
        #expect(base != ArtistConsensusStore.fingerprint(rows: Array(rows.dropLast()), genericRows: generic, policyVersion: 2))
        #expect(base != ArtistConsensusStore.fingerprint(rows: rows, genericRows: generic, policyVersion: 3))
        #expect(base != ArtistConsensusStore.fingerprint(rows: rows + generic, genericRows: [], policyVersion: 2), "通用旗標與所在清單要進指紋")
        #expect(ArtistConsensusStore.currentFingerprint == base || ReadabilityPolicy.version != 2)
    }
}

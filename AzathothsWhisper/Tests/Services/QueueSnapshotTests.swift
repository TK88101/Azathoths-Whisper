import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 D13、AC8、R4-5：Queue.dat 解析（只讀、純解析）
@Suite("QueueSnapshot")
struct QueueSnapshotTests {
    private typealias Item = QueueFixtures.Item

    @Test func orderedModeReadsListInFileOrderWithItemIDs() throws {
        let data = QueueFixtures.queue(list: [Item(-1_145_317_753_999_883_627, itemID: 63203), Item(42, itemID: 63205)])
        let snapshot = try #require(QueueSnapshot.parse(data))

        #expect(snapshot.sequenceKind == .ordered)
        #expect(snapshot.entries == [
            QueueEntry(persistentID: "F01B039225E38295", itemID: 63203),   // 實測：tID 的位元樣式＝persistent ID
            QueueEntry(persistentID: "000000000000002A", itemID: 63205),
        ])
    }

    @Test func shuffledModeReadsShuffledListNotTheOriginalOrder() throws {
        let data = QueueFixtures.queue(
            list: [Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12)],
            shuffled: [Item(3, itemID: 12), Item(1, itemID: 10), Item(2, itemID: 11)],
            shuffleMode: "tracks"
        )
        let snapshot = try #require(QueueSnapshot.parse(data))

        #expect(snapshot.sequenceKind == .shuffled)
        #expect(snapshot.entries.map(\.itemID) == [12, 10, 11])
    }

    /// R4-5：隨機模式缺 shuffledList → 整份不可用，絕不退回未打亂的 list
    @Test func shuffledModeWithoutShuffledListIsUnusable() {
        let data = QueueFixtures.queue(list: [Item(1), Item(2)], shuffled: nil, shuffleMode: "tracks")
        #expect(QueueSnapshot.parse(data) == nil)
    }

    @Test func entriesWithoutTrackIDAreSkipped() throws {
        let data = QueueFixtures.queue(list: [Item(1, itemID: 10), Item(nil, itemID: 11), Item(2, itemID: 12)])
        let snapshot = try #require(QueueSnapshot.parse(data))
        #expect(snapshot.entries.map(\.itemID) == [10, 12])
    }

    @Test func allEntriesWithoutTrackIDIsUnusable() {
        let data = QueueFixtures.queue(list: [Item(nil), Item(nil)])
        #expect(QueueSnapshot.parse(data) == nil)
    }

    @Test func emptyQueueIsAValidEmptySnapshot() throws {
        let snapshot = try #require(QueueSnapshot.parse(QueueFixtures.queue(list: [])))
        #expect(snapshot.entries.isEmpty)
    }

    @Test func multipleSegmentsAreTreatedAsUnusable() {
        #expect(QueueSnapshot.parse(QueueFixtures.queue(list: [Item(1)], segments: 2)) == nil)
    }

    @Test("壞檔與半份檔不可用", arguments: [
        Data(),
        Data("not a plist".utf8),
        Data(#"<?xml version="1.0"?><plist version="1.0"><dict><key>sega</key><array><dict>"#.utf8),
    ])
    func corruptDataIsUnusable(_ data: Data) {
        #expect(QueueSnapshot.parse(data) == nil)
    }

    @Test func contentHashChangesWithOrderAndStaysStableForSameContent() throws {
        let a = try #require(QueueSnapshot.parse(QueueFixtures.queue(list: [Item(1, itemID: 1), Item(2, itemID: 2)])))
        let again = try #require(QueueSnapshot.parse(QueueFixtures.queue(list: [Item(1, itemID: 1), Item(2, itemID: 2)])))
        let swapped = try #require(QueueSnapshot.parse(QueueFixtures.queue(list: [Item(2, itemID: 2), Item(1, itemID: 1)])))

        #expect(a.contentHash == again.contentHash)
        #expect(a.contentHash != swapped.contentHash)
    }

    /// 去識別化的實檔樣本（曲庫隨機、30 項）：選 shuffledList、身分欄位齊
    @Test func realShapeLibraryShuffleSample() throws {
        let url = try GoldenFixtures.fixturesRoot().appendingPathComponent("Queue/queue-library-shuffle.plist")
        let snapshot = try #require(QueueSnapshot.parse(try Data(contentsOf: url)))

        #expect(snapshot.sequenceKind == .shuffled)
        #expect(snapshot.entries.count == 30)
        #expect(snapshot.entries.prefix(3).map(\.persistentID) == ["BF216F8F586D16BB", "24AC3D48CDECFAAB", "69960B910FBFC4BF"])
        #expect(snapshot.entries.prefix(3).map(\.itemID) == [118_004, 133_788, 124_518])
    }
}

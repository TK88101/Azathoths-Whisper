import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 D16、AC8e：History.dat 解析（Music 的「履歴」，由舊到新）
@Suite("HistorySnapshot")
struct HistorySnapshotTests {
    @Test func keepsTheMostRecentEntriesOldestFirst() throws {
        let snapshot = try #require(HistorySnapshot.parse(QueueFixtures.history([1, 2, 3, 4]), keepLast: 2))
        #expect(snapshot.recent == [HistoryEntry(persistentID: QueueFixtures.pid(3)), HistoryEntry(persistentID: QueueFixtures.pid(4))])
    }

    @Test func entriesWithoutLibraryItemIDAreSkipped() throws {
        let snapshot = try #require(HistorySnapshot.parse(QueueFixtures.history([1, nil, 2]), keepLast: 10))
        #expect(snapshot.recent.map(\.persistentID) == [QueueFixtures.pid(1), QueueFixtures.pid(2)])
    }

    @Test("PID 段解析", arguments: [
        ("DBID:0xe4bda0d325c9e675-PID:0xf01b039225e38295-PPID:0x0-PIPID:0x0-IKIND:eSong", String?.some("F01B039225E38295")),
        ("DBID:0x1-PID:0x2a-PPID:0x0", String?.some("000000000000002A")),     // 補足 16 位
        ("PID:0xabc", String?.some("0000000000000ABC")),                      // 在開頭
        ("DBID:0x1-PPID:0x5-PIPID:0x0", String?.none),                        // 只有 PPID：不得誤中
        ("DBID:0x1-PID:0x0-PPID:0x0", String?.none),                          // 0 不是有效 ID
        ("DBID:0x1-PID:0xzz-PPID:0x0", String?.none),
        ("DBID:0x1-PID:0x11111111111111111-PPID:0x0", String?.none),          // 超過 16 位
        ("", String?.none),
    ])
    func persistentIDFromLibraryItemID(identifier: String, expected: String?) {
        #expect(HistorySnapshot.persistentID(fromLibraryItemID: identifier) == expected)
    }

    @Test("壞檔不可用", arguments: [Data(), Data("garbage".utf8)])
    func corruptDataIsUnusable(_ data: Data) {
        #expect(HistorySnapshot.parse(data, keepLast: 10) == nil)
    }

    @Test func contentHashFollowsRecentEntries() throws {
        let a = try #require(HistorySnapshot.parse(QueueFixtures.history([1, 2, 3]), keepLast: 2))
        let olderDiffers = try #require(HistorySnapshot.parse(QueueFixtures.history([9, 2, 3]), keepLast: 2))
        let newer = try #require(HistorySnapshot.parse(QueueFixtures.history([1, 2, 3, 4]), keepLast: 2))

        #expect(a.contentHash == olderDiffers.contentHash, "窗口外的舊項不影響")
        #expect(a.contentHash != newer.contentHash)
    }

    /// 去識別化的實檔樣本：最後一項與佇列樣本的第 0 項是同一首（剛播完、已進履歴）
    @Test func realShapeHistorySample() throws {
        let url = try GoldenFixtures.fixturesRoot().appendingPathComponent("Queue/history-recent.plist")
        let snapshot = try #require(HistorySnapshot.parse(try Data(contentsOf: url), keepLast: 10))
        #expect(snapshot.recent.count == 8)
        #expect(snapshot.recent.last?.persistentID == "BF216F8F586D16BB")
    }
}

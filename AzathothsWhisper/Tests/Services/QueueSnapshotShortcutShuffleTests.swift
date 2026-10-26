import Foundation
import Testing

@testable import AzathothsWhisper

// C′（docs/plans/2026-10-14-yse/s6-61-cprime.md §5、C2）：捷徑起播的佇列（`simp`＋無 `containerCD`）
// 開隨機但 Music 沒寫 `shuffledList`＝實際照 `list` 播。只有這一種形狀放寬，其餘維持 R4-5
/// 參數化用的 plist 字面量（`Any?` 不是 Sendable；同 `QueueFixtures.ModeFields`）
struct PlistValue: @unchecked Sendable, CustomTestStringConvertible {   // 只裝 plist 字面量，建立後不變
    let value: Any?
    init(_ value: Any?) { self.value = value }
    var testDescription: String { value.map { "\(type(of: $0)): \($0)" } ?? "nil" }
}

@Suite("QueueSnapshot C′ 捷徑清單隨機")
struct QueueSnapshotShortcutShuffleTests {
    private typealias Item = QueueFixtures.Item
    private static let spc: Int64 = 7
    private let items = [Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12)]

    /// C′ 正向形狀；各參數可逐一換掉以製造只差一處的反例
    private func shortcutQueue(
        shuffleMode: String = "tracks",
        shuffled: [Item]? = nil,
        modeFields: QueueFixtures.ModeFields? = nil,
        subcKind: Any? = QueueFixtures.simp,
        spcID: Any? = Self.spc,
        spcl: Any? = QueueFixtures.shortcutSpcl(id: Self.spc),
        shuffledListRaw: Any? = nil
    ) -> Data {
        QueueFixtures.queue(
            list: items, shuffled: shuffled, shuffleMode: shuffleMode, modeFields: modeFields,
            subcKind: subcKind, spcID: spcID, spcl: spcl, shuffledListRaw: shuffledListRaw
        )
    }

    // ① 正向
    @Test func shortcutPlaylistWithShuffleOnButNoShuffledListReadsTheList() throws {
        let snapshot = try #require(QueueSnapshot.parse(shortcutQueue()))
        #expect(snapshot.sequenceKind == .ordered)
        #expect(snapshot.entries.map(\.itemID) == [10, 11, 12])
    }

    // ② Music 介面的佇列（trls 或測試預設值）照舊不可用
    @Test("非 simp 的佇列缺 shuffledList 照舊不可用", arguments: [QueueFixtures.trls, Int64(1)])
    func otherQueueKindsStayUnusable(kind: Int64) {
        #expect(QueueSnapshot.parse(shortcutQueue(subcKind: kind)) == nil)
    }

    // ③ simp 但 Music 寫了 shuffledList：照打亂的那支讀
    @Test func shortcutPlaylistWithAShuffledListReadsTheShuffledList() throws {
        let data = shortcutQueue(shuffled: [Item(3, itemID: 12), Item(1, itemID: 10), Item(2, itemID: 11)])
        let snapshot = try #require(QueueSnapshot.parse(data))
        #expect(snapshot.sequenceKind == .shuffled)
        #expect(snapshot.entries.map(\.itemID) == [12, 10, 11])
    }

    // ④ shuffledList 壞型別：鍵存在＝不走 C′，也讀不出打亂序列
    @Test("shuffledList 壞型別不可用", arguments: [PlistValue("garbage"), PlistValue([Int]())])
    func malformedShuffledListIsUnusable(raw: PlistValue) {
        #expect(QueueSnapshot.parse(shortcutQueue(shuffledListRaw: raw.value)) == nil)
    }

    // ⑤ 其他非 off 的隨機值不放寬
    @Test func otherShuffleModesAreNotRelaxed() {
        #expect(QueueSnapshot.parse(shortcutQueue(shuffleMode: "albums")) == nil)
    }

    // ⑥ subcKind 必須是 plist 整數：字串、缺失、浮點（含整數值的浮點）、布林都不算
    @Test("subcKind 非整數不放寬", arguments: [
        PlistValue("1936289136"), PlistValue(nil), PlistValue(1936289136.0), PlistValue(1936289136.5), PlistValue(true),
    ])
    func subcKindMustBeAPlistInteger(value: PlistValue) {
        #expect(QueueSnapshot.parse(shortcutQueue(subcKind: value.value)) == nil)
    }

    // ⑥ 溢位：超出 Int64 的 <integer> 不得命中 simp
    @Test func overflowingSubcKindIsNotRelaxed() throws {
        let sentinel: Int64 = 424_242_424_242
        let xml = try #require(String(data: shortcutQueue(subcKind: sentinel), encoding: .utf8))
        let overflow = xml.replacingOccurrences(of: "<integer>\(sentinel)</integer>", with: "<integer>99999999999999999999999</integer>")
        #expect(overflow != xml)
        #expect(QueueSnapshot.parse(Data(overflow.utf8))?.sequenceKind != .ordered)
    }

    // ⑦ 兩處 shuffleMode 不一致
    @Test func inconsistentShuffleModeIsUnusable() {
        #expect(QueueSnapshot.parse(shortcutQueue(modeFields: .init(items: "tracks", root: "off"))) == nil)
    }

    // ⑦′ 起播來源必須是捷徑形狀：恰 1 筆、字典值、id＝spcID、沒有 containerCD
    @Test("spcl 不符捷徑形狀不放寬", arguments: [
        PlistValue(QueueFixtures.musicAppSpcl(id: 7)),                                   // Music 介面起播
        PlistValue(nil),                                                                   // 缺失
        PlistValue("not a dictionary"),                                                    // 非字典
        PlistValue([String: Any]()),                                                       // 空
        PlistValue(["1": ["id": Int64(7)], "2": ["id": Int64(7)]]),                                  // 2 筆（即使皆合法）
        PlistValue(["1": "not a dictionary"]),                                             // 值非字典
        PlistValue(["1": ["other": 1]]),                                                   // 缺 id
        PlistValue(["1": ["id": "7"]]),                                                    // id 為字串
        PlistValue(["1": ["id": true]]),                                                   // id 為布林
        PlistValue(["1": ["id": 7.0]]),                                                    // id 為浮點
        PlistValue(QueueFixtures.shortcutSpcl(id: 8)),                               // id ≠ spcID
    ])
    func sourceMustLookLikeAShortcutStart(spcl: PlistValue) {
        #expect(QueueSnapshot.parse(shortcutQueue(spcl: spcl.value)) == nil)
    }

    @Test("segment 的 spcID 必須是整數", arguments: [PlistValue(nil), PlistValue("7"), PlistValue(7.0), PlistValue(true)])
    func segmentSourceIDMustBeAPlistInteger(spcID: PlistValue) {
        #expect(QueueSnapshot.parse(shortcutQueue(spcID: spcID.value)) == nil)
    }

    // ⑧ 同一捷徑清單 off→tracks：內容雜湊不變（Cover Flow 不重建）
    @Test func togglingShuffleOnTheShortcutPlaylistKeepsTheContentHash() throws {
        let off = try #require(QueueSnapshot.parse(shortcutQueue(shuffleMode: "off")))
        let on = try #require(QueueSnapshot.parse(shortcutQueue()))
        #expect(off.contentHash == on.contentHash)
    }

    // ⑧ QueueSession：位置與卡 ID 在 off→tracks 後不變
    @Test func togglingShuffleOnKeepsTheQueueSessionPosition() throws {
        let off = try #require(QueueSnapshot.parse(shortcutQueue(shuffleMode: "off")))
        let on = try #require(QueueSnapshot.parse(shortcutQueue()))
        let before = QueueSession().applying(off).resolvingCurrent(persistentID: QueueFixtures.pid(2), isRealChange: true)
        let after = before.applying(on)
        #expect(before.currentIndex == 1)
        #expect(after.currentIndex == 1)
        #expect((0..<3).map(after.cardID(at:)) == (0..<3).map(before.cardID(at:)))
    }

    // ⑨ 去識別化的實檔樣本（spike s3-4：iPad 點歌後開隨機）
    @Test func realShapeShortcutShuffleSample() throws {
        let url = try GoldenFixtures.fixturesRoot().appendingPathComponent("Queue/queue-shortcut-shuffle-tracks.plist")
        let snapshot = try #require(QueueSnapshot.parse(try Data(contentsOf: url)))
        #expect(snapshot.sequenceKind == .ordered)
        #expect(snapshot.entries.count == 13)
        #expect(snapshot.entries.prefix(3).map(\.itemID) == [63_364, 63_365, 63_366])
    }
}

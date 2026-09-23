import Testing

@testable import AzathothsWhisper

// 計劃 Q4 畫面的純邏輯部分（畫面本身由 LyricsFlowUITests 驗）：
// 可點判定的容差（D6、N2）、卡片徽章（AC7）、把手刻度、狀態字的 i18n 鍵（§9.5）
@Suite("LyricsFlowPresentation")
struct LyricsFlowPresentationTests {
    private let geometry = CoverFlowGeometry(itemWidth: 260)

    // MARK: D6 可點＝播放中 ∧ 幾何正中（容差 |d| ≤ 0.2）

    @Test("正中容差", arguments: [
        (0.0, true), (0.2, true), (-0.2, true), (0.21, false), (-0.21, false),
    ])
    func centredWithinTolerance(distance: Double, expected: Bool) {
        #expect(geometry.isCentered(forDistance: distance) == expected)
    }

    /// 捲動跨兩卡中點時沒有任何卡可點：相鄰兩卡相距 0.58 個卡寬，中點兩側各 0.29
    @Test func noCardIsCentredHalfwayBetweenTwo() {
        let halfStride = (1 - 0.42) / 2
        #expect(!geometry.isCentered(forDistance: halfStride))
        #expect(!geometry.isCentered(forDistance: -halfStride))
    }

    // MARK: AC7 徽章

    @Test("徽章符號", arguments: [
        (LyricsStatus.present, "✓"), (.missing, "✗"), (.markedNone, "—"), (.unknown, "?"),
    ])
    func badgeSymbol(status: LyricsStatus, symbol: String) {
        #expect(LyricsBadge.text(for: status, trackNumber: nil, isCurrent: false) == symbol)
    }

    @Test func currentCardBadgeCarriesTheTrackNumber() {
        #expect(LyricsBadge.text(for: .present, trackNumber: 7, isCurrent: true) == "✓ 07")
        #expect(LyricsBadge.text(for: .missing, trackNumber: 12, isCurrent: true) == "✗ 12")
        #expect(LyricsBadge.text(for: .present, trackNumber: 0, isCurrent: true) == "✓", "沒有軌號就只顯示符號")
        #expect(LyricsBadge.text(for: .present, trackNumber: 7, isCurrent: false) == "✓", "非中心卡不帶軌號")
    }

    @Test("狀態字的 i18n 鍵", arguments: [
        (LyricsStatus.present, "lyrics_status_present"), (.missing, "lyrics_status_missing"),
        (.markedNone, "lyrics_status_marked"), (.unknown, "lyrics_status_unknown"),
    ])
    func statusKey(status: LyricsStatus, key: String) {
        #expect(LyricsBadge.statusKey(for: status) == key)
    }

    // MARK: 把手刻度（設計稿：播過的較短、接下來的較長、中心白色；缺詞紅、已標記暗灰）

    @Test func handleTicksFollowTheDeck() {
        let cards = [
            DeckCard(id: "h:A#0", persistentID: "A", side: .played),
            DeckCard(id: "q:0:1", persistentID: "B", side: .current),
            DeckCard(id: "q:0:2", persistentID: "C", side: .upcoming),
            DeckCard(id: "q:0:3", persistentID: "D", side: .upcoming),
        ]
        let statuses: [String: LyricsStatus] = ["A": .present, "B": .missing, "C": .missing, "D": .markedNone]
        let ticks = LyricsFlowHandle.ticks(cards: cards) { statuses[$0.persistentID] ?? .unknown }
        #expect(ticks == [
            HandleTick(side: .played, tone: .present),
            HandleTick(side: .current, tone: .missing),
            HandleTick(side: .upcoming, tone: .missing),
            HandleTick(side: .upcoming, tone: .marked),
        ])
    }
}

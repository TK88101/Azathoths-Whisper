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

    /// 使用者 2026-09-23 拍板：正中左側的卡，右上角被較靠中心的卡蓋住 → 徽章放左上角（露出的外側）
    @Test func badgeSitsOnTheExposedCornerRelativeToTheCentre() {
        let ids = ["h1", "h0", "now", "q1", "q2"]
        #expect(ids.map { LyricsBadge.corner(of: $0, in: ids, centerID: "now") }
            == [.leading, .leading, .trailing, .trailing, .trailing])
    }

    @Test func badgeCornerFollowsTheCentreWhileBrowsing() {
        let ids = ["h1", "h0", "now", "q1", "q2"]
        #expect(LyricsBadge.corner(of: "now", in: ids, centerID: "q1") == .leading, "播放卡被瀏覽移到左側")
        #expect(LyricsBadge.corner(of: "q1", in: ids, centerID: "q1") == .trailing)
    }

    @Test func badgeCornerDefaultsToTrailingWithoutACentre() {
        let ids = ["h1", "now"]
        #expect(LyricsBadge.corner(of: "h1", in: ids, centerID: nil) == .trailing)
        #expect(LyricsBadge.corner(of: "gone", in: ids, centerID: "now") == .trailing, "不在牌組的卡")
        #expect(LyricsBadge.corner(of: "h1", in: ids, centerID: "gone") == .trailing, "中心不在牌組")
    }

    @Test("狀態字的 i18n 鍵", arguments: [
        (LyricsStatus.present, "lyrics_status_present"), (.missing, "lyrics_status_missing"),
        (.markedNone, "lyrics_status_marked"), (.unknown, "lyrics_status_unknown"),
    ])
    func statusKey(status: LyricsStatus, key: String) {
        #expect(LyricsBadge.statusKey(for: status) == key)
    }

    // MARK: 把手刻度（設計稿：播過的較短、接下來的較長、中心白色；缺詞紅、已標記暗灰）

    /// 把手刻度的外觀（設計稿：中心白色發光、播過的短、接下來的長；缺詞紅、已標記暗、其餘淡）。只比意義，不比 Color
    @Test("刻度外觀＝位置 × 歌詞狀態", arguments: [
        (DeckCard.Side.current, LyricsBadge.Tone.present, TickAppearance(width: 3, height: 20, palette: .bright, glows: true)),
        (.current, .missing, TickAppearance(width: 3, height: 20, palette: .bright, glows: true)),
        (.current, .marked, TickAppearance(width: 3, height: 20, palette: .bright, glows: true)),
        (.current, .unknown, TickAppearance(width: 3, height: 20, palette: .bright, glows: true)),
        (.played, .present, TickAppearance(width: 2, height: 8, palette: .muted, glows: false)),
        (.played, .missing, TickAppearance(width: 2, height: 8, palette: .danger, glows: false)),
        (.played, .marked, TickAppearance(width: 2, height: 8, palette: .dim, glows: false)),
        (.played, .unknown, TickAppearance(width: 2, height: 8, palette: .muted, glows: false)),
        (.upcoming, .present, TickAppearance(width: 2, height: 11, palette: .muted, glows: false)),
        (.upcoming, .missing, TickAppearance(width: 2, height: 11, palette: .danger, glows: false)),
        (.upcoming, .marked, TickAppearance(width: 2, height: 11, palette: .dim, glows: false)),
        (.upcoming, .unknown, TickAppearance(width: 2, height: 11, palette: .muted, glows: false)),
    ])
    func tickAppearance(side: DeckCard.Side, tone: LyricsBadge.Tone, expected: TickAppearance) {
        #expect(HandleTick(side: side, tone: tone).appearance == expected)
    }

    /// D5／U6：升回延遲＝彩帶名義壽命，與 ConfettiView 的步進共用同一組常數
    @MainActor @Test func riseDelayIsTheConfettiLifetime() {
        #expect(LyricsFlowModel.riseDelay == ConfettiTiming.frameInterval * ConfettiTiming.ticks)
        #expect(LyricsFlowModel.riseDelay == .milliseconds(3200))
    }

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

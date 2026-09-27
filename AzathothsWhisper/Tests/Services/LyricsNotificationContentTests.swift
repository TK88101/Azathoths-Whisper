import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 2026-09-26-lyrics-notification §3、§4.1：通知文案是純函式，版式＝樣式 A（使用者 2026-09-26 拍板）。
// title＝app_title（隨 App 語言）、subtitle＝藝人 · 專輯、body＝結果。三語以對應 .lproj 注入驗證。
@Suite("LyricsNotificationContent")
struct LyricsNotificationContentTests {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func summary(
        album: String = "Blackwater Park",
        trackCount: Int = 8,
        succeeded: [String],
        failed: [String] = []
    ) -> BatchWriteSummary {
        BatchWriteSummary(
            artist: "Opeth", album: album, albumTrackCount: trackCount,
            succeeded: succeeded, failed: failed
        )
    }

    private let eight = [
        "The Leper Affinity", "Bleak", "Harvest", "The Drapery Falls",
        "Dirge for November", "The Funeral Portrait", "Patterns in the Ivy", "Blackwater Park",
    ]

    // MARK: - 單首（§3.1）

    @Test func singleUsesAppTitleSubtitleAndSongInBody() throws {
        let payload = LyricsNotificationContent.single(
            artist: "Opeth", title: "The Drapery Falls", album: "Blackwater Park", bundle: try bundle("zh-Hant")
        )
        #expect(payload == NotificationPayload(
            title: "阿撒托斯的低語",
            subtitle: "Opeth · 《Blackwater Park》",
            body: "「The Drapery Falls」歌詞寫入成功",
            threadID: "Blackwater Park"
        ))
    }

    @Test("單首三語", arguments: [
        ("en", "Azathoth's Whisper", "Opeth · Blackwater Park", "Lyrics saved for \"The Drapery Falls\""),
        ("ja", "アザトースの囁き", "Opeth · 『Blackwater Park』", "「The Drapery Falls」の歌詞を書き込みました"),
    ])
    func singleIsLocalized(language: String, title: String, subtitle: String, body: String) throws {
        let payload = LyricsNotificationContent.single(
            artist: "Opeth", title: "The Drapery Falls", album: "Blackwater Park", bundle: try bundle(language)
        )
        #expect(payload.title == title)
        #expect(payload.subtitle == subtitle)
        #expect(payload.body == body)
    }

    @Test func blankAlbumLeavesOnlyArtistInSubtitleAndNoThread() throws {
        let payload = LyricsNotificationContent.single(
            artist: "Opeth", title: "Harvest", album: "  ", bundle: try bundle("zh-Hant")
        )
        #expect(payload.subtitle == "Opeth")
        #expect(payload.threadID == nil)
    }

    // 歌名只作參數，不進格式字串
    @Test func percentAndQuotesInTitleAreLiteral() throws {
        let payload = LyricsNotificationContent.single(
            artist: "A", title: "100% \"Pure\" %@ %lld", album: "B", bundle: try bundle("en")
        )
        #expect(payload.body == "Lyrics saved for \"100% \"Pure\" %@ %lld\"")
    }

    // MARK: - Batch 匯總（§3.2）

    @Test func wholeAlbumSucceeded() throws {
        let payload = try #require(LyricsNotificationContent.batch(summary(succeeded: eight), bundle: try bundle("zh-Hant")))
        #expect(payload.title == "阿撒托斯的低語")
        #expect(payload.subtitle == "Opeth · 《Blackwater Park》")
        #expect(payload.body == "整張專輯 8 首歌詞寫入成功")
        #expect(payload.threadID == "Blackwater Park")
    }

    @Test func someSucceededListsAtMostThreeThenRemainder() throws {
        let five = Array(eight.prefix(5))
        let payload = try #require(LyricsNotificationContent.batch(summary(succeeded: five), bundle: try bundle("zh-Hant")))
        #expect(payload.body == "5 首歌詞寫入成功：The Leper Affinity、Bleak、Harvest 及另外 2 首")
    }

    @Test func someSucceededWithinThreeListsAllWithoutRemainder() throws {
        let payload = try #require(LyricsNotificationContent.batch(
            summary(succeeded: ["Bleak", "Harvest"]), bundle: try bundle("en")
        ))
        #expect(payload.body == "Lyrics saved for 2 tracks: Bleak, Harvest")
    }

    @Test func partialFailureListsFailedTracks() throws {
        let payload = try #require(LyricsNotificationContent.batch(
            summary(succeeded: Array(eight.prefix(6)), failed: ["Dirge for November", "The Funeral Portrait"]),
            bundle: try bundle("zh-Hant")
        ))
        #expect(payload.body == "6 / 8 首寫入成功，2 首失敗：Dirge for November、The Funeral Portrait")
    }

    @Test func partialFailureTruncatesFailedListAfterThree() throws {
        let payload = try #require(LyricsNotificationContent.batch(
            summary(succeeded: ["A"], failed: ["B", "C", "D", "E", "F"]),
            bundle: try bundle("en")
        ))
        #expect(payload.body == "1/6 saved, 5 failed: B, C, D and 2 more")
    }

    @Test func allFailed() throws {
        let payload = try #require(LyricsNotificationContent.batch(
            summary(succeeded: [], failed: eight), bundle: try bundle("ja")
        ))
        #expect(payload.body == "8 曲すべての書き込みに失敗しました")
    }

    // 「整張專輯」只在寫入數＝專輯曲目數且無失敗時成立
    @Test func succeededCountBelowAlbumSizeIsNotWholeAlbum() throws {
        let payload = try #require(LyricsNotificationContent.batch(
            summary(trackCount: 9, succeeded: eight), bundle: try bundle("en")
        ))
        #expect(payload.body == "Lyrics saved for 8 tracks: The Leper Affinity, Bleak, Harvest and 5 more")
    }

    @Test func nothingWrittenPostsNothing() throws {
        #expect(LyricsNotificationContent.batch(summary(succeeded: []), bundle: try bundle("en")) == nil)
    }
}

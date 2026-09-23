import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 D14／AC8d：卡片詳情以 persistentID 批次讀取（S6：一批 21 首約 5 AE／51ms）＋快取
@Suite("CardDetailsReader")
struct CardDetailsReaderTests {
    private func details(_ id: String, lyrics: String? = "") -> TrackDetails {
        TrackDetails(persistentID: id, artist: "A-\(id)", title: "T-\(id)", album: "L", discNumber: 1, trackNumber: 1, lyrics: lyrics)
    }

    @Test func fetchesMissingDetailsInOneBatch() async {
        let music = MockMusicClient()
        await music.setTrackDetails([details("P1"), details("P2"), details("P3")])
        let reader = CardDetailsReader(music: music)

        let result = await reader.details(for: ["P1", "P2", "P3"])

        #expect(Set(result.keys) == ["P1", "P2", "P3"])
        #expect(await music.trackDetailsRequests == [["P1", "P2", "P3"]])
    }

    @Test func cachedDetailsAreNotRefetched() async {
        let music = MockMusicClient()
        await music.setTrackDetails([details("P1"), details("P2")])
        let reader = CardDetailsReader(music: music)

        _ = await reader.details(for: ["P1"])
        let result = await reader.details(for: ["P1", "P2"])

        #expect(Set(result.keys) == ["P1", "P2"])
        #expect(await music.trackDetailsRequests == [["P1"], ["P2"]], "第二批只問沒快取的")
    }

    @Test func duplicateIDsAreRequestedOnce() async {
        let music = MockMusicClient()
        await music.setTrackDetails([details("P1")])
        let reader = CardDetailsReader(music: music)

        _ = await reader.details(for: ["P1", "P1", "P1"])
        #expect(await music.trackDetailsRequests == [["P1"]])
    }

    @Test func updatingLyricsChangesTheCachedStatusSource() async {
        let music = MockMusicClient()
        await music.setTrackDetails([details("P1", lyrics: "")])
        let reader = CardDetailsReader(music: music)
        _ = await reader.details(for: ["P1"])

        await reader.updateLyrics("new words", for: "P1")
        let result = await reader.details(for: ["P1"])

        #expect(result["P1"]?.lyrics == "new words")
        #expect(await music.trackDetailsRequests.count == 1, "更新快取不得重讀")
    }

    @Test func failureYieldsNothingAndIsNotCached() async {
        let music = MockMusicClient()
        await music.setTrackDetailsOutcome(.failure(.scriptingFailure("boom")))
        let reader = CardDetailsReader(music: music)

        #expect(await reader.details(for: ["P1"]).isEmpty)
        await music.setTrackDetailsOutcome(nil)
        await music.setTrackDetails([details("P1")])
        #expect(await reader.details(for: ["P1"]).keys.contains("P1"), "失敗不入快取，下次重試")
    }

    @Test func emptyIDsAreIgnored() async {
        let music = MockMusicClient()
        let reader = CardDetailsReader(music: music)
        #expect(await reader.details(for: ["", ""]).isEmpty)
        #expect(await music.trackDetailsRequests.isEmpty)
    }
}

import Foundation
import Testing

@testable import AzathothsWhisper

// 項 1：genre／duration／playerPosition 的唯讀契約（A1 計劃 §3.1）
@Suite("PlaybackPosition")
struct PlaybackPositionTests {
    static let before = ContinuousClock.now
    static let after = before.advanced(by: .milliseconds(40))

    private func make(state: PlayerState = .playing, idBefore: String? = "PID1", seconds: Double? = 12.5, idAfter: String? = "PID1") -> PlaybackPosition? {
        PlaybackPosition.make(state: state, idBefore: idBefore, seconds: seconds, idAfter: idAfter, before: Self.before, after: Self.after)
    }

    @Test func readAtIsTheMidpointOfThePositionReadAndRoundTripIsItsLength() throws {
        let position = try #require(make())
        #expect(position.persistentID == "PID1")
        #expect(position.seconds == 12.5)
        #expect(position.state == .playing)
        #expect(position.readAt == Self.before.advanced(by: .milliseconds(20)))
        #expect(position.roundTrip == .milliseconds(40))
    }

    @Test func pausedIsAReading() {
        #expect(make(state: .paused)?.state == .paused)
    }

    @Test func stoppedOrOtherStatesAreNoReading() {
        #expect(make(state: .stopped) == nil)
        #expect(make(state: .other("kPSF")) == nil)
    }

    /// 兩次 ID 不同＝讀的途中換了歌：位置不知道屬於哪首，整筆丟掉（Codex R1）
    @Test func trackChangingMidReadIsNoReading() {
        #expect(make(idBefore: "PID1", idAfter: "PID2") == nil)
    }

    @Test func missingOrEmptyValuesAreNoReading() {
        #expect(make(idBefore: nil) == nil)
        #expect(make(idBefore: "", idAfter: "") == nil)
        #expect(make(seconds: nil) == nil)
        #expect(make(seconds: .nan) == nil)
        #expect(make(seconds: -1) == nil)
    }
}

@Suite("Music read contract")
struct MusicReadContractTests {
    @Test func nowPlayingReadDefaultsToUnknownMetadata() {
        let read = NowPlayingRead(track: .fixture(), lyrics: "x")
        #expect(read.metadata == .unknown)
        #expect(TrackMetadata.unknown.genre == nil && TrackMetadata.unknown.duration == nil)
    }

    @Test func trackChangedDefaultsToUnknownMetadata() {
        let event = PlaybackEvent.trackChanged(.fixture(), existingLyrics: "x")
        #expect(event == .trackChanged(.fixture(), existingLyrics: "x", metadata: .unknown))
        #expect(event != .trackChanged(.fixture(), existingLyrics: "x", metadata: TrackMetadata(genre: "Metal", duration: 300)))
    }

    @Test func trackDetailsReadsGenreAndDurationColumns() {
        let columns: [[Any]] = [["PID1"], ["A"], ["T"], ["Al"], [NSNumber(value: 1)], [NSNumber(value: 2)], ["l"], ["Black Metal"], [NSNumber(value: 245.5)]]
        let details = TrackDetails.fromColumns(columns)
        #expect(details.first?.genre == "Black Metal")
        #expect(details.first?.duration == 245.5)
    }

    @Test func trackDetailsDefaultsMetadataToUnknown() {
        let details = TrackDetails(persistentID: "P", artist: "", title: "", album: "", discNumber: 0, trackNumber: 0, lyrics: nil)
        #expect(details.genre == nil && details.duration == nil)
    }

    /// 欄數不對（舊的 7 欄）＝批次不完整，整批不採用
    @Test func theOldSevenColumnShapeIsRejected() {
        let columns: [[Any]] = [["PID1"], ["A"], ["T"], ["Al"], [NSNumber(value: 1)], [NSNumber(value: 2)], ["l"]]
        #expect(TrackDetails.fromColumns(columns).isEmpty)
    }
}

// 只改歌詞的重組不得把 genre／曲長清掉（codex review R3 P2）
@Suite("TrackDetails lyrics replacement")
struct TrackDetailsLyricsReplacementTests {
    static let withMetadata = TrackDetails(
        persistentID: "P1", artist: "A", title: "T", album: "Al", discNumber: 1, trackNumber: 2,
        lyrics: "", genre: "Black Metal", duration: 245
    )

    @Test func replacingLyricsKeepsEverythingElse() {
        let replaced = Self.withMetadata.replacingLyrics("Lanterns over the river")
        #expect(replaced.lyrics == "Lanterns over the river")
        #expect(replaced.genre == "Black Metal")
        #expect(replaced.duration == 245)
        #expect(replaced.replacingLyrics("") == Self.withMetadata)
    }

    @Test func aCachedCardKeepsItsMetadataAfterAWrite() async {
        let music = MockMusicClient()
        await music.setTrackDetails([Self.withMetadata])
        let reader = CardDetailsReader(music: music)
        _ = await reader.details(for: ["P1"])

        await reader.updateLyrics("Lanterns over the river", for: "P1")

        let cached = await reader.details(for: ["P1"])["P1"]
        #expect(cached?.lyrics == "Lanterns over the river")
        #expect(cached?.genre == "Black Metal")
        #expect(cached?.duration == 245)
    }
}

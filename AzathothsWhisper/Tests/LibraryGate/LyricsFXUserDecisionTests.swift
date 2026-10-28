import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 計劃 §4.3：使用者決定沿用定格規則——播放途中才下的決定，下一次播放才生效。歌詞自編
@MainActor
@Suite("LyricsFX user decisions")
struct LyricsFXUserDecisionTests {
    static let lyrics = "[Verse]\nLanterns over the river\nAsh in the wind"
    /// 沒有任何列認得的虛構曲風：未決定前是素面
    static let unknown = TrackMetadata(genre: "Glimmerwave Foo", duration: 200)

    final class Box { var decision: ArtistDecision.Choice? }

    private func model() -> LyricsFXViewModel {
        LyricsFXViewModel(positionClock: PlaybackPositionClock(music: MockMusicClient(), pollClock: GatedPollClock()), nonceSource: SequenceNonceSource())
    }

    private func tags(_ recipe: SessionRecipe) -> Set<FXTag>? {
        if case .composed(let value) = recipe { return value.profile.tags }
        return nil
    }

    @Test func aDecisionMadeMidSessionAppliesFromTheNextPlay() {
        let box = Box()
        let vm = model()
        vm.artistDecision = { _ in box.decision }
        let track = TrackInfo.fixture(id: "A", artist: "Velvet Lanterns")
        vm.handle(.trackChanged(track, existingLyrics: Self.lyrics, metadata: Self.unknown))
        #expect(tags(vm.recipe) == nil, "未決定：素面")

        box.decision = .style(rowID: "industrial")
        vm.handle(.metadataChanged(persistentID: "A", metadata: TrackMetadata(genre: "Glimmerwave Foo", duration: 201)))
        #expect(tags(vm.recipe) == nil, "同一次播放不重組")

        vm.handle(.notPlaying)
        vm.handle(.trackChanged(track, existingLyrics: Self.lyrics, metadata: Self.unknown))
        #expect(tags(vm.recipe) == [.genIndustrial], "下一次播放套使用者指定的列")
    }

    @Test func theCallbackGetsTheTrackArtist() {
        var asked: [String] = []
        let vm = model()
        vm.artistDecision = { artist in asked.append(artist); return nil }
        vm.handle(.trackChanged(.fixture(id: "A", artist: "Velvet Lanterns"), existingLyrics: Self.lyrics, metadata: Self.unknown))
        #expect(asked.contains("Velvet Lanterns"))
    }
}

import Foundation
import Testing

@testable import AzathothsWhisper

/// 依序吐出固定的 nonce，並記下被要了幾次
final class SequenceNonceSource: FXNonceSource, @unchecked Sendable {
    private(set) var draws = 0
    private let values: [UInt64]

    init(_ values: [UInt64] = [11, 22, 33, 44, 55]) {
        self.values = values
    }

    func next() -> UInt64 {
        defer { draws += 1 }
        return values[draws % values.count]
    }
}

// B1 計劃 §3.7：session recipe——換曲或停播後再播才重抽；一次播放內（改詞、寫入、metadata 補讀）不換。歌詞為編造句
@MainActor
@Suite("LyricsFX session recipe")
struct LyricsFXRecipeTests {
    static let lyrics = "[Verse]\nLanterns over the river\nAsh in the wind"
    static let black = TrackMetadata(genre: "Black Metal", duration: 200)
    static let symphonic = TrackMetadata(genre: "Symphonic Metal", duration: 200)

    private func model(_ nonces: SequenceNonceSource = SequenceNonceSource()) -> LyricsFXViewModel {
        let clock = PlaybackPositionClock(music: MockMusicClient(), pollClock: GatedPollClock())
        return LyricsFXViewModel(positionClock: clock, nonceSource: nonces)
    }

    private func composed(_ recipe: SessionRecipe) -> ComposedRecipe? {
        if case .composed(let value) = recipe { return value }
        return nil
    }

    @Test func aBlackMetalTrackGetsAComposedRecipe() throws {
        let vm = model()
        vm.handle(.trackChanged(.fixture(id: "A"), existingLyrics: Self.lyrics, metadata: Self.black))
        let recipe = try #require(composed(vm.recipe))
        #expect(recipe.profile.tags == [.black])
    }

    @Test func anUnknownGenreSettlesAsMonoAndStaysMono() {
        let vm = model()
        vm.handle(.trackChanged(.fixture(id: "A"), existingLyrics: Self.lyrics, metadata: TrackMetadata(genre: "Polka", duration: 200)))
        #expect(vm.recipe == .mono)
        vm.handle(.metadataChanged(persistentID: "A", metadata: Self.black))
        #expect(vm.recipe == .mono, "已定格")
    }

    @Test func aLateGenreSettlesTheRecipeOnceThenItIsFixed() throws {
        let vm = model()
        vm.handle(.trackChanged(.fixture(id: "A"), existingLyrics: Self.lyrics, metadata: .unknown))
        #expect(vm.recipe == .mono, "genre 未讀到：先畫 mono")
        vm.handle(.metadataChanged(persistentID: "A", metadata: Self.black))
        let settled = try #require(composed(vm.recipe))
        vm.handle(.metadataChanged(persistentID: "A", metadata: Self.symphonic))
        #expect(composed(vm.recipe) == settled)
    }

    @Test func editsWritesAndForcedRereadsKeepTheRecipe() throws {
        let vm = model()
        vm.handle(.trackChanged(.fixture(id: "A"), existingLyrics: Self.lyrics, metadata: Self.black))
        let first = try #require(composed(vm.recipe))
        vm.handle(.lyricsChanged(persistentID: "A", lyrics: "Paper boats at dawn"))
        vm.lyricsUpdated(persistentID: "A", text: "Quiet harbor tonight")
        vm.handle(.trackChanged(.fixture(id: "A"), existingLyrics: "Morning tide", metadata: Self.symphonic))
        #expect(composed(vm.recipe) == first)
    }

    @Test func aNewTrackDrawsANewNonce() {
        let nonces = SequenceNonceSource()
        let vm = model(nonces)
        vm.handle(.trackChanged(.fixture(id: "A"), existingLyrics: Self.lyrics, metadata: Self.black))
        vm.handle(.trackChanged(.fixture(id: "B"), existingLyrics: Self.lyrics, metadata: Self.black))
        #expect(nonces.draws == 2)
    }

    @Test func playingTheSameTrackAgainAfterStoppingIsANewSession() {
        let nonces = SequenceNonceSource()
        let vm = model(nonces)
        vm.handle(.trackChanged(.fixture(id: "A"), existingLyrics: Self.lyrics, metadata: Self.black))
        vm.handle(.notPlaying)
        #expect(vm.recipe == .mono)
        vm.handle(.trackChanged(.fixture(id: "A"), existingLyrics: Self.lyrics, metadata: Self.black))
        #expect(nonces.draws == 2)
        #expect(composed(vm.recipe) != nil)
    }

    @Test func tracksWithoutAPersistentIDDoNotShareASeed() throws {
        let vm = model(SequenceNonceSource([7]))
        vm.handle(.trackChanged(.fixture(id: "", title: "Lanterns"), existingLyrics: Self.lyrics, metadata: Self.black))
        let first = try #require(composed(vm.recipe))
        vm.handle(.trackChanged(.fixture(id: "", title: "Harbor"), existingLyrics: Self.lyrics, metadata: Self.black))
        let second = try #require(composed(vm.recipe))
        #expect(first.seed != second.seed)
    }

    @Test func aKnownBandNeedsNoGenre() {
        let vm = model()
        vm.handle(.trackChanged(.fixture(id: "A", artist: "Mayhem"), existingLyrics: Self.lyrics, metadata: .unknown))
        #expect(composed(vm.recipe)?.profile.tags == [.black])
    }

    @Test func theSameNonceAndTrackReproduceTheRecipe() {
        let first = model(SequenceNonceSource([5]))
        let second = model(SequenceNonceSource([5]))
        for vm in [first, second] {
            vm.handle(.trackChanged(.fixture(id: "A"), existingLyrics: Self.lyrics, metadata: Self.black))
        }
        #expect(first.recipe == second.recipe)
    }

    /// simcodex R1：「同一首」只有 signature 一個定義——沒有 persistentID 的新曲不得沿用前一首的 genre
    @Test func aNewTrackWithoutAnIDDoesNotInheritThePreviousGenre() {
        let vm = model()
        vm.handle(.trackChanged(.fixture(id: "", title: "Lanterns"), existingLyrics: Self.lyrics, metadata: Self.black))
        #expect(composed(vm.recipe) != nil)
        vm.handle(.trackChanged(.fixture(id: "", title: "Harbor"), existingLyrics: Self.lyrics, metadata: .unknown))
        #expect(vm.recipe == .mono, "新曲的 genre 還沒讀到：應等它，而不是用上一首的黑金屬")
    }

    /// 使用者：「每次都給我感覺變了」「全部都要隨機起來」——同一首歌連續播放，每一槽都與上一次不同（黑金屬每槽都有兩個以上候選）
    @Test func theSameSongNeverRepeatsAnySlotTwiceInARow() {
        let vm = model(SequenceNonceSource(Array(UInt64(1)...97)))
        var recipes: [ComposedRecipe] = []
        for _ in 0..<50 {
            vm.handle(.trackChanged(.fixture(id: "0A2E500000000001"), existingLyrics: Self.lyrics, metadata: Self.black))
            if let recipe = composed(vm.recipe) { recipes.append(recipe) }
            vm.handle(.notPlaying)
        }
        #expect(recipes.count == 50)
        for (previous, next) in zip(recipes, recipes.dropFirst()) {
            #expect(previous.font != next.font && previous.backdrop != next.backdrop && previous.enter != next.enter)
            #expect(previous.exit != next.exit && previous.fx1 != next.fx1 && previous.palette != next.palette)
        }
    }

    @Test func theRecipeHistoryOutlivesTheViewModel() {
        let history = InMemoryRecipeHistory()
        let first = LyricsFXViewModel(positionClock: PlaybackPositionClock(music: MockMusicClient(), pollClock: GatedPollClock()), nonceSource: SequenceNonceSource([5]), recipeHistory: history)
        first.handle(.trackChanged(.fixture(id: "0A2E500000000001"), existingLyrics: Self.lyrics, metadata: Self.black))
        let second = LyricsFXViewModel(positionClock: PlaybackPositionClock(music: MockMusicClient(), pollClock: GatedPollClock()), nonceSource: SequenceNonceSource([5]), recipeHistory: history)
        second.handle(.trackChanged(.fixture(id: "0A2E500000000001"), existingLyrics: Self.lyrics, metadata: Self.black))
        #expect(composed(first.recipe)?.font != composed(second.recipe)?.font, "同 nonce 但歷史不同：第二次排除第一次的元件")
    }
}

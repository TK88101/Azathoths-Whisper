import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥a J-Pop 計劃 §4.4、§6.3：VM 接線——日文歌走 J-Pop、每次播放換變體、歌詞晚到與改詞只在來源改變時重組。歌詞為編造句
@MainActor
@Suite("LyricsFX J-Pop recipe")
struct LyricsFXJPopRecipeTests {
    static let japanese = "[Verse]\nひかりの道を歩く\n紙の舟が朝を待つ"
    static let english = "[Verse]\nLanterns over the river\nAsh in the wind"
    static let pop = TrackMetadata(genre: "Pop", duration: 200)
    static let black = TrackMetadata(genre: "Black Metal", duration: 200)
    static let pid = "0A2E500000000001"

    private static func track(_ artist: String = "Paper Lantern Ensemble") -> TrackInfo {
        .fixture(id: pid, artist: artist, title: "Paper Boat")
    }

    private func model(nonces: SequenceNonceSource = SequenceNonceSource(), history: any LyricsFXRecipeHistory = InMemoryRecipeHistory()) -> LyricsFXViewModel {
        LyricsFXViewModel(positionClock: PlaybackPositionClock(music: MockMusicClient(), pollClock: GatedPollClock()), nonceSource: nonces, recipeHistory: history)
    }

    private func variant(_ recipe: SessionRecipe) -> JPopVariant? {
        if case .composed(let composed) = recipe { JPopVariant(paletteID: composed.palette) } else { nil }
    }

    private func composed(_ recipe: SessionRecipe) -> ComposedRecipe? {
        if case .composed(let value) = recipe { value } else { nil }
    }

    @Test func aJapaneseSongByAnUnknownArtistGetsAJPopRecipe() throws {
        let vm = model()
        vm.handle(.trackChanged(Self.track(), existingLyrics: Self.japanese, metadata: Self.pop))
        let recipe = try #require(composed(vm.recipe))
        let variant = try #require(JPopVariant(paletteID: recipe.palette))
        #expect(recipe.profile == variant.profile)
        #expect(Set(JPopPolicy.catalog(variant).map(\.id)).isSuperset(of: recipe.componentIDs))
    }

    @Test func aSignedBandSingingInJapaneseKeepsItsOwnStyle() throws {
        let vm = model()
        vm.handle(.trackChanged(Self.track("Mayhem"), existingLyrics: Self.japanese, metadata: Self.pop))
        #expect(try #require(composed(vm.recipe)).profile.tags == [.black])
    }

    /// 持久化歷史＋每次重播新 nonce：相鄰兩次的變體一定不同（R1-5）
    @Test func replayingTheSameSongNeverRepeatsTheVariantBackToBack() throws {
        let suite = "azw.test.jpop.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = StoredRecipeHistory(store: ConfigStore(secrets: EphemeralSecretStore(), defaults: defaults))
        let vm = model(nonces: SequenceNonceSource([7, 7, 7, 7]), history: history)
        var variants: [JPopVariant] = []
        for _ in 0..<4 {
            vm.handle(.trackChanged(Self.track(), existingLyrics: Self.japanese, metadata: Self.pop))
            variants.append(try #require(variant(vm.recipe)))
            vm.handle(.notPlaying)
        }
        for (previous, next) in zip(variants, variants.dropFirst()) { #expect(previous != next, "\(variants)") }
    }

    @Test(arguments: [["Bebas", "snow", "fadeUp", "up", "none", "britRed"], ["Bebas", "snow", "fadeUp", "up", "none", "no-such-palette"]])
    func historyFromANonJPopRecipeCountsAsNoPreviousVariant(stored: [String]) throws {
        let history = InMemoryRecipeHistory()
        history.record(try #require(RecipePicks(stored: stored)), forTrack: Self.pid)
        let vm = model(history: history)
        vm.handle(.trackChanged(Self.track(), existingLyrics: Self.japanese, metadata: Self.pop))
        #expect(variant(vm.recipe) != nil)
    }

    @Test func unreadableLyricsWaitInsteadOfSettlingOnTheGenre() {
        let vm = model()
        vm.handle(.trackChanged(Self.track(), existingLyrics: nil, metadata: Self.black))
        #expect(vm.recipe == .mono)
        vm.handle(.trackChanged(Self.track(), existingLyrics: Self.japanese, metadata: Self.black))
        #expect(variant(vm.recipe) != nil, "歌詞到了才定格，而且是 J-Pop")
    }

    /// Codex 最擔心點：缺詞歌先依曲風定格成素面，之後寫入日文詞 → 來源改變 → 重組成 J-Pop
    @Test func writingJapaneseLyricsIntoASettledSongSwitchesItToJPop() {
        let vm = model()
        vm.handle(.trackChanged(Self.track(), existingLyrics: "", metadata: TrackMetadata(genre: "Polka", duration: 200)))
        #expect(vm.recipe == .mono)
        vm.lyricsUpdated(persistentID: Self.pid, text: Self.japanese)
        #expect(variant(vm.recipe) != nil)
    }

    @Test func japaneseLyricsReplacedByEnglishLeaveJPopForTheGenre() throws {
        let vm = model()
        vm.handle(.trackChanged(Self.track(), existingLyrics: Self.japanese, metadata: Self.black))
        #expect(variant(vm.recipe) != nil)
        vm.lyricsUpdated(persistentID: Self.pid, text: Self.english)
        #expect(try #require(composed(vm.recipe)).profile.tags.contains(.black))
    }

    @Test func editsWithinTheSameSourceKeepTheRecipe() throws {
        let vm = model()
        vm.handle(.trackChanged(Self.track(), existingLyrics: Self.japanese, metadata: Self.pop))
        let first = try #require(composed(vm.recipe))
        vm.lyricsUpdated(persistentID: Self.pid, text: "[Verse]\n朝の川をわたる")
        vm.handle(.metadataChanged(persistentID: Self.pid, metadata: Self.black))
        #expect(composed(vm.recipe) == first)
    }

    @Test func aSignedBandWritingJapaneseLyricsDoesNotRecompose() throws {
        let vm = model()
        vm.handle(.trackChanged(Self.track("Mayhem"), existingLyrics: Self.english, metadata: Self.black))
        let first = try #require(composed(vm.recipe))
        vm.lyricsUpdated(persistentID: Self.pid, text: Self.japanese)
        #expect(composed(vm.recipe) == first)
    }

    @Test func aLateGenreForAnEnglishSongStillSettlesOnce() throws {
        let vm = model()
        vm.handle(.trackChanged(Self.track(), existingLyrics: Self.english, metadata: .unknown))
        #expect(vm.recipe == .mono)
        vm.handle(.metadataChanged(persistentID: Self.pid, metadata: Self.black))
        #expect(try #require(composed(vm.recipe)).profile.tags.contains(.black))
    }

    /// 換曲後上一首的來源不得沿用：新的一首（英文、曲風無命中）不因「來源改變」被誤判重組
    @Test func aNewTrackStartsWithoutTheOldSource() {
        let vm = model()
        vm.handle(.trackChanged(Self.track(), existingLyrics: Self.japanese, metadata: Self.pop))
        vm.handle(.trackChanged(.fixture(id: "0A2E500000000002", artist: "Paper Lantern Ensemble", title: "Other"),
                                existingLyrics: Self.english, metadata: TrackMetadata(genre: "Polka", duration: 200)))
        #expect(vm.recipe == .mono)
        vm.handle(.notPlaying)
        vm.handle(.trackChanged(Self.track(), existingLyrics: Self.english, metadata: TrackMetadata(genre: "Polka", duration: 200)))
        #expect(vm.recipe == .mono)
    }
}

// 定格後何時重組：只有進出 J-Pop（唯一由歌詞決定的來源）
@Suite("LyricsFX recompose rule")
struct LyricsFXRecomposeRuleTests {
    @Test(arguments: [
        (ProfileSource?.none, ProfileSource.noMatch, true), (nil, .jpopPolicy, true),
        (.noMatch, .jpopPolicy, true), (.genreRow, .jpopPolicy, true), (.jpopPolicy, .genreRow, true), (.jpopPolicy, .noMatch, true),
        (.noMatch, .genreRow, false), (.genreRow, .noMatch, false), (.genreRow, .genreRow, false), (.jpopPolicy, .jpopPolicy, false),
        (.signedBand, .signedBand, false),
    ])
    @MainActor
    func recomposesOnlyAcrossTheJPopBoundary(settled: ProfileSource?, now: ProfileSource, expected: Bool) {
        #expect(LyricsFXViewModel.shouldCompose(settled: settled, now: now) == expected)
    }
}

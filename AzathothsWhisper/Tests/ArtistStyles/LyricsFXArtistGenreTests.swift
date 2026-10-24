import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥b 計劃 §4.3、§4.6（R1-6、R1-8）：VM 同步讀 snapshot；MB 結果在播放途中才到不重組，下一次播放才生效。歌詞自編
@MainActor
@Suite("LyricsFX artist genres")
struct LyricsFXArtistGenreTests {
    static let lyrics = "[Verse]\nLanterns over the river\nAsh in the wind"
    static let rock = TrackMetadata(genre: "Rock", duration: 200)

    final class Box { var genres: ArtistGenres = .unknown }

    private func model() -> LyricsFXViewModel {
        LyricsFXViewModel(positionClock: PlaybackPositionClock(music: MockMusicClient(), pollClock: GatedPollClock()), nonceSource: SequenceNonceSource())
    }

    private func tags(_ recipe: SessionRecipe) -> Set<FXTag>? {
        if case .composed(let value) = recipe { return value.profile.tags }
        return nil
    }

    @Test func anMBResultArrivingMidSessionAppliesFromTheNextPlay() throws {
        let box = Box()
        let vm = model()
        vm.artistGenres = { _ in box.genres }
        let track = TrackInfo.fixture(id: "A", artist: "Velvet Lanterns")
        vm.handle(.trackChanged(track, existingLyrics: Self.lyrics, metadata: Self.rock))
        let appleTags = try #require(tags(vm.recipe))
        #expect(!appleTags.contains(.black), "先依 Apple 曲風（Rock）")

        box.genres = .verified(["black metal"])
        vm.handle(.lyricsChanged(persistentID: "A", lyrics: Self.lyrics + "\nPaper boats at dawn"))
        vm.handle(.metadataChanged(persistentID: "A", metadata: TrackMetadata(genre: "Rock", duration: 201)))
        #expect(tags(vm.recipe) == appleTags, "同一次播放不重組")

        vm.handle(.notPlaying)
        vm.handle(.trackChanged(track, existingLyrics: Self.lyrics, metadata: Self.rock))
        #expect(tags(vm.recipe) == [.black], "下一次播放套 MB")
    }

    @Test func theCallbackGetsTheTrackArtist() {
        var asked: [String] = []
        let vm = model()
        vm.artistGenres = { artist in asked.append(artist); return .unknown }
        vm.handle(.trackChanged(.fixture(id: "A", artist: "Velvet Lanterns"), existingLyrics: Self.lyrics, metadata: Self.rock))
        #expect(asked.contains("Velvet Lanterns"))
    }
}

// ⑥b 計劃 §4.6：AppModel 接線——背景一輪跑完後，歌詞特效讀得到 snapshot
@MainActor
@Suite("AppModel artist styles")
struct AppModelArtistStylesTests {
    private struct AlwaysValidValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    @Test func aFinishedRunIsVisibleToTheLyricsFXCallback() async {
        let suiteName = "AppModelArtistStylesTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let music = MockMusicClient(script: [.notPlaying], repeatLast: true)
        await music.setLibrary([LibraryArtistAlbum(artist: "Velvet Lanterns", album: "Night Ferry")])
        await music.setArtistTracks([ArtistTrack(album: "Night Ferry", lyrics: "Lanterns over the river")], for: "Velvet Lanterns")
        let store = ArtistStyleStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("azw-appmodel-\(UUID().uuidString)"))
        let model = AppModel(
            configStore: ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!),
            httpClient: MockHTTPClient(), music: music, monitor: NowPlayingMonitor(music: music, clock: GatedPollClock()),
            validator: AlwaysValidValidator(), notifier: SpyLyricsNotifier(), playerSignal: SpyPlayerChangeSignal(),
            initialToken: "", initialLanguage: .system, splashDuration: .milliseconds(1), lyricsFlowClock: GatedPollClock(),
            positionPollClock: GatedPollClock(), isMusicRunning: { true },
            artistStyles: { publish in
                ArtistStyleSync(
                    music: music, store: store,
                    identify: { _, _ throws(ProviderFailure) in .verified(id: "mb-1", matchedReleaseGroups: [], genres: [.init(name: "black metal", count: 2)]) },
                    publish: publish
                )
            }
        )
        defer { model.stop() }
        #expect(model.lyricsFX.artistGenres("Velvet Lanterns") == .unknown)
        model.startArtistStyles()
        await model.waitForArtistStyles()
        #expect(model.lyricsFX.artistGenres("Velvet Lanterns") == .verified(["black metal"]))
    }
}

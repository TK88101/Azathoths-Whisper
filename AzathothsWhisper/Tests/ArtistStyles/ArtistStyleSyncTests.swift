import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥b 計劃 §4.1、§4.5（R1-2、R1-11、R2-3）：要查清單、佇列、失敗、續跑。歌手、專輯、歌詞全為自編
@Suite("Artist style sync")
struct ArtistStyleSyncTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let english = "Lanterns drift across the harbour\nPaper boats remember rain"
    static let japanese = "かみのふねがながれる\nあめのおとをおぼえてる"

    actor Recorder {
        private(set) var asked: [(artist: String, albums: [String])] = []
        private(set) var published: [ArtistStyleBook] = []
        var failures: [String: ProviderFailure] = [:]
        var onAsk: (@Sendable (String) async -> Void)?

        func fail(_ artist: String, with failure: ProviderFailure) { failures[artist] = failure }
        func setOnAsk(_ hook: @escaping @Sendable (String) async -> Void) { onAsk = hook }
        func publish(_ book: ArtistStyleBook) { published.append(book) }

        func identify(_ artist: String, _ albums: [String]) async throws(ProviderFailure) -> ArtistStyleBook.Lookup {
            asked.append((artist, albums))
            await onAsk?(artist)
            if let failure = failures[artist] { throw failure }
            return .verified(id: "mb-\(artist)", matchedReleaseGroups: [], genres: [.init(name: "black metal", count: 1)])
        }
    }

    private func tempStore() -> ArtistStyleStore {
        ArtistStyleStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("azw-sync-\(UUID().uuidString)"))
    }

    private func sync(_ music: MockMusicClient, _ recorder: Recorder, store: ArtistStyleStore) -> ArtistStyleSync {
        ArtistStyleSync(
            music: music, store: store, now: { Self.now },
            identify: { artist, albums throws(ProviderFailure) in try await recorder.identify(artist, albums) },
            publish: { book in await recorder.publish(book) }
        )
    }

    private func library(_ rows: [(String, String)]) -> [LibraryArtistAlbum] {
        rows.map { LibraryArtistAlbum(artist: $0.0, album: $0.1) }
    }

    @Test func signedBandsAndJapaneseOnlyArtistsAreNotQueried() async {
        let music = MockMusicClient()
        await music.setLibrary(library([("Mayhem", "A"), ("Velvet Lanterns", "Night Ferry"), ("Kamifune", "Ame")]))
        await music.setArtistTracks([ArtistTrack(album: "Night Ferry", lyrics: Self.english)], for: "Velvet Lanterns")
        await music.setArtistTracks([ArtistTrack(album: "Ame", lyrics: Self.japanese)], for: "Kamifune")
        let recorder = Recorder()
        await sync(music, recorder, store: tempStore()).run()
        #expect(await recorder.asked.map(\.artist) == ["Velvet Lanterns"])
        #expect(await music.artistTracksRequests.contains("Mayhem") == false, "樂團表的團連歌詞都不讀")
    }

    /// R1-2：混合歌手照查，但只送含非日文曲的專輯
    @Test func aMixedArtistSendsOnlyAlbumsWithNonJapaneseSongs() async {
        let music = MockMusicClient()
        await music.setLibrary(library([("Velvet Lanterns", "Night Ferry"), ("Velvet Lanterns", "Ame"), ("Velvet Lanterns", "Quiet")]))
        await music.setArtistTracks([
            ArtistTrack(album: "Night Ferry", lyrics: Self.english), ArtistTrack(album: "Ame", lyrics: Self.japanese),
            ArtistTrack(album: "Quiet", lyrics: ""),
        ], for: "Velvet Lanterns")
        let recorder = Recorder()
        await sync(music, recorder, store: tempStore()).run()
        #expect(await recorder.asked.first?.albums == ["Night Ferry", "Quiet"])
    }

    @Test func artistsWithMoreTracksAreQueriedFirst() async {
        let music = MockMusicClient()
        await music.setLibrary(library([("Paper Harbour", "B"), ("Velvet Lanterns", "A"), ("Velvet Lanterns", "A"), ("Velvet Lanterns", "C")]))
        for artist in ["Paper Harbour", "Velvet Lanterns"] { await music.setArtistTracks([ArtistTrack(album: "A", lyrics: Self.english)], for: artist) }
        let recorder = Recorder()
        await sync(music, recorder, store: tempStore()).run()
        #expect(await recorder.asked.map(\.artist) == ["Velvet Lanterns", "Paper Harbour"])
    }

    /// R1-11：正在播的歌手插到隊首；只有排隊中的能插隊，查過的不重查
    @Test func theNowPlayingArtistJumpsTheQueue() async {
        let music = MockMusicClient()
        await music.setLibrary(library([("Alpha Lanterns", "A"), ("Alpha Lanterns", "A2"), ("Beta Harbour", "B"), ("Gamma Ferry", "C")]))
        for artist in ["Alpha Lanterns", "Beta Harbour", "Gamma Ferry"] { await music.setArtistTracks([ArtistTrack(album: "A", lyrics: Self.english)], for: artist) }
        let recorder = Recorder()
        let sync = sync(music, recorder, store: tempStore())
        await recorder.setOnAsk { artist in
            if artist == "Alpha Lanterns" {
                await sync.prioritize(artist: "GAMMA FERRY")
                await sync.prioritize(artist: "Alpha Lanterns")
            }
        }
        await sync.run()
        #expect(await recorder.asked.map(\.artist) == ["Alpha Lanterns", "Gamma Ferry", "Beta Harbour"])
    }

    @Test func aNetworkFailureIsNotRecordedAndIsRetriedNextTime() async {
        let music = MockMusicClient()
        await music.setLibrary(library([("Velvet Lanterns", "A")]))
        await music.setArtistTracks([ArtistTrack(album: "A", lyrics: Self.english)], for: "Velvet Lanterns")
        let store = tempStore()
        let recorder = Recorder()
        await recorder.fail("Velvet Lanterns", with: .timedOut)
        await sync(music, recorder, store: store).run()
        let afterFailure = store.load().book
        #expect(afterFailure.hasRecord(forArtist: "Velvet Lanterns") == false)
        #expect(afterFailure.summary.lastNetworkError == "timedOut")

        let retry = Recorder()
        await sync(music, retry, store: store).run()
        #expect(await retry.asked.map(\.artist) == ["Velvet Lanterns"])
        #expect(store.load().book.genres(forArtist: "Velvet Lanterns") == .verified(["black metal"]))
    }

    @Test func anOpenCircuitStopsTheRun() async {
        let music = MockMusicClient()
        await music.setLibrary(library([("Alpha Lanterns", "A"), ("Alpha Lanterns", "A"), ("Beta Harbour", "B")]))
        for artist in ["Alpha Lanterns", "Beta Harbour"] { await music.setArtistTracks([ArtistTrack(album: "A", lyrics: Self.english)], for: artist) }
        let recorder = Recorder()
        await recorder.fail("Alpha Lanterns", with: .circuitOpen)
        await sync(music, recorder, store: tempStore()).run()
        #expect(await recorder.asked.map(\.artist) == ["Alpha Lanterns"])
    }

    @Test func aFailedLibraryScanQueriesNothingButStillPublishesWhatIsStored() async throws {
        let store = tempStore()
        try store.save(ArtistStyleBook().recording(.unresolved(.notFound), forSpelling: "Paper Harbour", at: Self.now))
        let music = MockMusicClient()
        await music.failLibrary(.notRunning)
        let recorder = Recorder()
        await sync(music, recorder, store: store).run()
        #expect(await recorder.asked.isEmpty)
        #expect(await recorder.published.first?.hasRecord(forArtist: "Paper Harbour") == true)
    }

    @Test func recordsArePersistedOneByOneSoASecondRunAsksNothing() async {
        let music = MockMusicClient()
        await music.setLibrary(library([("Alpha Lanterns", "A"), ("Beta Harbour", "B")]))
        for artist in ["Alpha Lanterns", "Beta Harbour"] { await music.setArtistTracks([ArtistTrack(album: "A", lyrics: Self.english)], for: artist) }
        let store = tempStore()
        let first = Recorder()
        await sync(music, first, store: store).run()
        #expect(await first.published.count == 3, "載入一次＋每查完一位一次")
        let second = Recorder()
        await sync(music, second, store: store).run()
        #expect(await second.asked.isEmpty)
    }

    /// R2-3：曲庫裡兩個不同寫法撞同一個鍵＝不查、兩個都記成撞鍵
    @Test func differentSpellingsOnOneKeyAreACollisionAndAreNotQueried() async {
        let music = MockMusicClient()
        await music.setLibrary(library([("AC/DX", "A"), ("ACDX", "B")]))
        let recorder = Recorder()
        let store = tempStore()
        await sync(music, recorder, store: store).run()
        #expect(await recorder.asked.isEmpty)
        #expect(store.load().book.record(forArtist: "ACDX")?.reason == .collision)
    }

    @Test func caseVariantsAreQueriedOnceAndShareTheResult() async {
        let music = MockMusicClient()
        await music.setLibrary(library([("Velvet Lanterns", "A"), ("VELVET LANTERNS", "B")]))
        await music.setArtistTracks([ArtistTrack(album: "A", lyrics: Self.english)], for: "Velvet Lanterns")
        let recorder = Recorder()
        let store = tempStore()
        await sync(music, recorder, store: store).run()
        #expect(await recorder.asked.count == 1)
        #expect(store.load().book.genres(forArtist: "VELVET LANTERNS") == .verified(["black metal"]))
    }

    @Test func anUnwritableStoreQueriesNothing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{\"schemaVersion\": 99}".write(to: directory.appendingPathComponent(ArtistStyleStore.fileName), atomically: true, encoding: .utf8)
        let music = MockMusicClient()
        await music.setLibrary(library([("Velvet Lanterns", "A")]))
        let recorder = Recorder()
        await sync(music, recorder, store: ArtistStyleStore(directory: directory)).run()
        #expect(await recorder.asked.isEmpty)
    }

    @Test func anArtistWithNoReadableTracksIsSkippedThisTime() async {
        let music = MockMusicClient()
        await music.setLibrary(library([("Velvet Lanterns", "A")]))
        let recorder = Recorder()
        let store = tempStore()
        await sync(music, recorder, store: store).run()
        #expect(await recorder.asked.isEmpty)
        #expect(store.load().book.hasRecord(forArtist: "Velvet Lanterns") == false)
    }

    /// simcodex R1（Codex）：掃描時才發現的撞鍵要立刻發布，不能讓這次啟動繼續套舊的 MB 曲風
    @Test func aCollisionFoundDuringTheScanIsPublishedRightAway() async throws {
        let store = tempStore()
        try store.save(ArtistStyleBook().recording(
            .verified(id: "mb-1", matchedReleaseGroups: [], genres: [.init(name: "black metal", count: 1)]), forSpelling: "AC/DX", at: Self.now
        ))
        let music = MockMusicClient()
        await music.setLibrary(library([("AC/DX", "A"), ("ACDX", "B")]))
        let recorder = Recorder()
        await sync(music, recorder, store: store).run()
        let published = await recorder.published
        #expect(published.first?.genres(forArtist: "AC/DX") == .verified(["black metal"]), "載入時照舊")
        #expect(published.last?.genres(forArtist: "AC/DX") == .unresolved)
        #expect(published.last?.genres(forArtist: "ACDX") == .unresolved)
        #expect(await recorder.asked.isEmpty)
    }
}

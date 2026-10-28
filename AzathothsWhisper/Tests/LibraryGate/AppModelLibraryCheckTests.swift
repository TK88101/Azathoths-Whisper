import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.3、§4.5：AppModel 接線——檢查畫面掃 Music 替身、決定存檔並同步給歌詞特效、MB 資料換新就要重掃
@MainActor
@Suite("AppModel library check")
struct AppModelLibraryCheckTests {
    private struct AlwaysValidValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    private func model(music: MockMusicClient, decisions: ArtistDecisionStore?, suiteName: String,
                       artistStyles: AppModel.ArtistStylesFactory? = nil) -> AppModel {
        AppModel(
            configStore: ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!),
            httpClient: MockHTTPClient(), music: music, monitor: NowPlayingMonitor(music: music, clock: GatedPollClock()),
            validator: AlwaysValidValidator(), notifier: SpyLyricsNotifier(), playerSignal: SpyPlayerChangeSignal(),
            initialToken: "", initialLanguage: .system, artistStylesStartDelay: .milliseconds(1), lyricsFlowClock: GatedPollClock(),
            positionPollClock: GatedPollClock(), isMusicRunning: { true },
            artistStyles: artistStyles, artistDecisions: decisions
        )
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("azw-appmodel-decisions-\(UUID().uuidString)")
    }

    @Test func aDecisionIsSavedAndVisibleToTheLyricsFXCallback() async throws {
        let suiteName = "AppModelLibraryCheckTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let music = MockMusicClient(script: [.notPlaying], repeatLast: true)
        await music.setSnapshot([LibraryTrackRow(persistentID: "1", name: "Song 1", artist: "Paper Harbour", album: "Night Ferry", genre: "Rock")])
        await music.setArtistLyrics([ArtistLyricsRow(persistentID: "1", lyrics: "Lanterns over the river")], for: "Paper Harbour")
        let directory = tempDirectory()
        let model = model(music: music, decisions: ArtistDecisionStore(directory: directory), suiteName: suiteName)
        defer { model.stop() }

        model.libraryCheck.rescan()
        await model.libraryCheck.waitForScan()
        #expect(model.libraryCheck.report?.composed == .init(songs: 1, artists: 1))

        model.libraryCheck.decide(.style(rowID: "punk"), forArtists: ["Paper Harbour"])
        #expect(model.lyricsFX.artistDecision("Paper Harbour") == .style(rowID: "punk"))
        #expect(ArtistDecisionStore(directory: directory).load().book.decision(forArtist: "Paper Harbour")?.choice == .style(rowID: "punk"))
    }

    @Test func savedDecisionsAreLoadedAtLaunch() throws {
        let suiteName = "AppModelLibraryCheckTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let directory = tempDirectory()
        try ArtistDecisionStore(directory: directory).save(
            ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Paper Harbour"], at: Date(timeIntervalSince1970: 1_790_000_000))
        )
        let model = model(music: MockMusicClient(script: [.notPlaying], repeatLast: true), decisions: ArtistDecisionStore(directory: directory), suiteName: suiteName)
        defer { model.stop() }
        #expect(model.lyricsFX.artistDecision("Paper Harbour") == .keepFallback)
        #expect(model.libraryCheck.decisions.decision(forArtist: "Paper Harbour")?.choice == .keepFallback)
    }

    @Test func withoutAStoreDecisionsStayInMemoryOnly() async {
        let suiteName = "AppModelLibraryCheckTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = model(music: MockMusicClient(script: [.notPlaying], repeatLast: true), decisions: nil, suiteName: suiteName)
        defer { model.stop() }
        model.libraryCheck.decide(.keepFallback, forArtists: ["Paper Harbour"])
        #expect(model.lyricsFX.artistDecision("Paper Harbour") == .keepFallback)
    }

    /// codex review R2 P1：MB 資料換新時，畫面讀的 `status` 要收到觀察通知（不靠別的欄位碰巧重繪）
    @Test func freshArtistDataNotifiesObserversOfTheStatus() async {
        let suiteName = "AppModelLibraryCheckTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let music = MockMusicClient(script: [.notPlaying], repeatLast: true)
        await music.setSnapshot([LibraryTrackRow(persistentID: "1", name: "Song 1", artist: "Mayhem", album: "Night Ferry", genre: "Black Metal")])
        await music.setArtistLyrics([ArtistLyricsRow(persistentID: "1", lyrics: "Lanterns over the river")], for: "Mayhem")
        let store = ArtistStyleStore(directory: tempDirectory())
        let model = model(music: music, decisions: nil, suiteName: suiteName, artistStyles: { publish in
            ArtistStyleSync(music: music, store: store, identify: { _, _ throws(ProviderFailure) in .unresolved(.notFound) }, publish: publish)
        })
        defer { model.stop() }
        // 已有報表時 status 才會讀 MB 存檔（還沒掃描＝直接回「還沒掃描」）
        model.libraryCheck.rescan()
        await model.libraryCheck.waitForScan()
        final class Flag: @unchecked Sendable { var changed = false }
        let flag = Flag()
        withObservationTracking { _ = model.libraryCheck.status } onChange: { flag.changed = true }
        model.startArtistStyles()
        await model.waitForArtistStyles()
        #expect(flag.changed)
    }

    @Test func freshArtistDataMarksTheCheckForARescan() async {
        let suiteName = "AppModelLibraryCheckTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let music = MockMusicClient(script: [.notPlaying], repeatLast: true)
        await music.setSnapshot([LibraryTrackRow(persistentID: "1", name: "Song 1", artist: "Mayhem", album: "Night Ferry", genre: "Black Metal")])
        await music.setArtistLyrics([ArtistLyricsRow(persistentID: "1", lyrics: "Lanterns over the river")], for: "Mayhem")
        let store = ArtistStyleStore(directory: tempDirectory())
        let model = model(music: music, decisions: nil, suiteName: suiteName, artistStyles: { publish in
            ArtistStyleSync(music: music, store: store, identify: { _, _ throws(ProviderFailure) in .unresolved(.notFound) }, publish: publish)
        })
        defer { model.stop() }
        model.libraryCheck.rescan()
        await model.libraryCheck.waitForScan()
        #expect(model.libraryCheck.status == .needsRescan, "MB 存檔還沒載入，不能判定達標")
        model.startArtistStyles()
        await model.waitForArtistStyles()
        model.libraryCheck.rescan()
        await model.libraryCheck.waitForScan()
        #expect(model.libraryCheck.status == .passed)
    }
}

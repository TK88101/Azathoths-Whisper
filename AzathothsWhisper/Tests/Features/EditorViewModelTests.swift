import Foundation
import Testing

@testable import AzathothsWhisper

// ACCEPTANCE B 區段的邏輯層：狀態文案、自動抓詞、世代守衛、Save 綁定、行數統計
@MainActor
@Suite("EditorViewModel")
struct EditorViewModelTests {
    private func makeModel(
        genius: LyricsResult = .notFound,
        music: MockMusicClient = MockMusicClient()
    ) -> EditorViewModel {
        EditorViewModel(
            lyricsService: .stub(genius: genius),
            music: music,
            clock: ImmediateClock()
        )
    }

    // B-15
    @Test func lineCountFollowsPythonSplitSemantics() {
        let model = makeModel()
        #expect(model.lineCount == 0)
        model.lyricsText = "one"
        #expect(model.lineCount == 1)
        model.lyricsText = "one\ntwo"
        #expect(model.lineCount == 2)
        model.lyricsText = "one\n"          // 尾空行仍計為一行
        #expect(model.lineCount == 2)
    }

    // B-15：Music 常以 CR 分行，原版經 <textarea> 隱式正規化成 LF；缺這一步整首歌會算成 1 行
    @Test func carriageReturnLyricsAreNormalizedLikeTextarea() {
        let model = makeModel()
        model.handle(.trackChanged(.fixture(), existingLyrics: "one\rtwo\r\nthree"))

        #expect(model.lyricsText == "one\ntwo\nthree")
        #expect(model.lineCount == 3)
    }

    // B-04
    @Test func trackWithExistingLyricsLoadsThemAndReportsStatus() {
        let model = makeModel()
        model.handle(.trackChanged(.fixture(), existingLyrics: "already here"))

        #expect(model.lyricsText == "already here")
        #expect(model.statusText == StatusText.lyricsLoadedFromMusicApp)
        #expect(model.autoFetchTask == nil, "已有歌詞不得自動抓取")
    }

    // B-05
    @Test func trackWithoutLyricsClearsAndAutoFetches() async {
        let model = makeModel(genius: .found("fetched body"))
        model.lyricsText = "stale"
        model.handle(.trackChanged(.fixture(), existingLyrics: "   "))

        #expect(model.lyricsText == "")
        await model.autoFetchTask?.value
        #expect(model.lyricsText == "fetched body")
        #expect(model.statusText == StatusText.lyricsFetched)
    }

    /// 計劃 D8／AC7：讀不到歌詞 → 不自動抓詞、不宣稱缺詞（否則使用者按 Write 會覆蓋掉原本的詞）
    @Test func unreadableLyricsNeitherAutoFetchNorClaimMissing() {
        let model = makeModel(genius: .found("body"))
        model.lyricsText = "stale"
        model.handle(.trackChanged(.fixture(), existingLyrics: nil))

        #expect(model.autoFetchTask == nil)
        #expect(model.lyricsText == "")
        #expect(model.statusText == StatusText.lyricsUnreadable)
    }

    // B-05（後半）：非 Editor tab 時不自動抓
    @Test func autoFetchSkippedWhenEditorTabInactive() {
        let model = makeModel(genius: .found("body"))
        model.isEditorTabActive = false
        model.handle(.trackChanged(.fixture(), existingLyrics: ""))

        #expect(model.autoFetchTask == nil)
        #expect(model.lyricsText == "")
    }

    // B-11：三態文案
    @Test func fetchReportsFetchedForFoundResult() async {
        let model = makeModel(genius: .found("lyrics body"))
        model.handle(.trackChanged(.fixture(), existingLyrics: "seed"))
        await model.fetch()

        #expect(model.lyricsText == "lyrics body")
        #expect(model.statusText == StatusText.lyricsFetched)
    }

    @Test func fetchReportsNotFoundForNotFoundResult() async {
        let model = makeModel(genius: .notFound)
        model.handle(.trackChanged(.fixture(), existingLyrics: "seed"))
        await model.fetch()

        #expect(model.statusText == StatusText.lyricsNotFound)
        #expect(model.lyricsText == "seed", "未命中不得清空使用者既有內容")
    }

    // B-11a：Genius 錯誤不得被當作歌詞寫進編輯框
    @Test func fetchNeverWritesErrorTextIntoLyricsBox() async {
        let model = makeModel(genius: .error("Genius Error: boom"))
        model.handle(.trackChanged(.fixture(), existingLyrics: "seed"))
        await model.fetch()

        #expect(model.statusText == StatusText.lyricsNotFound)
        #expect(model.lyricsText == "seed")
    }

    @Test func fetchWithoutAnyTrackReportsNotFound() async {
        let music = MockMusicClient(script: [.notPlaying])
        let model = makeModel(genius: .found("x"), music: music)
        await model.fetch()

        #expect(model.statusText == StatusText.lyricsNotFound)
    }

    @Test func fetchReportsFetchFailedWhenMusicIsUnreachable() async {
        let music = MockMusicClient(script: [.failure(.notRunning)])
        let model = makeModel(genius: .found("x"), music: music)
        await model.fetch()

        #expect(model.statusText == StatusText.fetchFailed)
    }

    // B-14：抓詞進行中切歌 → 結果不套用到新曲
    @Test func inFlightFetchDoesNotOverwriteNewlySwitchedTrack() async {
        let gate = LyricsGate()
        let model = EditorViewModel(
            lyricsService: LyricsService(
                genius: GatedLyricsSource(gate: gate, result: .found("OLD SONG")),
                darkLyrics: StubLyricsSource(.notFound)
            ),
            music: MockMusicClient(),
            clock: ImmediateClock()
        )

        model.handle(.trackChanged(.fixture(id: "PID1"), existingLyrics: ""))
        await waitUntil { model.isBusy }
        #expect(model.isBusy)
        #expect(model.statusText == StatusText.fetchingFromGenius, "B-10：抓詞中的狀態文案")

        model.handle(.trackChanged(.fixture(id: "PID2", title: "Next"), existingLyrics: "NEW SONG"))
        await gate.open()
        await model.autoFetchTask?.value

        #expect(model.lyricsText == "NEW SONG")
        #expect(model.statusText == StatusText.lyricsLoadedFromMusicApp)
    }

    // B-13：Save 寫入畫面綁定的 persistentID
    @Test func saveWritesToBoundTrackIdentifier() async {
        let music = MockMusicClient()
        let model = makeModel(music: music)
        model.handle(.trackChanged(.fixture(id: "BOUND"), existingLyrics: "seed"))
        model.lyricsText = "edited body"

        await model.save()

        #expect(await music.writes == ["BOUND": "edited body"])
        #expect(model.statusText == StatusText.saved)
    }

    // B-12
    @Test func successfulSaveTriggersConfetti() async {
        let model = makeModel()
        model.handle(.trackChanged(.fixture(), existingLyrics: "seed"))
        let before = model.confettiTrigger

        await model.save()

        #expect(model.confettiTrigger == before + 1)
    }

    @Test func saveWithoutBoundTrackReportsNoTrackPlaying() async {
        let model = makeModel()
        await model.save()

        #expect(model.statusText == StatusText.noTrackPlaying)
        #expect(model.confettiTrigger == 0)
    }

    @Test func saveReportsFailedToSaveWhenWriteReturnsFalse() async {
        let music = MockMusicClient()
        await music.setSetLyricsOutcome(.success(false))
        let model = makeModel(music: music)
        model.handle(.trackChanged(.fixture(), existingLyrics: "seed"))

        await model.save()

        #expect(model.statusText == StatusText.failedToSave)
        #expect(model.confettiTrigger == 0)
    }

    @Test func saveReportsWriteFailedWhenMusicThrows() async {
        let music = MockMusicClient()
        await music.setSetLyricsOutcome(.failure(.permissionDenied))
        let model = makeModel(music: music)
        model.handle(.trackChanged(.fixture(), existingLyrics: "seed"))

        await model.save()

        #expect(model.statusText == StatusText.writeFailed)
    }

    // B-21 / B-02：忙碌狀態外溢（按鈕禁用＋輪詢跳過的唯一資料源）
    @Test func busyStateIsPublishedAroundFetch() async {
        let model = makeModel(genius: .found("x"))
        var transitions: [Bool] = []
        model.onBusyChange = { transitions.append($0) }
        model.handle(.trackChanged(.fixture(), existingLyrics: "seed"))

        await model.fetch()

        #expect(transitions == [true, false])
        #expect(model.isBusy == false)
    }

    // A-12
    @Test func permissionDeniedShowsAccessDeniedCard() {
        let model = makeModel()
        model.handle(.permissionDenied)

        #expect(model.artistLine == StatusText.accessDenied)
        #expect(model.titleLine == StatusText.checkMacOSPermissions)
        #expect(model.isAccessDenied)
    }

    // B-08
    @Test func notPlayingShowsPlaceholderLines() {
        let model = makeModel()
        model.handle(.trackChanged(.fixture(), existingLyrics: "seed"))
        model.handle(.notPlaying)

        #expect(model.artistLine == StatusText.noArtist)
        #expect(model.titleLine == StatusText.noTrack)
    }

    // B-06：卡片點擊＝強制重讀
    @Test func cardTapRequestsHydrate() {
        let model = makeModel()
        var didRequest = false
        model.onRequestHydrate = { didRequest = true }

        model.requestHydrate()

        #expect(didRequest)
    }

    // B-19：資料來源下拉純裝飾——切成 darklyrics 後 Editor 仍只走 Genius
    @Test func dataSourceSelectionDoesNotAffectFetchPath() async {
        let model = makeModel(genius: .found("from genius"))
        model.dataSource = .darklyrics
        model.handle(.trackChanged(.fixture(), existingLyrics: "seed"))

        await model.fetch()

        #expect(model.lyricsText == "from genius")
    }
}

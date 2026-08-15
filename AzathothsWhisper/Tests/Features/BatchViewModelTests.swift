import Foundation
import Testing

@testable import AzathothsWhisper

// ACCEPTANCE C 區段的邏輯層：載入三態、列表渲染、三動作串行循環、sessionID 守衛。
// 行為真源＝lyrics_fetcher.py:554-740（JS）＋2218-2255（後端）。
@MainActor
@Suite("BatchViewModel")
struct BatchViewModelTests {
    /// T1＝有詞、T2＝空字串缺詞、T3＝純空白（C-29 判為缺詞）
    private var sampleTracks: [AlbumTrack] {
        [
            .fixture(id: "T1", title: "Alpha", lyrics: "alpha body"),
            .fixture(id: "T2", title: "Beta", lyrics: ""),
            .fixture(id: "T3", title: "Gamma", lyrics: "   \n  "),
        ]
    }

    private func makeModel(
        albumTracks: [AlbumTrack] = [],
        genius: [String: LyricsResult] = [:],
        darkLyrics: LyricsResult = .notFound,
        music: MockMusicClient? = nil
    ) async -> BatchViewModel {
        let client = music ?? MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await client.setAlbumTracks(albumTracks)
        return BatchViewModel(
            lyricsService: .scripted(genius: genius, darkLyrics: darkLyrics),
            music: client
        )
    }

    /// 等到來源實際收到至少 n 次查詢。
    /// 不能改用 statusText 判斷：進度文案設在 await 之前，actor hop 使「文案已更新」早於「來源已被調用」
    private func waitForQueries(_ source: RecordingLyricsSource, atLeast n: Int) async {
        for _ in 0..<500 {
            if await source.queries.count >= n { return }
            await Task.yield()
        }
    }

    /// 讓 model 進入「已載入 sampleTracks」狀態
    private func loadedModel(
        genius: [String: LyricsResult] = [:],
        darkLyrics: LyricsResult = .notFound,
        music: MockMusicClient? = nil
    ) async -> BatchViewModel {
        let model = await makeModel(
            albumTracks: sampleTracks, genius: genius, darkLyrics: darkLyrics, music: music
        )
        await model.loadAlbum()
        return model
    }

    // MARK: - 載入（C-01/02/18/23/24/26）

    // C-01：條件是「資料為空」，不是「首次切入」（py:396）
    @Test func activatingTabWithEmptyListLoadsAlbum() async {
        let model = await makeModel(albumTracks: sampleTracks)

        model.tabActivated()
        await model.loadTask?.value

        #expect(model.tracks.count == 3)
        #expect(model.listState == .loaded)
    }

    // C-01 反向：已有資料再切入不重載
    @Test func activatingTabWithLoadedListDoesNotReload() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        let model = await loadedModel(music: music)

        await music.setAlbumTracks([])      // 若重載會清空
        model.tabActivated()
        await model.loadTask?.value

        #expect(model.tracks.count == 3, "已有資料不得重新載入")
    }

    // C-02＋C-23：載入中列表區佔位，同時把三態文案設在 Editor 狀態欄
    @Test func loadingPublishesPlaceholderAndEditorStatus() async {
        let model = await makeModel(albumTracks: sampleTracks)
        var editorStatuses: [String] = []
        model.onEditorStatus = { editorStatuses.append($0) }

        #expect(model.listState == .idle)
        await model.loadAlbum()

        #expect(editorStatuses == [StatusText.processingAlbumBatch, StatusText.albumLoaded])
        #expect(model.listState == .loaded)
    }

    // C-02＋C-18：載入中列表區呈佔位、全部按鈕禁用。
    // 這個狀態在真機上一閃而過，目視不可靠，故以閘門在測試中定格
    @Test func loadingStateIsObservableWhileFetching() async {
        let gate = LyricsGate()
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(sampleTracks)
        await music.setAlbumTracksGate(gate)
        let model = await makeModel(albumTracks: sampleTracks, music: music)

        let task = Task { await model.loadAlbum() }
        await waitUntil { model.listState == .loading }

        #expect(model.listState == .loading)
        #expect(model.isLoadingAlbum, "載入期間全部按鈕禁用")

        await gate.open()
        await task.value

        #expect(model.listState == .loaded)
        #expect(!model.isLoadingAlbum)
    }

    // C-24：有資料取首曲的 album 欄位
    @Test func loadedAlbumTakesHeaderNameFromFirstTrack() async {
        let model = await loadedModel()

        #expect(model.albumName == "Damage Done")
    }

    // C-24：空專輯 → "No Data / Album"（初始值為 "Loading..."）
    @Test func emptyAlbumShowsNoDataHeader() async {
        let model = await makeModel(albumTracks: [])

        #expect(model.albumName == StatusText.albumLoadingPlaceholder)
        await model.loadAlbum()

        #expect(model.albumName == StatusText.noDataAlbum)
        #expect(model.listState == .loaded, "空專輯不是失敗態")
    }

    // C-26：原版 get_album_tracks 的 except 吞掉全部異常回 []（py:1180-1182），
    // 故 JS 的 catch 分支實際不可達——照搬此語義：權限被拒＝空專輯，不是失敗態
    @Test func musicFailureIsSwallowedAsEmptyAlbumLikePython() async {
        let music = MockMusicClient(script: [.failure(.permissionDenied)])
        let model = await makeModel(albumTracks: sampleTracks, music: music)

        await model.loadAlbum()

        #expect(model.tracks.isEmpty)
        #expect(model.listState == .loaded)
        #expect(model.albumName == StatusText.noDataAlbum)
    }

    // C-18：只有「載入專輯」停輪詢（其餘三動作照跑）
    @Test func onlyAlbumLoadSuspendsPolling() async {
        let model = await makeModel(albumTracks: sampleTracks)
        var busyFlags: [Bool] = []
        model.onBusyChange = { busyFlags.append($0) }

        await model.loadAlbum()

        #expect(busyFlags == [true, false])
    }

    // MARK: - 列表與選中（C-04/05/06/29）

    // C-04：順序＝AE 回傳序，不套用 sortedForDisplay()（那是 M7 Cover Flow 專用）
    @Test func tracksKeepAppleEventsOrderWithoutSorting() async {
        let unordered: [AlbumTrack] = [
            .fixture(id: "T9", title: "Ninth", disc: 1, track: 9),
            .fixture(id: "T2", title: "Second", disc: 1, track: 2),
        ]
        let model = await makeModel(albumTracks: unordered)

        await model.loadAlbum()

        #expect(model.tracks.map(\.persistentID) == ["T9", "T2"])
    }

    // C-04：序號＝列表索引+1 補零，與 trackNumber 無關
    @Test func rowNumberIsListIndexPaddedToTwoDigits() async {
        let model = await loadedModel()

        #expect(model.rowNumber(at: 0) == "01")
        #expect(model.rowNumber(at: 2) == "03")
        #expect(model.rowNumber(at: 11) == "12")
    }

    // C-29（⚠️ 已拍板）：純空白＝缺詞
    @Test func whitespaceOnlyLyricsCountAsMissing() async {
        let model = await loadedModel()

        #expect(model.missingTracks.map(\.persistentID) == ["T2", "T3"])
    }

    // C-06：選中→預覽填充＋meta "Artist - Title"
    @Test func selectingTrackFillsPreviewAndMeta() async {
        let model = await loadedModel()

        #expect(model.previewMeta == "--", "未選中時為佔位符（py:234）")
        model.select("T1")

        #expect(model.selectedID == "T1")
        #expect(model.previewText == "alpha body")
        #expect(model.previewMeta == "Dark Tranquillity - Alpha")
    }

    // MARK: - Fetch Missing（C-08/09/11/12/18/27/30）

    // C-08
    @Test func fetchMissingWithNothingMissingShowsAlert() async {
        let model = await makeModel(albumTracks: [.fixture(id: "T1", lyrics: "has body")])
        await model.loadAlbum()

        await model.fetchMissing()

        #expect(model.alertMessage == StatusText.noMissingLyrics)
        #expect(model.statusText == StatusText.batchReady, "不得進入抓詞流程")
    }

    // C-09＋C-27：串行逐條，進度格式 "Fetching (i/n): title"
    @Test func fetchMissingRunsSeriallyWithProgressText() async {
        let gate = LyricsGate()
        let source = RecordingLyricsSource(["Beta": .found("beta body")], gate: gate, gateAtCall: 1)
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(sampleTracks)
        let model = BatchViewModel(
            lyricsService: LyricsService(genius: source, darkLyrics: StubLyricsSource(.notFound)),
            music: music
        )
        await model.loadAlbum()

        let task = Task { await model.fetchMissing() }
        await waitForQueries(source, atLeast: 1)

        #expect(model.statusText == StatusText.fetchingProgress(1, of: 2, title: "Beta"))
        // 第一首卡在 gate 上；再讓出若干次確認第二首沒有並發插進來
        for _ in 0..<50 { await Task.yield() }
        #expect(await source.queries.count == 1, "第一首未完成前不得發第二首（串行）")

        await gate.open()
        await task.value

        #expect(await source.queries.count == 2)
        #expect(model.statusText == StatusText.fetchComplete)   // C-12
    }

    // C-10 決策 5：Batch 路徑要傳 album（原版 py:2229 不傳）
    @Test func fetchMissingPassesAlbumToSource() async {
        let source = RecordingLyricsSource([:])
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(sampleTracks)
        let model = BatchViewModel(
            lyricsService: LyricsService(genius: source, darkLyrics: StubLyricsSource(.notFound)),
            music: music
        )
        await model.loadAlbum()

        await model.fetchMissing()

        #expect(await source.queries.allSatisfy { $0.album == "Damage Done" })
    }

    // C-11：命中即時寫回列表，選中項同步預覽
    @Test func fetchedLyricsUpdateListAndSelectedPreview() async {
        let model = await loadedModel(genius: ["Beta": .found("beta body")])
        model.select("T2")

        await model.fetchMissing()

        #expect(model.tracks.first { $0.persistentID == "T2" }?.lyrics == "beta body")
        #expect(model.previewText == "beta body")
        #expect(model.tracks.first { $0.persistentID == "T3" }?.lyrics == "   \n  ", "未命中者不得被改寫")
    }

    // C-30（⚠️）：來源回錯誤時不得當成歌詞寫入列表
    @Test func sourceErrorIsNeverStoredAsLyrics() async {
        let model = await loadedModel(
            genius: ["Beta": .error("Genius Error: boom")],
            darkLyrics: .error("Error: blocked")
        )
        model.select("T2")

        await model.fetchMissing()

        #expect(model.tracks.first { $0.persistentID == "T2" }?.lyrics == "")
        #expect(model.previewText == "", "錯誤訊息不得污染預覽框")
    }

    // C-18：Fetch Missing 只禁自己的按鈕，不動輪詢
    @Test func fetchMissingDisablesOnlyItsOwnButton() async {
        let gate = LyricsGate()
        let source = RecordingLyricsSource(["Beta": .found("b")], gate: gate, gateAtCall: 1)
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(sampleTracks)
        let model = BatchViewModel(
            lyricsService: LyricsService(genius: source, darkLyrics: StubLyricsSource(.notFound)),
            music: music
        )
        await model.loadAlbum()
        var busyFlags: [Bool] = []
        model.onBusyChange = { busyFlags.append($0) }

        let task = Task { await model.fetchMissing() }
        await waitUntil { model.isFetchingMissing }

        #expect(model.isFetchingMissing)
        #expect(!model.isLoadingAlbum, "不得禁用其餘按鈕")
        #expect(!model.isImportingAll)
        #expect(busyFlags.isEmpty, "抓詞期間輪詢照跑（py 未調 toggleBusy）")

        await gate.open()
        await task.value
        #expect(!model.isFetchingMissing)
    }

    // MARK: - Import Selected（C-13/14/28）

    // C-13
    @Test func importSelectedWithoutSelectionShowsAlert() async {
        let model = await loadedModel()

        await model.importSelected()

        #expect(model.alertMessage == StatusText.selectTrackFirst)
    }

    // C-14＋C-28：寫入預覽框文本、文案帶句點、觸發 confetti
    @Test func importSelectedWritesPreviewTextAndTriggersConfetti() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        let model = await loadedModel(music: music)
        model.select("T2")
        model.previewText = "edited body"

        await model.importSelected()

        #expect(await music.writes["T2"] == "edited body")
        #expect(model.statusText == StatusText.batchSaved)
        #expect(model.confettiTrigger == 1)
        #expect(model.tracks.first { $0.persistentID == "T2" }?.lyrics == "edited body")
    }

    // C-28：寫入回 false → "Save failed."
    @Test func importSelectedReportsSaveFailedWhenWriteReturnsFalse() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setSetLyricsOutcome(.success(false))
        let model = await loadedModel(music: music)
        model.select("T1")

        await model.importSelected()

        #expect(model.statusText == StatusText.batchSaveFailed)
        #expect(model.confettiTrigger == 0)
    }

    // C-28：拋錯 → "Error saving."
    @Test func importSelectedReportsErrorSavingWhenMusicThrows() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setSetLyricsOutcome(.failure(.permissionDenied))
        let model = await loadedModel(music: music)
        model.select("T1")

        await model.importSelected()

        #expect(model.statusText == StatusText.batchErrorSaving)
    }

    // MARK: - Import All（C-15/16/22/27）

    // C-15：先確認才動作
    @Test func importAllRequiresConfirmationFirst() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        let model = await loadedModel(music: music)

        model.requestImportAll()
        #expect(model.isConfirmingImportAll)
        #expect(await music.writes.isEmpty, "確認前不得寫入")

        model.cancelImportAll()
        #expect(!model.isConfirmingImportAll)
        #expect(await music.writes.isEmpty)
    }

    // C-22：確認後才發現無可寫項（原版順序即如此：confirm 在 filter 之前）
    @Test func importAllWithNoLyricsShowsAlertAfterConfirmation() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        let model = await makeModel(albumTracks: [.fixture(id: "T2", lyrics: "")], music: music)
        await model.loadAlbum()

        model.requestImportAll()
        await model.confirmImportAll()

        #expect(model.alertMessage == StatusText.noTracksHaveLyrics)
        #expect(await music.writes.isEmpty)
    }

    // C-16＋C-27：串行寫入全部有詞項 → "All saved." ＋confetti
    @Test func importAllWritesEveryTrackThatHasLyrics() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        let model = await loadedModel(music: music)

        model.requestImportAll()
        await model.confirmImportAll()

        let writes = await music.writes
        #expect(writes.keys.sorted() == ["T1"], "只寫有詞項；純空白（T3）依 C-29 視為缺詞")
        #expect(model.statusText == StatusText.allSaved)
        #expect(model.confettiTrigger == 1)
    }

    // C-27：Import All 的逐條進度格式（同樣一閃而過，以閘門定格）
    @Test func importAllReportsPerTrackProgress() async {
        let gate = LyricsGate()
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setWriteGate(gate)
        let model = await loadedModel(music: music)      // 三首中只有 T1（Alpha）有詞

        model.requestImportAll()
        let task = Task { await model.confirmImportAll() }
        await waitUntil { model.statusText == StatusText.savingProgress(1, of: 1, title: "Alpha") }

        #expect(model.statusText == StatusText.savingProgress(1, of: 1, title: "Alpha"))
        #expect(model.isImportingAll)

        await gate.open()
        await task.value

        #expect(model.statusText == StatusText.allSaved)
        #expect(!model.isImportingAll)
    }

    // C-27：Import Selected 的 "Saving {title}..."（此條在原版可觀察，後面接 await）
    @Test func importSelectedReportsSavingProgress() async {
        let gate = LyricsGate()
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setWriteGate(gate)
        let model = await loadedModel(music: music)
        model.select("T1")

        let task = Task { await model.importSelected() }
        await waitUntil { model.statusText == StatusText.savingTrack("Alpha") }

        #expect(model.statusText == StatusText.savingTrack("Alpha"))

        await gate.open()
        await task.value

        #expect(model.statusText == StatusText.batchSaved)
    }

    // MARK: - 專輯切換與 sessionID 守衛（C-17/19）

    // C-17：切專輯清空列表；Batch 可見則自動重載
    @Test func albumChangeClearsListAndReloadsWhenVisible() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        let model = await loadedModel(music: music)
        model.tabActivated()

        await music.setAlbumTracks([.fixture(id: "N1", title: "NewOne")])
        model.handle(.albumChanged("Dark Tranquillity\u{1}Other Album"))
        await model.loadTask?.value

        #expect(model.tracks.map(\.persistentID) == ["N1"])
    }

    // C-17：Batch 不可見時只清空、不重載
    @Test func albumChangeClearsListWithoutReloadWhenHidden() async {
        let model = await loadedModel()
        model.tabDeactivated()

        model.handle(.albumChanged("Dark Tranquillity\u{1}Other Album"))
        await model.loadTask?.value

        #expect(model.tracks.isEmpty)
    }

    // C-19：載入進行中切專輯 → 舊載入的回寫必須被 sessionID 擋掉。
    // 與下一條的差別：那條擋的是「抓詞循環」，這條擋的是「載入本身」——
    // 載入路徑原先無守衛，過期結果會把已切走的舊專輯重新填回列表（Phase 3 codex 指出）。
    @Test func staleAlbumLoadDoesNotRepopulateAfterAlbumChange() async {
        let gate = LyricsGate()
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(sampleTracks)
        await music.setAlbumTracksGate(gate)
        let model = await makeModel(albumTracks: sampleTracks, music: music)
        model.tabDeactivated()   // 隔離變量：不可見則 albumChanged 只清空、不重載

        let stale = Task { await model.loadAlbum() }
        await waitUntil { model.listState == .loading }

        // 載入卡在 AE 回應上時切專輯：列表清空、sessionID 遞增
        model.handle(.albumChanged("Dark Tranquillity\u{1}Other Album"))
        #expect(model.tracks.isEmpty)

        await gate.open()
        await stale.value

        #expect(model.tracks.isEmpty, "過期載入的結果不得回寫進已切走的專輯")
        #expect(model.albumName == StatusText.albumLoadingPlaceholder, "header 不得倒回舊專輯名")
    }

    // C-19：抓詞進行中專輯重載 → 舊循環的回寫必須被 sessionID 擋掉
    @Test func staleFetchLoopStopsWritingAfterAlbumReload() async {
        let gate = LyricsGate()
        let source = RecordingLyricsSource(["Beta": .found("stale body")], gate: gate, gateAtCall: 1)
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(sampleTracks)
        let model = BatchViewModel(
            lyricsService: LyricsService(genius: source, darkLyrics: StubLyricsSource(.notFound)),
            music: music
        )
        await model.loadAlbum()
        model.tabActivated()

        let task = Task { await model.fetchMissing() }
        await waitForQueries(source, atLeast: 1)   // 確認第一首確實卡在 gate 上，再製造專輯切換

        // 抓詞卡在第一首時切專輯 → 重載成新列表
        await music.setAlbumTracks([.fixture(id: "N1", title: "NewOne", lyrics: "")])
        model.handle(.albumChanged("Dark Tranquillity\u{1}Other Album"))
        await model.loadTask?.value
        await gate.open()
        await task.value

        #expect(model.tracks.map(\.persistentID) == ["N1"])
        #expect(model.tracks.first?.lyrics == "", "過期循環的結果不得寫進新列表")
        #expect(await source.queries.count == 1, "過期循環必須中止，不得續抓第二首")
    }
}

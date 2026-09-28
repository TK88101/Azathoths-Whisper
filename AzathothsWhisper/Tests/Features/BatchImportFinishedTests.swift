import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 2026-09-26-lyrics-notification §4.3／§4.3a／§4.6：
// Batch 的寫入結果由 BatchViewModel 判定 outcome（AppModel 與通知文案不重算），
// 同一個判定決定狀態欄、彩紙與完成事件；事件在狀態欄與彩紙**之後**送出。
@MainActor
@Suite("BatchViewModel 匯入完成事件")
struct BatchImportFinishedTests {
    @MainActor
    final class Recorder {
        var results: [BatchImportResult] = []
        /// 事件送出當下的狀態欄與彩紙計數（驗「事件在彩紙之後」）
        var statusAtEvent: [String] = []
        var confettiAtEvent: [Int] = []
    }

    private func loadedModel(_ tracks: [AlbumTrack], music: MockMusicClient) async -> (BatchViewModel, Recorder) {
        await music.setAlbumTracks(tracks)
        let model = BatchViewModel(lyricsService: .scripted(genius: [:]), music: music)
        let recorder = Recorder()
        model.onImportFinished = { [unowned model] result in
            recorder.results.append(result)
            recorder.statusAtEvent.append(model.statusText)
            recorder.confettiAtEvent.append(model.confettiTrigger)
        }
        await model.loadAlbum()
        return (model, recorder)
    }

    private func music() -> MockMusicClient {
        MockMusicClient(script: [.track(.fixture(), lyrics: "")])
    }

    private func track(_ id: String, _ title: String, lyrics: String = "body") -> AlbumTrack {
        .fixture(id: id, artist: "Opeth", title: title, album: "Blackwater Park", lyrics: lyrics)
    }

    private func summary(trackCount: Int, succeeded: [String], failed: [String] = []) -> BatchWriteSummary {
        BatchWriteSummary(
            artist: "Opeth", album: "Blackwater Park", albumTrackCount: trackCount,
            succeeded: succeeded, failed: failed
        )
    }

    // MARK: - Import All：四種 outcome（§4.3a 表）

    @Test func allSucceededKeepsAllSavedAndConfettiThenReports() async {
        let (model, recorder) = await loadedModel(
            [track("T1", "One"), track("T2", "Two"), track("T3", "Three", lyrics: "")], music: music()
        )

        model.requestImportAll()
        await model.confirmImportAll()

        #expect(model.statusText == StatusText.allSaved)
        #expect(model.confettiTrigger == 1)
        #expect(recorder.results == [.batch(summary(trackCount: 3, succeeded: ["One", "Two"]), .allSucceeded)])
        #expect(recorder.statusAtEvent == [StatusText.allSaved], "事件在狀態欄之後")
        #expect(recorder.confettiAtEvent == [1], "事件在彩紙之後（切頁計時的起點）")
    }

    @Test func someFailedShowsCountsWithoutConfetti() async {
        let music = music()
        await music.setSetLyricsOutcome(.success(false), for: "T2")
        await music.setSetLyricsOutcome(.failure(.permissionDenied), for: "T3")
        let (model, recorder) = await loadedModel(
            [track("T1", "One"), track("T2", "Two"), track("T3", "Three"), track("T4", "Four")], music: music
        )

        model.requestImportAll()
        await model.confirmImportAll()

        #expect(model.statusText == "Saved 2 of 4. 2 failed.")
        #expect(model.confettiTrigger == 0)
        #expect(recorder.results == [
            .batch(summary(trackCount: 4, succeeded: ["One", "Four"], failed: ["Two", "Three"]), .someFailed),
        ])
    }

    @Test func allFailedShowsSaveFailedWithoutConfetti() async {
        let music = music()
        await music.setSetLyricsOutcome(.success(false))
        let (model, recorder) = await loadedModel([track("T1", "One"), track("T2", "Two")], music: music)

        model.requestImportAll()
        await model.confirmImportAll()

        #expect(model.statusText == StatusText.batchSaveFailed)
        #expect(model.confettiTrigger == 0)
        #expect(recorder.results == [.batch(summary(trackCount: 2, succeeded: [], failed: ["One", "Two"]), .allFailed)])
    }

    /// 寫入途中切專輯：只含實際寫入的曲目，專輯資訊取自寫入前的快照（切專輯會把 tracks 清空、albumName 改成 Loading）
    @Test func staleBatchReportsOnlyWhatWasWrittenUnderTheOldAlbum() async {
        let gate = LyricsGate()
        let music = music()
        await music.setWriteGate(gate)
        let (model, recorder) = await loadedModel([track("T1", "One"), track("T2", "Two")], music: music)

        model.requestImportAll()
        let task = Task { await model.confirmImportAll() }
        await waitUntil { model.statusText == StatusText.savingProgress(1, of: 2, title: "One") }
        model.handle(.albumChanged("Other\u{1}Album"))
        await gate.open()
        await task.value

        #expect(recorder.results == [.batch(summary(trackCount: 2, succeeded: ["One"]), .stale)])
        #expect(model.statusText == StatusText.savingProgress(1, of: 2, title: "One"), "stale 不寫狀態欄（原版）")
        #expect(model.confettiTrigger == 0, "stale 不放彩紙（原版）")
    }

    @Test func importAllWithNothingToSaveReportsNothing() async {
        let (model, recorder) = await loadedModel([track("T1", "One", lyrics: "")], music: music())

        model.requestImportAll()
        await model.confirmImportAll()

        #expect(model.alertMessage == StatusText.noTracksHaveLyrics)
        #expect(recorder.results.isEmpty)
    }

    // MARK: - Import Selected

    @Test func importSelectedSuccessReportsSingleAfterConfetti() async {
        let (model, recorder) = await loadedModel([track("T1", "One")], music: music())
        model.select("T1")

        await model.importSelected()

        #expect(recorder.results == [.single(artist: "Opeth", title: "One", album: "Blackwater Park", isStale: false)])
        #expect(recorder.confettiAtEvent == [1])
    }

    @Test func importSelectedStaleStillReportsTheWrite() async {
        let gate = LyricsGate()
        let music = music()
        await music.setWriteGate(gate)
        let (model, recorder) = await loadedModel([track("T1", "One")], music: music)
        model.select("T1")

        let task = Task { await model.importSelected() }
        await waitUntil { model.statusText == StatusText.savingTrack("One") }
        model.handle(.albumChanged("Other\u{1}Album"))
        await gate.open()
        await task.value

        #expect(recorder.results == [.single(artist: "Opeth", title: "One", album: "Blackwater Park", isStale: true)])
        #expect(model.confettiTrigger == 0)
    }

    @Test("Import Selected 失敗不送", arguments: [
        Result<Bool, MusicError>.success(false), .failure(.permissionDenied),
    ])
    func importSelectedFailureReportsNothing(outcome: Result<Bool, MusicError>) async {
        let music = music()
        await music.setSetLyricsOutcome(outcome)
        let (model, recorder) = await loadedModel([track("T1", "One")], music: music)
        model.select("T1")

        await model.importSelected()

        #expect(recorder.results.isEmpty)
    }

    // MARK: - 新工作世代（§4.6 ⑧：只有真正開始新工作才遞增）

    @Test func realOperationsAdvanceTheGeneration() async {
        let (model, _) = await loadedModel([track("T1", "One"), track("T2", "Two", lyrics: "")], music: music())

        var last = model.operationGeneration
        func expectAdvanced(_ label: String) {
            #expect(model.operationGeneration > last, "\(label) 應遞增")
            last = model.operationGeneration
        }

        await model.fetchMissing()
        expectAdvanced("Fetch Missing")
        model.select("T1")
        await model.importSelected()
        expectAdvanced("Import Selected")
        model.requestImportAll()
        await model.confirmImportAll()
        expectAdvanced("Import All")
        await model.loadAlbum()
        expectAdvanced("載入專輯")
        model.handle(.albumChanged("Other\u{1}Album"))
        expectAdvanced("切換專輯")
    }

    @Test func browsingAndNoOpActionsKeepTheGeneration() async {
        let (model, _) = await loadedModel([track("T1", "One")], music: music())
        let before = model.operationGeneration

        model.select("T1")                 // 點選看預覽
        model.requestImportAll()           // 只開確認框（由彈框規則⑦處理）
        model.cancelImportAll()
        await model.fetchMissing()         // 沒有缺詞 → 提示框，沒開始工作
        model.alertMessage = nil

        #expect(model.operationGeneration == before)
    }

    @Test func noOpImportsKeepTheGeneration() async {
        let (model, _) = await loadedModel([track("T1", "One", lyrics: "")], music: music())
        let before = model.operationGeneration

        await model.importSelected()       // 沒選曲 → 提示框
        model.alertMessage = nil
        model.requestImportAll()
        await model.confirmImportAll()     // 沒有有詞曲 → 提示框

        #expect(model.operationGeneration == before)
    }

    @Test func savedSomeFailedText() {
        #expect(StatusText.savedSomeFailed(saved: 6, of: 8, failed: 2) == "Saved 6 of 8. 2 failed.")
    }
}

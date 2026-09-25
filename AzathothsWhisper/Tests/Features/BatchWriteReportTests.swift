import Foundation
import Testing

@testable import AzathothsWhisper

// 2026-09-25 使用者回報：Batch 匯入成功後 Cover Flow 徽章不刷新（計劃 2026-09-25-batch-import-coverflow-refresh §3.1）。
// Batch 每筆**成功**寫入都經 `onLyricsWritten` 回報（寫入目標, 寫入的文字）；false／throw 不報；
// 寫入已落檔就回報，不受 Batch session（專輯切換）約束。
@MainActor
@Suite("BatchViewModel 寫入回報")
struct BatchWriteReportTests {
    struct Report: Equatable {
        let persistentID: String
        let text: String
    }

    @MainActor
    final class Recorder {
        var reports: [Report] = []
    }

    private func loadedModel(_ tracks: [AlbumTrack], music: MockMusicClient) async -> (BatchViewModel, Recorder) {
        await music.setAlbumTracks(tracks)
        let model = BatchViewModel(lyricsService: .scripted(genius: [:]), music: music)
        let recorder = Recorder()
        model.onLyricsWritten = { recorder.reports.append(Report(persistentID: $0, text: $1)) }
        await model.loadAlbum()
        return (model, recorder)
    }

    private func music() -> MockMusicClient {
        MockMusicClient(script: [.track(.fixture(), lyrics: "")])
    }

    // MARK: - Import Selected（AC2／AC3／AC7）

    @Test func importSelectedReportsTheWrittenText() async {
        let (model, recorder) = await loadedModel([.fixture(id: "T1", title: "Alpha", lyrics: "")], music: music())
        model.select("T1")
        model.previewText = "fetched body"

        await model.importSelected()

        #expect(recorder.reports == [Report(persistentID: "T1", text: "fetched body")])
    }

    @Test func importSelectedDoesNotReportWhenTheWriteReturnsFalse() async {
        let music = music()
        await music.setSetLyricsOutcome(.success(false))
        let (model, recorder) = await loadedModel([.fixture(id: "T1", lyrics: "body")], music: music)
        model.select("T1")

        await model.importSelected()

        #expect(recorder.reports.isEmpty)
    }

    @Test func importSelectedDoesNotReportWhenMusicThrows() async {
        let music = music()
        await music.setSetLyricsOutcome(.failure(.permissionDenied))
        let (model, recorder) = await loadedModel([.fixture(id: "T1", lyrics: "body")], music: music)
        model.select("T1")

        await model.importSelected()

        #expect(recorder.reports.isEmpty)
    }

    /// AC7：寫入途中切專輯（session 作廢）——檔案已寫入，仍要回報
    @Test func importSelectedStillReportsWhenTheAlbumChangesDuringTheWrite() async {
        let gate = LyricsGate()
        let music = music()
        await music.setWriteGate(gate)
        let (model, recorder) = await loadedModel([.fixture(id: "T1", title: "Alpha", lyrics: "body")], music: music)
        model.select("T1")

        let task = Task { await model.importSelected() }
        await waitUntil { model.statusText == StatusText.savingTrack("Alpha") }
        model.handle(.albumChanged("Other\u{1}Album"))
        await gate.open()
        await task.value

        #expect(recorder.reports == [Report(persistentID: "T1", text: "body")])
    }

    // MARK: - Import All（AC1／AC3／AC7）

    @Test func importAllReportsEverySuccessfulWriteInOrder() async {
        let music = music()
        await music.setSetLyricsOutcome(.success(false), for: "T2")
        await music.setSetLyricsOutcome(.failure(.permissionDenied), for: "T3")
        let tracks: [AlbumTrack] = [
            .fixture(id: "T1", title: "One", lyrics: "one body"),
            .fixture(id: "T2", title: "Two", lyrics: "two body"),
            .fixture(id: "T3", title: "Three", lyrics: "three body"),
            .fixture(id: "T4", title: "Four", lyrics: "four body"),
            .fixture(id: "T5", title: "Five", lyrics: ""),
        ]
        let (model, recorder) = await loadedModel(tracks, music: music)

        model.requestImportAll()
        await model.confirmImportAll()

        #expect(recorder.reports == [
            Report(persistentID: "T1", text: "one body"),
            Report(persistentID: "T4", text: "four body"),
        ], "false／throw 不報；缺詞曲不寫也不報")
    }

    /// AC7：第一首寫入中切專輯——它已落檔、要回報；之後的循環依 C-19 中止，不寫也不報
    @Test func importAllReportsTheWriteThatFinishesAfterAnAlbumChange() async {
        let gate = LyricsGate()
        let music = music()
        await music.setWriteGate(gate)
        let tracks: [AlbumTrack] = [
            .fixture(id: "T1", title: "One", lyrics: "one body"),
            .fixture(id: "T2", title: "Two", lyrics: "two body"),
        ]
        let (model, recorder) = await loadedModel(tracks, music: music)

        model.requestImportAll()
        let task = Task { await model.confirmImportAll() }
        await waitUntil { model.statusText == StatusText.savingProgress(1, of: 2, title: "One") }
        model.handle(.albumChanged("Other\u{1}Album"))
        await gate.open()
        await task.value

        #expect(recorder.reports == [Report(persistentID: "T1", text: "one body")])
        #expect(await music.writes.keys.sorted() == ["T1"])
    }
}

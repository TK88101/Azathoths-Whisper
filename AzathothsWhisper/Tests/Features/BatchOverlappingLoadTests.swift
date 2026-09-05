import Foundation
import Testing

@testable import AzathothsWhisper

// 重疊載入場景（C-18／C-19）。
//
// 由來：本組的第一條用例原是 2026-08-15 撤回的那條——它讓 test run 永久掛起，
// xcodebuild 報 `runner hung before establishing connection` 且 0 條測試執行。
// 2026-08-23 查明根因為 LyricsGate 單槽 continuation（見 docs/plans/2026-08-23-m6-closeout.md
// 附錄 A1），修復後轉為常規回歸用例。
@MainActor
@Suite("BatchOverlappingLoad")
struct BatchOverlappingLoadTests {
    private var sampleTracks: [AlbumTrack] {
        [
            .fixture(id: "T1", title: "Alpha", lyrics: "alpha body"),
            .fixture(id: "T2", title: "Beta", lyrics: ""),
        ]
    }

    private func makeGatedModel(
        gate: LyricsGate
    ) async -> (BatchViewModel, MockMusicClient) {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(sampleTracks)
        await music.setAlbumTracksGate(gate)
        let model = BatchViewModel(lyricsService: .scripted(genius: [:]), music: music)
        return (model, music)
    }

    /// 逐次閘門版：第一次載入等 gateA、第二次等 gateB，
    /// 讓兩個重疊載入能**分別**完成（單一 broadcast gate 會同時放行兩者）
    private func makeQueueGatedModel(
        _ gateA: LyricsGate, _ gateB: LyricsGate
    ) async -> (BatchViewModel, MockMusicClient) {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(sampleTracks)
        await music.setAlbumTracksGateQueue([gateA, gateB])
        let model = BatchViewModel(lyricsService: .scripted(genius: [:]), music: music)
        return (model, music)
    }

    /// 兩個重疊載入都必須收束（原單槽 gate 下第一個永久掛起 → 整個 test run 掛死）
    @Test func overlappingLoadsBothComplete() async {
        let gate = LyricsGate()
        let (model, _) = await makeGatedModel(gate: gate)

        model.tabActivated()
        let firstTask = model.loadTask
        await waitUntil { model.isLoadingAlbum }

        // tab 連點：tracks 仍為空，C-01 判定為真 → 再次 startLoad（原版同構行為，上游 §8.2 駁回項 1）
        model.tabActivated()
        let secondTask = model.loadTask
        await settle()

        await gate.open()
        await firstTask?.value
        await secondTask?.value

        #expect(model.tracks.count == 2)
        #expect(model.listState == .loaded)
    }

    // MARK: - C-18 偏差：busy 不得在最後一個載入完成前落下

    /// 上游 §8.3 codex 勝方意見：`loadAlbum()` 的 `defer { setLoadingAlbum(false) }`
    /// 在過期路徑照跑；舊載入先完成時按鈕提前啟用、輪詢提前恢復。
    ///
    /// 切專輯路徑在**原版不可能發生**（輪詢在 isBusy 時跳過 py:508-510，載入期間偵測不到
    /// 專輯變更），故此空窗違反已簽署的 C-18，非 1:1 保真。
    @Test func overlappingLoadKeepsBusyUntilLastCompletes() async {
        let gateA = LyricsGate()
        let gateB = LyricsGate()
        let (model, _) = await makeQueueGatedModel(gateA, gateB)
        var busyLog: [Bool] = []
        model.onBusyChange = { busyLog.append($0) }

        model.tabActivated()
        let first = model.loadTask
        await waitUntil { model.isLoadingAlbum }

        model.tabActivated()
        let second = model.loadTask
        await settle()

        // 只放行第一個載入
        await gateA.open()
        await first?.value

        #expect(model.isLoadingAlbum, "第二個載入仍在飛，busy 不得落下")
        #expect(!busyLog.contains(false), "onBusyChange 不得在最後一個載入完成前發出 false")

        await gateB.open()
        await second?.value

        #expect(!model.isLoadingAlbum, "最後一個載入完成後 busy 必須落下")
        #expect(busyLog == [true, false], "整個重疊區間只應有一次 true 與一次 false")
    }

    /// C-18 的**真正效果**：輪詢必須停到最後一個載入完成。
    /// 只斷言 `isLoadingAlbum` 與 callback 不夠——`onBusyChange` 經
    /// `Task { await monitor.setBusy(...) }` 異步跳板送出，可能「測試綠但實際仍有 polling window」。
    @Test func overlappingLoadSuspendsPollingUntilLastCompletes() async {
        let gateA = LyricsGate()
        let gateB = LyricsGate()
        let (model, music) = await makeQueueGatedModel(gateA, gateB)
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        model.onBusyChange = { busy in
            await monitor.setBusy(busy, source: .batch)   // 與 AppModel.swift:76 同構
        }

        model.tabActivated()
        let first = model.loadTask
        await waitUntil { model.isLoadingAlbum }
        // 不再需要 settle()：onBusyChange 已是 async，setBusy 在同一條 await 鏈上完成

        model.tabActivated()
        let second = model.loadTask
        await settle()

        await gateA.open()
        await first?.value

        // 第一個已完成、第二個仍在飛：此時驅動輪詢，必須被 busy 擋掉
        let callsBefore = await music.currentTrackCalls
        await monitor.tick()
        let callsAfter = await music.currentTrackCalls
        #expect(callsAfter == callsBefore, "重疊載入未結束時輪詢必須仍被擋住（C-18）")

        await gateB.open()
        await second?.value
    }

    // MARK: - loadsInFlight 不變量（loadsInFlight == 活躍 loadAlbum 呼叫數）

    /// ①單一載入的正常路徑：恰好一次 true、一次 false
    @Test func singleLoadEmitsExactlyOneBusyPair() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(sampleTracks)
        let model = BatchViewModel(lyricsService: .scripted(genius: [:]), music: music)
        var busyLog: [Bool] = []
        model.onBusyChange = { busyLog.append($0) }

        await model.loadAlbum()
        #expect(busyLog == [true, false])
    }

    /// ②連續多輪載入不得讓計數下溢（下溢會讓 busy 永久卡在 false，輪詢再也擋不住）
    @Test func repeatedLoadsNeverUnderflow() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(sampleTracks)
        let model = BatchViewModel(lyricsService: .scripted(genius: [:]), music: music)
        var busyLog: [Bool] = []
        model.onBusyChange = { busyLog.append($0) }

        for _ in 0..<5 { await model.loadAlbum() }

        #expect(busyLog == [true, false, true, false, true, false, true, false, true, false])
        #expect(!model.isLoadingAlbum)
    }

    /// ③錯誤路徑同樣配對：`fetchAlbumTracks` 吞掉異常回 []（C-26），
    /// 但 `defer` 的 false 必須照常抵達，否則 busy 永久卡在 true、輪詢再也不恢復
    @Test func failedLoadStillReleasesBusy() async {
        let music = MockMusicClient(script: [.failure(.permissionDenied)])
        let model = BatchViewModel(lyricsService: .scripted(genius: [:]), music: music)
        var busyLog: [Bool] = []
        model.onBusyChange = { busyLog.append($0) }

        await model.loadAlbum()

        #expect(busyLog == [true, false], "異常路徑的 busy 必須配對釋放")
        #expect(!model.isLoadingAlbum)
    }

    /// ④舊 task 被 `loadTask` 覆蓋**不代表**舊 task 被取消——它仍會跑完並釋放自己那一份計數。
    /// （不取消是刻意的：tab 連點的重疊載入是原版可觀察行為，上游 §8.2 駁回項 1）
    @Test func overwrittenLoadTaskStillReleasesItsCount() async {
        let gateA = LyricsGate()
        let gateB = LyricsGate()
        let (model, _) = await makeQueueGatedModel(gateA, gateB)

        model.tabActivated()
        let overwritten = model.loadTask
        await waitUntil { model.isLoadingAlbum }
        model.tabActivated()
        let current = model.loadTask
        await settle()

        #expect(overwritten != current, "第二次 startLoad 必須覆蓋 loadTask")
        #expect(overwritten?.isCancelled == false, "被覆蓋的 task 不得被取消")

        await gateB.open()
        await current?.value
        #expect(model.isLoadingAlbum, "被覆蓋的舊載入仍在飛，busy 不得落下")

        await gateA.open()
        await overwritten?.value
        #expect(!model.isLoadingAlbum, "舊載入釋放自己那份計數後才歸零")
    }
}

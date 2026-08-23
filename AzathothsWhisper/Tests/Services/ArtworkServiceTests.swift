import AppKit
import Foundation
import Testing

@testable import AzathothsWhisper

// 封面取圖編排（M7 P1-2）：查記憶體 → 未命中走 AE → 解碼縮圖 → 存記憶體。
//
// **測試邊界**：這裡用 mock 驗編排邏輯。真實 AE 佇列的公平性（慢請求是否真的釋放佇列）
// 靠 `SBApplication.timeout` 保證，屬 M8 真機驗證——mock 沒有真實的串行 AE 佇列，
// 在此斷言「monitor 不被阻塞」會是自欺。本檔只驗 client 端的 bounded wait 與編排契約。
@Suite("ArtworkService")
struct ArtworkServiceTests {
    /// 造一張可編碼為 PNG 的真圖（解碼路徑需要真實位元組）
    private func pngData(side: Int = 800) -> Data {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return Data() }
        return png
    }

    private func makeService(
        music: MockMusicClient,
        disk: ArtworkDiskCache? = nil,
        clock: any MonotonicClock = SystemMonotonicClock()
    ) -> ArtworkService {
        ArtworkService(music: music, memory: ArtworkMemoryCache(), disk: disk, clock: clock)
    }

    /// 臨時目錄的磁碟快取。真實 Caches 不得被測試碰到（Plan V4）
    private func withTempDisk<T>(_ body: (ArtworkDiskCache) async throws -> T) async rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("azw-artwork-service-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await body(ArtworkDiskCache(directory: dir))
    }

    @Test func fetchesDecodesAndCachesOnMiss() async {
        let music = MockMusicClient()
        await music.setArtwork(pngData(), for: "PID1")
        let service = makeService(music: music)

        let image = await service.artwork(for: "PID1")
        #expect(image != nil)
        #expect(await music.artworkCalls == 1)

        // 第二次應命中記憶體，不再打 AE
        _ = await service.artwork(for: "PID1")
        #expect(await music.artworkCalls == 1, "命中快取不得重複請求 AE")
    }

    /// 縮圖上限 512px（§4.8）——原圖 800px 應被縮小
    @Test func decodesToThumbnailNoLargerThan512() async {
        let music = MockMusicClient()
        await music.setArtwork(pngData(side: 800), for: "PID1")
        let service = makeService(music: music)

        let image = await service.artwork(for: "PID1")
        #expect(image != nil)
        #expect(max(image?.size.width ?? 0, image?.size.height ?? 0) <= 512)
    }

    /// 同一 ID 併發 miss 只發一次 AE（in-flight 去重）
    @Test func concurrentMissesShareOneAERequest() async {
        let gate = LyricsGate()
        let music = MockMusicClient()
        await music.setArtwork(pngData(), for: "PID1")
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        async let a = service.artwork(for: "PID1")
        async let b = service.artwork(for: "PID1")
        async let c = service.artwork(for: "PID1")
        await settle()
        await gate.open()

        let results = await [a, b, c]
        #expect(results.allSatisfy { $0 != nil })
        #expect(await music.artworkCalls == 1, "三個併發請求只該打一次 AE")
    }

    /// AE 拋錯 → 回 nil 不崩，且不寫快取
    ///
    /// P2 起失敗會進退避表（避免 `.task(id:)` 每次 render 重打 AE），
    /// 故「下次重試」的時點由退避決定——用可推進的時鐘驗，而非賭真實時間
    @Test func aeFailureReturnsNilWithoutCaching() async {
        let clock = ManualClock()
        let music = MockMusicClient()
        await music.setArtworkOutcome(.failure(.permissionDenied))
        let service = makeService(music: music, clock: clock)

        #expect(await service.artwork(for: "PID1") == nil)

        // 失敗不得寫快取——退避到期後仍須重取
        await music.setArtworkOutcome(.success(pngData()))
        clock.advance(by: ArtworkFailureBackoff.baseDelay)
        #expect(await service.artwork(for: "PID1") != nil)
        let calls = await music.artworkCalls
        #expect(calls == 2, "失敗不得寫快取，退避到期後應重新請求")
    }

    /// 無法解碼的位元組 → 回 nil 且不寫快取
    @Test func undecodableDataReturnsNilWithoutCaching() async {
        let clock = ManualClock()
        let music = MockMusicClient()
        await music.setArtwork(Data([0x00, 0x01, 0x02]), for: "PID1")
        let service = makeService(music: music, clock: clock)

        #expect(await service.artwork(for: "PID1") == nil)
        clock.advance(by: ArtworkFailureBackoff.baseDelay)
        #expect(await service.artwork(for: "PID1") == nil)
        let calls = await music.artworkCalls
        #expect(calls == 2, "解碼失敗不得寫快取")
    }

    /// 曲目無封面（AE 回 nil）→ 回 nil，不崩
    @Test func absentArtworkReturnsNil() async {
        let music = MockMusicClient()
        let service = makeService(music: music)
        #expect(await service.artwork(for: "PID1") == nil)
    }

    /// 單槽不變量的基礎版（P1 立、P2 由 `prefetchKeepsAEInFlightAtMostOne` 在有預取下重驗）
    @Test func noPrefetchKeepsInFlightAtMostOne() async {
        let gate = LyricsGate()
        let music = MockMusicClient()
        await music.setArtwork(pngData(), for: "PID1")
        await music.setArtwork(pngData(), for: "PID2")
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        async let a = service.artwork(for: "PID1")
        await settle()
        #expect(await music.artworkInFlight <= 1)

        await gate.open()
        _ = await a
    }


    // MARK: - P2-1b 磁碟層

    /// DoD ①：磁碟命中要回填記憶體，且**不打 AE**
    @Test func diskHitPopulatesMemoryWithoutAE() async {
        await withTempDisk { disk in
            let music = MockMusicClient()
            await music.setArtwork(pngData(), for: "PID1")

            let first = makeService(music: music, disk: disk)
            #expect(await first.artwork(for: "PID1") != nil)
            #expect(await music.artworkCalls == 1)

            // 新 service＝冷啟動（記憶體空），磁碟仍在
            let second = makeService(music: music, disk: disk)
            #expect(await second.artwork(for: "PID1") != nil, "冷啟動須由磁碟命中")
            #expect(await music.artworkCalls == 1, "磁碟命中不得打 AE")
        }
    }

    /// DoD ⑤：磁碟上的位元組解不開＝損毀 → 刪除並重取
    @Test func undecodableDiskEntryIsRemovedAndRefetched() async {
        await withTempDisk { disk in
            await disk.store(Data([0x00, 0x01, 0x02]), for: "PID1")

            let music = MockMusicClient()
            await music.setArtwork(pngData(), for: "PID1")
            let service = makeService(music: music, disk: disk)

            #expect(await service.artwork(for: "PID1") != nil, "損毀後須落到 AE 重取")
            #expect(await music.artworkCalls == 1)
            #expect(await disk.data(for: "PID1") != nil, "重取成功後須回寫磁碟")
        }
    }

    /// DoD ⑦：同 ID 併發只寫一次磁碟
    @Test func concurrentMissesWriteDiskOnce() async {
        await withTempDisk { disk in
            let gate = LyricsGate()
            let music = MockMusicClient()
            await music.setArtwork(pngData(), for: "PID1")
            await music.setArtworkGate(gate)
            let service = makeService(music: music, disk: disk)

            async let a = service.artwork(for: "PID1")
            async let b = service.artwork(for: "PID1")
            await settle()
            await gate.open()
            _ = await [a, b]

            #expect(await music.artworkCalls == 1)
            #expect(await disk.entryCount == 1)
        }
    }

    /// 空 ID 不得觸碰 AE 或磁碟——它會固定 hash 成同一個檔案
    @Test func emptyIDReturnsNilWithoutAEOrDisk() async {
        await withTempDisk { disk in
            let music = MockMusicClient()
            let service = makeService(music: music, disk: disk)

            #expect(await service.artwork(for: "") == nil)
            await service.prefetch(["", ""])
            await settle()

            let calls = await music.artworkCalls
            let entries = await disk.entryCount
            #expect(calls == 0)
            #expect(entries == 0)
        }
    }

    // MARK: - P2-2b 預取排程

    private func makeMusic(ids: [String]) async -> MockMusicClient {
        let music = MockMusicClient()
        for id in ids { await music.setArtwork(pngData(side: 40), for: id) }
        return music
    }

    /// DoD ⑥ 的單元層不變量：預取多張時，任一時刻送進 AE 的 artwork ≤ 1
    @Test func prefetchKeepsAEInFlightAtMostOne() async {
        let ids = (0..<10).map { "PID\($0)" }
        let music = await makeMusic(ids: ids)
        await music.setArtworkGateQueue((0..<10).map { _ in LyricsGate.opened() })
        let service = makeService(music: music)

        await service.prefetch(ids)
        await waitFor { await music.artworkCalls == 10 }

        let peak = await music.maxArtworkInFlight
        let calls = await music.artworkCalls
        #expect(peak <= 1, "單槽：AE 上同時最多一張 artwork")
        #expect(calls == 10, "預取最終仍須全部取到")
    }

    /// DoD ①：替換預取集合時，尚未開始的舊項不得再打 AE
    @Test func prefetchReplacementDropsUnstartedEntries() async {
        let gate = LyricsGate()
        let music = await makeMusic(ids: (0..<6).map { "PID\($0)" })
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        await service.prefetch(["PID0", "PID1", "PID2"])
        await waitFor { await music.artworkOrder == ["PID0"] }   // PID0 卡在 AE，其餘仍在佇列
        await service.prefetch(["PID5"])                         // 換一批
        await gate.open()
        await waitFor { await music.artworkOrder.contains("PID5") }

        let order = await music.artworkOrder
        #expect(order.contains("PID0"), "已送出的不取消")
        #expect(order.contains("PID5"))
        #expect(!order.contains("PID1") && !order.contains("PID2"), "未開始的舊項須被丟棄")
    }

    /// 空集合＝全部取消（切專輯／切 tab 走這條）
    @Test func emptyPrefetchCancelsEverythingPending() async {
        let gate = LyricsGate()
        let music = await makeMusic(ids: (0..<4).map { "PID\($0)" })
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        await service.prefetch(["PID0", "PID1", "PID2", "PID3"])
        await waitFor { await music.artworkInFlight == 1 }
        await service.prefetch([])
        await gate.open()
        await settle(300)   // 「不應再有呼叫」沒有正向條件可等，只能讓一會兒再看

        let calls = await music.artworkCalls
        #expect(calls == 1, "只有已送出的那一張會完成")
    }

    /// DoD ③：記憶體／磁碟已有的不排 AE
    @Test func prefetchSkipsMemoryAndDiskHits() async {
        await withTempDisk { disk in
            let music = await makeMusic(ids: ["PID1", "PID2"])
            let service = makeService(music: music, disk: disk)

            _ = await service.artwork(for: "PID1")          // 進記憶體＋磁碟
            let afterFirst = await music.artworkCalls

            await service.prefetch(["PID1"])
            await settle(200)   // 「不應排 AE」無正向條件可等
            let afterMemoryHit = await music.artworkCalls
            #expect(afterMemoryHit == afterFirst, "記憶體命中不得排 AE")

            let cold = makeService(music: music, disk: disk)  // 記憶體空、磁碟有
            await cold.prefetch(["PID1"])
            await settle(200)
            let afterDiskHit = await music.artworkCalls
            #expect(afterDiskHit == afterFirst, "磁碟命中不得排 AE")
        }
    }

    /// DoD ④：explicit 請求碰上進行中的預取 → 共享同一次 AE
    @Test func explicitRequestJoinsPendingPrefetch() async {
        let gate = LyricsGate()
        let music = await makeMusic(ids: ["PID1"])
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        await service.prefetch(["PID1"])
        await waitFor { await music.artworkInFlight == 1 }
        async let explicit = service.artwork(for: "PID1")
        await settle()
        await gate.open()

        #expect(await explicit != nil, "explicit 須拿到同一次取圖的結果")
        let calls = await music.artworkCalls
        #expect(calls == 1, "不得重複打 AE")
    }

    /// 中心優先：後到的 explicit 要排在尚未開始的預取之前
    @Test func explicitRequestIsServedBeforePendingPrefetch() async {
        let gate = LyricsGate()
        let music = await makeMusic(ids: ["BLOCK", "P1", "P2", "CENTER"])
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        await service.prefetch(["BLOCK", "P1", "P2"])
        await waitFor { await music.artworkOrder == ["BLOCK"] }   // BLOCK 佔住 AE
        async let center = service.artwork(for: "CENTER")
        await settle()                                            // 讓 explicit 進入佇列
        await gate.open()
        _ = await center
        await waitFor { await music.artworkOrder.count == 4 }

        let order = await music.artworkOrder
        let centerIndex = order.firstIndex(of: "CENTER") ?? .max
        let p1Index = order.firstIndex(of: "P1") ?? .max
        #expect(centerIndex < p1Index, "explicit 須插隊到未開始的預取之前")
    }

    /// DoD ⑤：失敗後在退避期內不得重打；到期後由下一次請求觸發重試
    @Test func failedIDIsNotRefetchedUntilBackoffElapses() async {
        let clock = ManualClock()
        let music = MockMusicClient()
        await music.setArtworkOutcome(.failure(.permissionDenied))
        let service = makeService(music: music, clock: clock)

        #expect(await service.artwork(for: "PID1") == nil)
        #expect(await music.artworkCalls == 1)

        #expect(await service.artwork(for: "PID1") == nil)
        #expect(await music.artworkCalls == 1, "退避期內不得重打 AE")

        clock.advance(by: ArtworkFailureBackoff.baseDelay)
        await music.setArtworkOutcome(.success(pngData()))
        #expect(await service.artwork(for: "PID1") != nil, "到期後須重試")
        #expect(await music.artworkCalls == 2)
    }

    /// 退避中的 ID 不得被預取排進 AE
    @Test func backedOffIDIsSkippedByPrefetch() async {
        let clock = ManualClock()
        let music = MockMusicClient()
        await music.setArtworkOutcome(.failure(.permissionDenied))
        let service = makeService(music: music, clock: clock)

        _ = await service.artwork(for: "PID1")
        await service.prefetch(["PID1"])
        await settle(200)   // 「不應重打」無正向條件可等
        let duringBackoff = await music.artworkCalls
        #expect(duringBackoff == 1)

        clock.advance(by: ArtworkFailureBackoff.baseDelay)
        await service.prefetch(["PID1"])
        await waitFor { await music.artworkCalls == 2 }
        let afterBackoff = await music.artworkCalls
        #expect(afterBackoff == 2, "到期後預取須重新排入")
    }

    // MARK: - 取消與狀態機

    /// explicit 的呼叫端被取消 → waiter 移除、entry 降級，不得卡住後續預取
    @Test func cancelledExplicitWaiterIsRemovedAndEntryDemoted() async {
        let gate = LyricsGate()
        let music = await makeMusic(ids: ["BLOCK", "DROPPED", "KEPT"])
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        await service.prefetch(["BLOCK"])
        await waitFor { await music.artworkOrder == ["BLOCK"] }   // BLOCK 佔住 AE

        let task = Task { await service.artwork(for: "DROPPED") }
        await settle()
        task.cancel()
        #expect(await task.value == nil, "取消的等待者須立即收到 nil")

        // 降級後，替換預取集合應能把它淘汰掉
        await service.prefetch(["KEPT"])
        await gate.open()
        await waitFor { await music.artworkOrder.contains("KEPT") }

        let order = await music.artworkOrder
        #expect(order.contains("KEPT"))
        #expect(!order.contains("DROPPED"), "無人等待的 explicit 須降級並可被替換淘汰")
    }

    /// 呼叫端在 continuation 註冊**之前**就取消：不得留下永不 resume 的等待者。
    /// 這條在 SwiftUI 上的表現是 `.task` 永久掛起、封面永遠停在佔位
    @Test func alreadyCancelledRequestReturnsWithoutHanging() async {
        let gate = LyricsGate()
        let music = await makeMusic(ids: ["BLOCK", "TARGET"])
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        await service.prefetch(["BLOCK"])
        await waitFor { await music.artworkOrder == ["BLOCK"] }

        let task = Task {
            // 進 artwork(for:) 之前就取消，讓註冊與取消互相競爭
            await service.artwork(for: "TARGET")
        }
        task.cancel()
        #expect(await task.value == nil, "已取消的請求必須返回，不得永久掛起")

        await gate.open()
        await waitFor { await music.artworkInFlight == 0 }
        await settle(200)

        // 光讓呼叫端返回還不夠：沒人再等的請求不得繼續佔用共用的 AE 佇列
        let order = await music.artworkOrder
        #expect(!order.contains("TARGET"), "已取消的請求不得仍被送去打 AE")
    }

    /// 取消一個**由既有預取升級而來**的 explicit 請求，不得把別人排的預取一起刪掉
    @Test func cancellingUpgradedRequestKeepsUnderlyingPrefetch() async {
        let gate = LyricsGate()
        let music = await makeMusic(ids: ["BLOCK", "SHARED"])
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        await service.prefetch(["BLOCK", "SHARED"])
        await waitFor { await music.artworkOrder == ["BLOCK"] }

        let task = Task { await service.artwork(for: "SHARED") }
        task.cancel()
        _ = await task.value

        await gate.open()
        await waitFor { await music.artworkOrder.contains("SHARED") }

        let order = await music.artworkOrder
        #expect(order.contains("SHARED"), "升級而來的請求被取消後，底下的預取仍須完成")
    }

    /// 取圖失敗不得讓佇列停滯——後續項仍須被處理
    @Test func failedFetchDoesNotStallQueue() async {
        let music = MockMusicClient()
        await music.setArtworkOutcome(.failure(.permissionDenied))
        let service = makeService(music: music)

        await service.prefetch(["A", "B", "C"])
        await waitFor { await music.artworkCalls == 3 }

        let calls = await music.artworkCalls
        #expect(calls == 3, "第一張失敗後其餘仍須執行")
    }

    /// 佇列排空後再進新工作，drain 必須能重新啟動
    @Test func drainRestartsAfterQueueDrains() async {
        let music = await makeMusic(ids: ["A", "B"])
        let service = makeService(music: music)

        await service.prefetch(["A"])
        await waitFor { await music.artworkCalls == 1 }

        await service.prefetch(["B"])
        await waitFor { await music.artworkCalls == 2 }
        let calls = await music.artworkCalls
        #expect(calls == 2, "排空後的新工作仍須被處理")
    }

    /// 替換預取集合不得把**正在 AE** 的那一張抽掉——它的結果照樣要寫快取
    @Test func prefetchReplacementKeepsActiveEntry() async {
        let gate = LyricsGate()
        let music = await makeMusic(ids: ["ACTIVE", "OTHER"])
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        await service.prefetch(["ACTIVE"])
        await waitFor { await music.artworkOrder == ["ACTIVE"] }
        await service.prefetch(["OTHER"])
        await gate.open()
        await waitFor { await music.artworkOrder.contains("OTHER") }

        #expect(await service.artwork(for: "ACTIVE") != nil, "進行中的取圖結果仍須落進快取")
        let order = await music.artworkOrder
        #expect(order.filter { $0 == "ACTIVE" }.count == 1, "不得重取")
    }

    /// **首次就成功不發通知**：呼叫端本來就會從回傳值拿到圖，不需要被叫醒重讀。
    /// 無條件通知會讓每張封面完成都驚動 View 層
    @Test func onStoredDoesNotFireOnFirstTimeSuccess() async {
        let recorder = StoredRecorder()
        let music = await makeMusic(ids: ["A", "B"])
        let service = makeService(music: music)
        await service.setOnStored { id in Task { await recorder.record(id) } }

        await service.prefetch(["A", "B"])
        await waitFor { await music.artworkCalls == 2 }
        await settle(200)

        let stored = await recorder.ids
        #expect(stored.isEmpty, "首次成功不得發恢復通知")
    }

    /// 從失敗中恢復才通知——這正是「已顯示佔位的項目該被叫醒」的唯一情形。
    /// 判定放在 service（它的退避表本就記著誰失敗過），呼叫端不必自建鏡像狀態
    @Test func onStoredFiresWhenRecoveringFromFailure() async {
        let recorder = StoredRecorder()
        let clock = ManualClock()
        let music = MockMusicClient()
        await music.setArtworkOutcome(.failure(.permissionDenied))
        let service = makeService(music: music, clock: clock)
        await service.setOnStored { id in Task { await recorder.record(id) } }

        #expect(await service.artwork(for: "PID1") == nil)
        await settle(100)
        #expect(await recorder.ids.isEmpty, "失敗當下不發通知")

        clock.advance(by: ArtworkFailureBackoff.baseDelay)
        await music.setArtworkOutcome(.success(pngData()))
        #expect(await service.artwork(for: "PID1") != nil)
        await waitFor { await recorder.ids == ["PID1"] }

        let stored = await recorder.ids
        #expect(stored == ["PID1"], "恢復成功須通知一次")
    }

    /// 失敗不得發通知——沒有新圖可看
    @Test func onStoredDoesNotFireOnFailure() async {
        let recorder = StoredRecorder()
        let music = MockMusicClient()
        await music.setArtworkOutcome(.failure(.permissionDenied))
        let service = makeService(music: music)
        await service.setOnStored { id in Task { await recorder.record(id) } }

        _ = await service.artwork(for: "PID1")
        await settle(200)

        #expect(await recorder.ids.isEmpty)
    }
}

/// 手動推進的時鐘：退避的到期判定必須可測，不能靠真實等待。
///
/// `MonotonicClock.now` 是同步屬性，故用鎖而非 actor——actor 的狀態讀不到同步 getter 裡
final class ManualClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval = 1000

    var now: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current += interval
    }
}

/// 收集 onStored 通知
actor StoredRecorder {
    private(set) var ids: [String] = []
    func record(_ id: String) { ids.append(id) }
}

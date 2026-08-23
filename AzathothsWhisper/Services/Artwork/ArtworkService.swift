import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 封面來源抽象——ViewModel 只依賴它，測試可注入替身
protocol ArtworkProviding: Sendable {
    func artwork(for persistentID: String) async -> NSImage?
    /// 以 `persistentIDs` **取代**目前的預取集合：未開始的舊項取消、新項按序排入；
    /// 空陣列＝全部取消。已送進 AE 的那一張不受影響（取消已送出的 Apple Event 沒有意義）
    func prefetch(_ persistentIDs: [String]) async
    /// 註冊「**從失敗中恢復**」的通知：某個先前取圖失敗（呼叫端已顯示佔位）的 ID
    /// 在退避到期後重取成功。呼叫端負責跳回自己的 actor。
    ///
    /// **單一訂閱者**：後註冊者覆蓋前一個，不是多播。目前唯一呼叫點是組裝根；
    /// 若日後出現第二個消費者，必須先改成多播，否則會靜默地只剩最後一個收得到。
    ///
    /// **放在協議而非具體型別上**：ViewModel 只依賴本協議，接線若收窄成 `ArtworkService`，
    /// 測試替身就無法傳入——那條 actor→MainActor 的橋接便再也沒有任何測試能跑到
    func setOnStored(_ handler: (@Sendable (String) -> Void)?) async
}

/// 取圖編排（M7 P1-2／P2）：記憶體 → 磁碟 → AE，單槽送出、explicit 優先、可取消。
///
/// **best-effort 語義**：任何一步失敗都回 `nil`，由呼叫端顯示佔位（H-08）。
/// 失敗**不寫快取**——否則一次網路/權限抖動會把「沒有封面」永久固化。
///
/// ## 為何單槽（P2 的 AE 公平性解法）
/// AE 呼叫是串行佇列上的**同步**呼叫，執行中的那一張不可搶佔（Swift cancellation 不中斷
/// 已開始的 dispatch block）。因此任何 executor 級優先級方案，monitor 的最佳界都是
/// 「等完當前那一張 artwork」。本服務任一時刻只向 AE 送**一張**，達成完全相同的界，
/// 卻不必改動 Editor／Batch／monitor 三方共用的 `MusicAppleEventsClient`。
/// backlog 留在本服務內，因此可取消、可依「中心優先」重排。
///
/// 前提（任一失效即需重評）：①artwork 只由本服務發出 ②單槽 ③AE 不可搶佔 ④executor FIFO。
actor ArtworkService: ArtworkProviding {
    /// §4.8：縮圖上限
    static let maxPixelSize = 512
    /// 磁碟存的是重新編碼的 JPEG——原圖動輒數 MB，50MB 配額只裝得下十幾張
    static let diskCompressionQuality = 0.85

    /// 待處理項。**class**：waiters 需要跨 `await` 被增刪，值型別會複製出兩份狀態
    private final class Entry {
        let id: String
        var isExplicit: Bool
        var waiters: [UUID: CheckedContinuation<NSImage?, Never>] = [:]

        init(id: String, isExplicit: Bool) {
            self.id = id
            self.isExplicit = isExplicit
        }

        /// 取走 waiters 並清空——確保「移除者才 resume」，杜絕 double-resume
        func takeWaiters() -> [UUID: CheckedContinuation<NSImage?, Never>] {
            defer { waiters.removeAll() }
            return waiters
        }
    }

    private let music: any MusicControlling
    private let memory: ArtworkMemoryCache
    private let disk: ArtworkDiskCache?
    private let clock: any MonotonicClock

    private var pending: [Entry] = []
    /// 正在 AE 的那一筆（≤1）。**持有自己的 waiters**——只存 id 就無法把結果送回等待者
    private var active: Entry?
    private var drainTask: Task<Void, Never>?
    private var backoff = ArtworkFailureBackoff()

    /// 「從失敗中恢復」的通知（供呼叫端叫醒已顯示佔位的項目）。呼叫端負責跳回自己的 actor
    private var onStored: (@Sendable (String) -> Void)?

    init(
        music: any MusicControlling,
        memory: ArtworkMemoryCache = ArtworkMemoryCache(),
        disk: ArtworkDiskCache? = nil,
        clock: any MonotonicClock = SystemMonotonicClock()
    ) {
        self.music = music
        self.memory = memory
        self.disk = disk
        self.clock = clock
    }

    func setOnStored(_ handler: (@Sendable (String) -> Void)?) {
        onStored = handler
    }

    /// 快取查詢的三種結果。`artwork(for:)` 與排程器都要先問這一輪，抽出來避免兩份逐字相同的判斷
    private enum Resolution {
        case hit(NSImage)
        case backedOff
        case miss
    }

    /// 記憶體 → 磁碟 → 退避表。磁碟命中會回填記憶體
    private func resolveCached(_ persistentID: String) async -> Resolution {
        if let cached = memory.image(for: persistentID) { return .hit(cached) }
        if let image = await loadFromDisk(persistentID) { return .hit(image) }
        return backoff.isDue(persistentID, now: clock.now) ? .miss : .backedOff
    }

    // MARK: - ArtworkProviding

    func artwork(for persistentID: String) async -> NSImage? {
        // 空 ID 會固定 hash 成同一個磁碟檔，不同「未知曲目」互相覆寫；AE 端也拒絕空 ID
        guard !persistentID.isEmpty else { return nil }
        switch await resolveCached(persistentID) {
        case .hit(let image): return image
        case .backedOff: return nil
        case .miss: break
        }

        // 進來就已取消：連排都不要排（下面那道檢查擋的是「排完才取消」的競態）
        guard !Task.isCancelled else { return nil }

        let (entry, wasNewlyCreated) = explicitEntry(for: persistentID)
        let token = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // **註冊時再檢查一次**：若 Task 在建立 entry 與此處之間被取消，
                // onCancel 早已跑過並找不到 token（no-op），continuation 隨後才入表 →
                // 永不 resume → SwiftUI 的 `.task` 永久掛起。
                //
                // 光是 resume(nil) 還不夠：entry 已經以 explicit 身分排在佇列上，
                // 沒有任何等待者卻仍會被 drain 取走、對已離開畫面的封面打一次 AE，
                // 佔住三方共用的串行佇列。**取消必須連工作一起撤掉**
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    withdraw(entry, wasNewlyCreated: wasNewlyCreated)
                    return
                }
                entry.waiters[token] = continuation
            }
        } onCancel: {
            Task { await self.cancelWaiter(entryID: persistentID, token: token) }
        }
    }

    func prefetch(_ persistentIDs: [String]) async {
        let wanted = persistentIDs.filter { !$0.isEmpty }
        let keep = Set(wanted)

        // 未開始的預取項：不在新集合裡就丟掉。explicit 不動——有人正等著它
        pending.removeAll { !$0.isExplicit && !keep.contains($0.id) }

        for id in wanted {
            guard memory.image(for: id) == nil,
                  backoff.isDue(id, now: clock.now),
                  active?.id != id,
                  !pending.contains(where: { $0.id == id })
            else { continue }
            pending.append(Entry(id: id, isExplicit: false))
        }
        ensureDraining()
    }

    // MARK: - 排程

    /// - Returns: entry 與「它是否為本次新建」——撤回時要據此決定移除或只降級
    private func explicitEntry(for id: String) -> (entry: Entry, wasNewlyCreated: Bool) {
        if let active, active.id == id { return (active, false) }
        if let existing = pending.first(where: { $0.id == id }) {
            existing.isExplicit = true      // 預取升級為 explicit：有人正在等它
            return (existing, false)
        }
        let entry = Entry(id: id, isExplicit: true)
        pending.append(entry)
        ensureDraining()
        return (entry, true)
    }

    /// 撤回一個沒人再等的 explicit 請求。
    ///
    /// 本次新建的直接移除；由既有預取項升級而來的只降回預取——
    /// 那是別人排的工作，不該因為某個 View 取消就被連坐刪掉
    private func withdraw(_ entry: Entry, wasNewlyCreated: Bool) {
        guard entry !== active, entry.waiters.isEmpty else { return }
        if wasNewlyCreated {
            pending.removeAll { $0 === entry }
        } else {
            entry.isExplicit = false
        }
    }

    /// 取消：**只有在 token 仍在場時才移除並 resume**。
    /// completion 已 `takeWaiters()` 的情況下找不到 token，此處即為 no-op——
    /// continuation 因此只有一條 resume 路徑
    private func cancelWaiter(entryID: String, token: UUID) {
        let entry = active?.id == entryID
            ? active
            : pending.first(where: { $0.id == entryID })
        guard let entry, let continuation = entry.waiters.removeValue(forKey: token) else { return }
        continuation.resume(returning: nil)

        // 沒人等的 explicit 降級回預取，好讓下一次 prefetch 的替換能把它淘汰掉；
        // active 不降級（AE 已送出，結果照樣寫快取）。
        // 此處一律降級不移除：走到這裡代表 entry 曾有等待者，可能同時也在預取視窗內
        withdraw(entry, wasNewlyCreated: false)
    }

    private func ensureDraining() {
        guard drainTask == nil, !pending.isEmpty else { return }
        // **強引用**：drain 在佇列排空後自行結束，不會長期持有 service。
        // 用 `[weak self]` 會讓 ARC 在呼叫端不再引用 service 時中途釋放它，
        // drain 於下一次 `self?` 解包時靜默中止、剩餘項目永不處理
        drainTask = Task { await self.drain() }
    }

    private func drain() async {
        while let entry = popNext() {
            active = entry
            let image = await fetch(entry.id)
            // 先取走 waiters、再清 active、最後 resume——三者同一同步段，無重入窗口
            let waiters = entry.takeWaiters()
            active = nil
            for continuation in waiters.values { continuation.resume(returning: image) }
        }
        // 與最後一次 popNext 同一同步段：此後的 enqueue 都會看到 nil 並重啟 drain，不會遺失
        drainTask = nil
    }

    /// explicit 優先；同類之間依入列序（各自 FIFO）。
    ///
    /// 入列序**就是陣列序**——`pending` 只 append 與 removeAll，從不插隊重排，
    /// 故不需要額外的序號欄位（那會是第二份得手動與陣列保持同步的狀態）
    private func popNext() -> Entry? {
        if let index = pending.firstIndex(where: \.isExplicit) {
            return pending.remove(at: index)
        }
        return pending.isEmpty ? nil : pending.removeFirst()
    }

    // MARK: - 取圖

    /// 單一 completion path：AE 拋錯、回 nil、解碼失敗，一律回 nil 並記退避
    private func fetch(_ persistentID: String) async -> NSImage? {
        // 排進來之後才被別的路徑填上的情況（例如同批預取先取到）——不重複打 AE
        switch await resolveCached(persistentID) {
        case .hit(let image): return image
        case .backedOff: return nil
        case .miss: break
        }

        guard let data = try? await music.artworkData(persistentID: persistentID),
              let image = Self.thumbnail(from: data)
        else {
            backoff.record(persistentID, now: clock.now)
            return nil
        }

        // 清除失敗紀錄並同時得知「這次是否為恢復」——退避表本就記著誰失敗過，
        // 呼叫端不需要另建一份「誰在顯示佔位」的鏡像狀態
        let wasRecovery = backoff.recordSuccess(persistentID)
        memory.store(image, for: persistentID)
        await storeToDisk(image, for: persistentID)
        // 只有恢復才通知：首次就成功的項目，呼叫端本來就會從回傳值拿到圖
        if wasRecovery { onStored?(persistentID) }
        return image
    }

    /// 磁碟命中要回填記憶體；解碼失敗＝檔案損毀，刪掉並當 miss（下次重取）
    private func loadFromDisk(_ persistentID: String) async -> NSImage? {
        guard let disk, let data = await disk.data(for: persistentID) else { return nil }
        guard let image = Self.thumbnail(from: data) else {
            await disk.remove(for: persistentID)
            return nil
        }
        memory.store(image, for: persistentID)
        return image
    }

    private func storeToDisk(_ image: NSImage, for persistentID: String) async {
        guard let disk, let encoded = Self.encodeForDisk(image) else { return }
        await disk.store(encoded, for: persistentID)
    }

    // MARK: - 影像

    /// 解碼為 ≤512px 的縮圖。原圖可能是專輯級的大圖，直接進記憶體會炸。
    nonisolated static func thumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// 磁碟存 JPEG 而非 AE 原始位元組：原圖 1–5MB，50MB 配額只裝得下十幾張，
    /// 「冷啟動即顯」就形同虛設；512px JPEG 約 30–80KB
    nonisolated static func encodeForDisk(_ image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: diskCompressionQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

import Foundation
import OSLog

private let syncLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "cloud-sync")

/// iCloud 同步的排程（⑨ 計劃 §6.4–§6.5、T5）：dirty 依類別的安靜期與最長延遲匯出、啟動時比雜湊補匯出、
/// 每 10 分鐘匯入一次（MB 先）。只寫自己的資料夾、只寫本機正本；日誌只記類別、筆數、錯誤類型
actor CloudSyncCoordinator {
    struct Status: Equatable, Sendable {
        var lastExport: Date?
        var lastImport: Date?
        /// 其他 Mac 與各自最後一次寫檔時間
        var otherWriters: [String: Date] = [:]
        var skipped = 0
        var pendingDownloads = 0
        /// 最近一次錯誤的類型（不含路徑與內容）
        var lastError: String?
    }

    struct Cadence: Equatable, Sendable {
        /// 最後一次變更後安靜這麼久就匯出
        let quiet: TimeInterval
        /// 第一次變更後最晚這麼久一定匯出（連續寫入不會無限延後，R1-15）
        let maxDelay: TimeInterval
    }

    static func cadence(_ kind: SyncKind) -> Cadence {
        switch kind {
        case .decisions, .nolyrics: Cadence(quiet: 10, maxDelay: 10)
        case .artists: Cadence(quiet: 60, maxDelay: 600)
        case .timings: Cadence(quiet: 300, maxDelay: 1_800)
        }
    }

    static let importInterval: TimeInterval = 600
    static let tickInterval: Duration = .seconds(5)
    static let readTimeout: Duration = .seconds(30)

    private let folder: SyncFolder
    private let channels: [CloudSyncChannel]
    private let clock: any MonotonicClock & PollClock
    private let readDeadline: any PollClock
    private let wallClock: @Sendable () -> Date
    private let lock: SyncLock?
    private let publish: @Sendable (Status) async -> Void

    private var dirty: [SyncKind: (first: TimeInterval, last: TimeInterval)] = [:]
    /// 各類、各他機上次採用成功時的檔案大小與時間（沒變就不重讀）
    private var knownStamps: [SyncKind: [String: SyncFolder.FileStamp]] = [:]
    /// 讀取還沒結束的類別（逾時後阻塞讀取仍佔著執行緒；上一輪沒結束就不再開新的，安全評審 LOW-9）
    private var readsInFlight: Set<SyncKind> = []
    /// 各他機最後一次讀到的 writtenAt（沒變而略過時沿用）
    private var writerTimes: [String: Date] = [:]
    private var lastImportAt: TimeInterval?
    private var status = Status()
    private var published: Status?
    private(set) var exportCount = 0

    init(
        folder: SyncFolder, channels: [CloudSyncChannel], clock: any MonotonicClock & PollClock, readDeadline: any PollClock,
        wallClock: @escaping @Sendable () -> Date, lock: SyncLock?, publish: @escaping @Sendable (Status) async -> Void
    ) {
        self.folder = folder
        // MB 先匯入：讓背景查詢跳過他機已查的歌手（§6.5）
        self.channels = channels.sorted { ($0.kind == .artists ? 0 : 1) < ($1.kind == .artists ? 0 : 1) }
        self.clock = clock
        self.readDeadline = readDeadline
        self.wallClock = wallClock
        self.lock = lock
        self.publish = publish
    }

    /// 開啟同步、或同步為開時的啟動：補 origin → 匯入 → 匯出（與自己那份相同的不寫）
    func start() async {
        for channel in channels {
            do {
                try await channel.stamp(folder.writerID)
            } catch {
                fail("stampFailed", kind: channel.kind)
            }
        }
        await importAll()
        for channel in channels {
            await export(channel)
        }
        await publishIfChanged()
    }

    func run() async {
        guard !Task.isCancelled else { return }
        await start()
        while !Task.isCancelled {
            do {
                try await clock.sleep(for: Self.tickInterval)
            } catch {
                return
            }
            await tick()
        }
    }

    func markDirty(_ kind: SyncKind) {
        let now = clock.now
        dirty[kind] = (dirty[kind]?.first ?? now, now)
    }

    func tick() async {
        let now = clock.now
        for channel in channels {
            guard let pending = dirty[channel.kind] else { continue }
            let cadence = Self.cadence(channel.kind)
            if now - pending.last >= cadence.quiet || now - pending.first >= cadence.maxDelay {
                await export(channel)
            }
        }
        if lastImportAt.map({ now - $0 >= Self.importInterval }) ?? true {
            await importAll()
        }
        await publishIfChanged()
    }

    /// 結束 app 時：只匯出 dirty 的類別（呼叫端限時，§6.4）。`skipping` 的類別留給下次啟動的雜湊比對補上
    func flushDirty(skipping skipped: Set<SyncKind> = []) async {
        for channel in channels where dirty[channel.kind] != nil && !skipped.contains(channel.kind) {
            await export(channel)
        }
        await publishIfChanged()
    }

    // MARK: 內部

    private func export(_ channel: CloudSyncChannel) async {
        let held = lock?.tryAcquire()
        if lock != nil, held == nil {
            fail("locked", kind: channel.kind)
            return
        }
        defer { held?.release() }
        do {
            try await channel.stamp(folder.writerID)
            if try await channel.export(folder, wallClock()) {
                status.lastExport = wallClock()
                exportCount += 1
            }
            dirty[channel.kind] = nil
        } catch let failure as SyncFolder.Failure {
            fail(String(describing: failure), kind: channel.kind)
        } catch {
            fail("exportFailed", kind: channel.kind)
        }
    }

    private func importAll() async {
        lastImportAt = clock.now
        var writers: [String: Date] = [:]
        var seen: Set<String> = []
        var skipped = 0
        var pending = 0
        for channel in channels {
            guard !readsInFlight.contains(channel.kind) else {
                fail("readBusy", kind: channel.kind)
                continue
            }
            guard let read = await readWithDeadline(channel) else {
                fail("readTimeout", kind: channel.kind)
                continue
            }
            writers.merge(read.writers, uniquingKeysWith: max)
            seen.formUnion(read.stamps.keys)
            skipped += read.skipped
            pending += read.pendingDownloads
            let adoption = await read.apply()
            // 寫入失敗的不記成已採用：下輪重讀重試（codex review P2）
            if !adoption.failed {
                knownStamps[channel.kind, default: [:]].merge(read.stamps) { _, new in new }
            } else {
                fail("adoptFailed", kind: channel.kind)
            }
            if adoption.rejected > 0 {
                syncLog.error("sync records rejected kind=\(channel.kind.rawValue, privacy: .public) count=\(adoption.rejected, privacy: .public)")
            }
            if adoption.changed { markDirty(channel.kind) }
        }
        // 沒變而略過的他機沿用上次讀到的時間；這輪完全看不到的（資料夾被刪）就不列
        writerTimes.merge(writers, uniquingKeysWith: max)
        status.otherWriters = writerTimes.filter { seen.contains($0.key) }
        status.skipped = skipped
        status.pendingDownloads = pending
        status.lastImport = wallClock()
    }

    /// 讀取放到 actor 外、限時；逾時就丟掉這次的結果（晚到也不採用）。讀取真正結束時才清掉「進行中」
    private func readWithDeadline(_ channel: CloudSyncChannel) async -> CloudSyncRead? {
        let folder = folder
        let known = knownStamps[channel.kind] ?? [:]
        let kind = channel.kind
        readsInFlight.insert(kind)
        return await SyncDeadline.run(Self.readTimeout, clock: readDeadline) { [weak self] in
            let read = await channel.read(folder, known)
            await self?.readFinished(kind)
            return read
        }
    }

    private func readFinished(_ kind: SyncKind) {
        readsInFlight.remove(kind)
    }

    private func fail(_ kind: String, kind syncKind: SyncKind) {
        status.lastError = kind
        syncLog.error("cloud sync \(kind, privacy: .public) kind=\(syncKind.rawValue, privacy: .public)")
    }

    private func publishIfChanged() async {
        guard status != published else { return }
        published = status
        await publish(status)
    }
}

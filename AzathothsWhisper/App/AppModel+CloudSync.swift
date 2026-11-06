import Foundation
import OSLog

// ⑨ iCloud 跨 Mac 同步的接線（計劃 docs/plans/2026-11-03-lyrics-icloud-sync.md §6.5「單一採用入口」、§6.6、§6.7）。
// 四類資料各一個 channel；所有匯入都經這裡更新存檔與記憶體快照，不需重啟即下次播放（時間軸：下次查找）生效
private let cloudSyncLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "cloud-sync")

extension AppModel {
    /// 結束 app 時最多等這麼久（不擋退出，§6.4）
    static let cloudSyncQuitBudget: Duration = .seconds(2)

    /// 設定頁要顯示的狀態
    var cloudSyncDisplay: CloudSyncDisplay {
        CloudSyncDisplay(enabled: cloudSyncEnabled, unavailable: cloudSyncUnavailable, status: cloudSyncStatus)
    }

    func startCloudSyncIfEnabled() {
        guard cloudSyncEnabled else { return }
        startCloudSync()
    }

    /// 設定頁開關：每台各自，預設關
    func setCloudSyncEnabled(_ enabled: Bool) {
        guard cloudSyncEnvironment != nil, enabled != cloudSyncEnabled else { return }
        // 讀不到硬體身分：開不起來，開關也不存成「開」
        guard !enabled || makeSyncFolder() != nil else {
            settings.updateCloudSync(cloudSyncDisplay)
            return
        }
        configStore.setCloudSyncEnabled(enabled)
        cloudSyncEnabled = enabled
        if enabled {
            startCloudSync()
        } else {
            stopCloudSync()
        }
        settings.updateCloudSync(cloudSyncDisplay)
    }

    /// 「重設這台 Mac 的雲端副本」＝刪除自己的資料夾並關閉同步（R1-18）。本機正本不動
    func resetCloudSyncCopy() async {
        guard let folder = makeSyncFolder() else { return }
        setCloudSyncEnabled(false)
        do {
            try await Task.detached { try folder.removeOwnFolder() }.value
        } catch {
            cloudSyncLog.error("cloud sync reset failed")
            cloudSyncStatus = (cloudSyncStatus ?? .init()).failing("resetFailed")
        }
        settings.updateCloudSync(cloudSyncDisplay)
    }

    func markCloudSyncDirty(_ kind: SyncKind) {
        guard let cloudSync else { return }
        Task { await cloudSync.markDirty(kind) }
    }

    /// 結束 app：dirty 的小類別盡力匯出，最多 `cloudSyncQuitBudget`。時間軸不在這裡匯出（整庫掃描加編碼常超過 2 s，
    /// 效率評審 #5）：下次啟動比雜湊補上
    func flushCloudSync(budget: Duration = AppModel.cloudSyncQuitBudget) async {
        guard let cloudSync else { return }
        _ = await SyncDeadline.run(budget, clock: cloudSyncEnvironment?.readDeadline ?? SystemPollClock()) {
            await cloudSync.flushDirty(skipping: [.timings])
        }
    }

    /// 關閉＝停止讀寫；他機的時間軸候選一併清掉（關閉後查找不得再用，效率評審 #6）
    func stopCloudSync() {
        let running = cloudSyncTask
        running?.cancel()
        cloudSyncTask = nil
        cloudSync = nil
        // 先等舊排程器真的結束（取消擋不住進行中的匯入寫索引）再清；下一次開啟再等這次清完
        // （codex review R2／R3、層級評審 R3：清除不得早於舊匯入、也不得晚於新匯入）
        let previous = cloudSyncIndexClear
        if let remoteTimingIndex {
            cloudSyncIndexClear = Task {
                await previous?.value
                await running?.value
                await remoteTimingIndex.clear()
            }
        }
    }

    // MARK: 內部

    private func makeSyncFolder() -> SyncFolder? {
        guard let environment = cloudSyncEnvironment else { return nil }
        do {
            let writer = try SyncWriterID.current(from: environment.hardware)
            cloudSyncUnavailable = false
            return SyncFolder(root: environment.root, writerID: writer, appVersion: environment.appVersion, downloads: environment.downloads,
                              onAccess: environment.folderAccess)
        } catch {
            cloudSyncUnavailable = true
            cloudSyncLog.error("cloud sync unavailable: no hardware identity")
            return nil
        }
    }

    private func startCloudSync() {
        guard cloudSync == nil, let environment = cloudSyncEnvironment, let folder = makeSyncFolder() else { return }
        let coordinator = CloudSyncCoordinator(
            folder: folder, channels: cloudSyncChannels(), clock: environment.clock, readDeadline: environment.readDeadline,
            wallClock: environment.wallClock, lock: environment.lockURL.map(SyncLock.init(url:)),
            publish: { [weak self] status in await self?.receiveCloudSyncStatus(status) }
        )
        cloudSync = coordinator
        let pendingClear = cloudSyncIndexClear
        cloudSyncIndexClear = nil
        cloudSyncTask = Task(priority: .utility) {
            await pendingClear?.value
            // 等待期間又被關掉：不啟動（否則關了仍會讀寫 iCloud）
            guard !Task.isCancelled else { return }
            await coordinator.run()
        }
    }

    private func receiveCloudSyncStatus(_ status: CloudSyncCoordinator.Status) {
        cloudSyncStatus = status
        settings.updateCloudSync(cloudSyncDisplay)
    }

    private func cloudSyncChannels() -> [CloudSyncChannel] {
        var channels = [decisionsChannel(), noLyricsChannel()]
        if let sync = artistStyleSync() { channels.append(Self.artistsChannel(sync)) }
        if let timingStore, let remoteTimingIndex, let environment = cloudSyncEnvironment {
            channels.append(Self.timingsChannel(store: timingStore, index: remoteTimingIndex, now: environment.wallClock))
        }
        return channels
    }

    // MARK: 時間軸

    nonisolated static func timingsChannel(store: TimingStore, index: RemoteTimingIndex, now: @escaping @Sendable () -> Date) -> CloudSyncChannel {
        .make(
            kind: .timings, as: SyncPayload.Timings.self,
            stamp: { writer in _ = try await store.stampAll(by: writer) },
            payload: { SyncPayload.canonicalTimings(await store.allRecords()) },
            adopt: { envelopes in
                var result = CloudSyncAdoption.none
                for envelope in envelopes {
                    let records = envelope.payload.compactMap(\.record).filter { $0.isAcceptableRemote(now: now()) }
                    result = result + CloudSyncAdoption(rejected: envelope.payload.count - records.count, changed: false)
                    // 跨 persistentID 的候選：整台換（§6.5）
                    await index.replace(writer: envelope.writerID, records: records)
                    for record in records {
                        do {
                            if try await store.adopt(record) { result = result + CloudSyncAdoption(rejected: 0, changed: true) }
                        } catch TimingStore.StoreError.unrecognizedFileOnDisk {
                            // 本機那份看不懂（較新版本、符號連結）：永久性的，算拒收，不觸發每輪全量重試（效率評審 R2-2）
                            result = result + CloudSyncAdoption(rejected: 1, changed: false)
                        } catch {
                            result = result + CloudSyncAdoption(rejected: 0, changed: false, failed: true)
                        }
                    }
                }
                return result
            }
        )
    }

    // MARK: MB 歌手（唯一擁有者是 ArtistStyleSync）

    nonisolated static func artistsChannel(_ sync: ArtistStyleSync) -> CloudSyncChannel {
        .make(
            kind: .artists, as: SyncPayload.Artists.self,
            stamp: { writer in try await sync.stamp(by: writer) },
            payload: { SyncPayload.canonicalArtists(await sync.records()) },
            adopt: { envelopes in
                var result = CloudSyncAdoption.none
                for envelope in envelopes { result = result + (await sync.adopt(remote: envelope.payload)) }
                return result
            }
        )
    }

    // MARK: 使用者決定

    private func decisionsChannel() -> CloudSyncChannel {
        .make(
            kind: .decisions, as: SyncPayload.Decisions.self,
            stamp: { [weak self] writer in try await self?.stampDecisions(by: writer) },
            payload: { [weak self] in await self?.decisionEntries() ?? [:] },
            adopt: { [weak self] envelopes in await self?.adoptRemoteDecisions(envelopes) ?? .none }
        )
    }

    private func decisionEntries() -> SyncPayload.Decisions {
        decisionBook.entries
    }

    private func stampDecisions(by writer: String) throws {
        let stamped = decisionBook.stamped(by: writer)
        guard stamped != decisionBook else { return }
        try replaceDecisions(stamped)
    }

    func adoptRemoteDecisions(_ envelopes: [SyncEnvelope<SyncPayload.Decisions>]) -> CloudSyncAdoption {
        let merged = envelopes.reduce((book: decisionBook, rejected: 0)) { result, envelope in
            let next = result.book.merging(remote: envelope.payload)
            return (next.book, result.rejected + next.rejected)
        }
        guard merged.book != decisionBook else { return CloudSyncAdoption(rejected: merged.rejected, changed: false) }
        do {
            try replaceDecisions(merged.book)
        } catch {
            cloudSyncLog.error("remote decisions not written")
            return CloudSyncAdoption(rejected: merged.rejected, changed: false, failed: true)
        }
        return CloudSyncAdoption(rejected: merged.rejected, changed: true)
    }

    /// 先落盤、再換快照（與 `saveDecisions` 同順序）；曲庫檢查視窗一併換
    private func replaceDecisions(_ book: ArtistDecisionBook) throws {
        try artistDecisions?.save(book)
        decisionBook = book
        libraryCheck.decisionsReplaced(book)
    }

    // MARK: 沒有歌詞標記（ledger 的讀改寫一律在主執行緒，與 LyricsFlow 的標記同序）

    private func noLyricsChannel() -> CloudSyncChannel {
        .make(
            kind: .nolyrics, as: SyncPayload.NoLyrics.self,
            stamp: { [weak self] writer in await self?.stampMarks(by: writer) },
            payload: { [weak self] in await self?.markLedger() ?? [:] },
            adopt: { [weak self] envelopes in await self?.adoptRemoteMarks(envelopes) ?? .none }
        )
    }

    private func markLedger() -> SyncPayload.NoLyrics {
        configStore.noLyricsMarkLedger
    }

    private func stampMarks(by writer: String) {
        let ledger = configStore.noLyricsMarkLedger
        let stamped = ledger.mapValues { $0.stamped(by: writer) }
        guard stamped != ledger else { return }
        configStore.writeNoLyricsMarkLedger(stamped)
    }

    func adoptRemoteMarks(_ envelopes: [SyncEnvelope<SyncPayload.NoLyrics>]) -> CloudSyncAdoption {
        let local = configStore.noLyricsMarkLedger
        var rejected = 0
        let merged = envelopes.reduce(local) { ledger, envelope in
            let valid = envelope.payload.filter { Self.isAcceptableMark($0.key, $0.value) }
            rejected += envelope.payload.count - valid.count
            return SyncRegister.merged(ledger, valid)
        }
        guard merged != local else { return CloudSyncAdoption(rejected: rejected, changed: false) }
        configStore.writeNoLyricsMarkLedger(merged)
        lyricsFlow.marksChangedExternally()
        return CloudSyncAdoption(rejected: rejected, changed: true)
    }

    /// 標記的逐筆驗證（§6.3）：pid 16 位 hex、已蓋章、revision 非負、值只能是 true 或墓碑
    nonisolated static func isAcceptableMark(_ persistentID: String, _ register: SyncRegister<Bool>) -> Bool {
        TimingStore.isCanonicalID(persistentID) && register.version.isAcceptable(allowUnstamped: false) && register.value != false
    }
}

extension CloudSyncCoordinator.Status {
    func failing(_ kind: String) -> Self {
        var copy = self
        copy.lastError = kind
        return copy
    }
}

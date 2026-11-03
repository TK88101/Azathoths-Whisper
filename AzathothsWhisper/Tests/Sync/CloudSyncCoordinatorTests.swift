import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.4–§6.5、T5：dirty 節奏與最長延遲、啟動雜湊比對、匯入冪等、未下載跳過、逾時丟棄、鎖、不寫他機資料夾。
// 時鐘一律注入（FakeTimingClock：sleep 直接推進時間）；一律在臨時目錄
@Suite("Cloud sync coordinator")
struct CloudSyncCoordinatorTests {
    static let me = "000000000000000a"
    static let other = "000000000000000b"
    static let wall = Date(timeIntervalSince1970: 1_790_000_000)

    /// 記憶體裡的「本機正本」：一份標記 ledger
    actor MemoryLedger {
        var ledger: SyncPayload.NoLyrics = [:]
        private(set) var adoptCalls = 0
        func set(_ ledger: SyncPayload.NoLyrics) { self.ledger = ledger }
        func stamp(_ writer: String) { ledger = ledger.mapValues { $0.stamped(by: writer) } }
        func adopt(_ envelopes: [SyncEnvelope<SyncPayload.NoLyrics>]) -> CloudSyncAdoption {
            adoptCalls += 1
            let before = ledger
            ledger = envelopes.reduce(ledger) { SyncRegister.merged($0, $1.payload) }
            return CloudSyncAdoption(rejected: 0, changed: ledger != before)
        }
    }

    /// 永不醒的期限（正常讀檔不會逾時）；被取消就結束
    struct NeverDeadline: PollClock {
        func sleep(for interval: Duration) async throws { try await Task.sleep(for: .seconds(86_400)) }
    }

    actor Published {
        private(set) var statuses: [CloudSyncCoordinator.Status] = []
        func add(_ status: CloudSyncCoordinator.Status) { statuses.append(status) }
        var last: CloudSyncCoordinator.Status? { statuses.last }
    }

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("azw-coordinator-\(UUID().uuidString)")
    }

    private func channel(_ memory: MemoryLedger) -> CloudSyncChannel {
        CloudSyncChannel.make(
            kind: .nolyrics, as: SyncPayload.NoLyrics.self,
            stamp: { writer in await memory.stamp(writer) },
            payload: { await memory.ledger },
            adopt: { envelopes in await memory.adopt(envelopes) }
        )
    }

    private func coordinator(
        _ root: URL, channels: [CloudSyncChannel], clock: FakeTimingClock, deadline: any PollClock = NeverDeadline(),
        lock: SyncLock? = nil, published: Published = Published()
    ) -> CloudSyncCoordinator {
        CloudSyncCoordinator(
            folder: SyncFolder(root: root, writerID: Self.me, appVersion: "3.1.0", downloads: UbiquitousDownloadProbe()),
            channels: channels, clock: clock, readDeadline: deadline, wallClock: { Self.wall }, lock: lock,
            publish: { status in await published.add(status) }
        )
    }

    private func mark(_ pid: String, origin: String = "") -> SyncPayload.NoLyrics {
        [pid: SyncRegister(value: true, version: SyncVersion(revision: 1, origin: origin))]
    }

    private func ownFile(_ root: URL) -> URL { root.appendingPathComponent("Sync/\(Self.me)/nolyrics.json") }

    private func writeOther(_ root: URL, _ payload: SyncPayload.NoLyrics) throws {
        try SyncFolder(root: root, writerID: Self.other, appVersion: "3.1.0", downloads: UbiquitousDownloadProbe())
            .write(payload, kind: .nolyrics, at: Self.wall)
    }

    private func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    @Test func startStampsImportsThenExports() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let memory = MemoryLedger()
        await memory.set(mark("AAAA000000000001"))
        try writeOther(root, mark("AAAA000000000002", origin: Self.other))
        let sync = coordinator(root, channels: [channel(memory)], clock: FakeTimingClock())
        await sync.start()
        let ledger = await memory.ledger
        #expect(ledger["AAAA000000000001"]?.version.origin == Self.me, "先補 origin")
        #expect(ledger["AAAA000000000002"] != nil, "再匯入")
        let exported = try SyncCodec.decode(Data(contentsOf: ownFile(root)), as: SyncPayload.NoLyrics.self, kind: .nolyrics, expectedWriter: Self.me).get()
        #expect(exported.payload == ledger, "最後匯出聯集")
    }

    @Test func aSecondStartWithNothingNewDoesNotRewrite() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let memory = MemoryLedger()
        await memory.set(mark("AAAA000000000001"))
        await coordinator(root, channels: [channel(memory)], clock: FakeTimingClock()).start()
        let first = try Data(contentsOf: ownFile(root))
        await coordinator(root, channels: [channel(memory)], clock: FakeTimingClock()).start()
        #expect(try Data(contentsOf: ownFile(root)) == first, "雜湊相同不重寫（writtenAt 也不變）")
    }

    @Test func manyChangesInsideTheQuietPeriodExportOnce() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let memory = MemoryLedger()
        let clock = FakeTimingClock()
        let published = Published()
        let sync = coordinator(root, channels: [channel(memory)], clock: clock, published: published)
        await sync.start()
        let exportsAfterStart = await sync.exportCount
        for index in 1...3 {
            await memory.set(mark(String(format: "AAAA%012d", index)))
            await sync.markDirty(.nolyrics)
            clock.advance(by: 3)
            await sync.tick()
        }
        #expect(await sync.exportCount == exportsAfterStart, "10 s 安靜期內不匯出")
        clock.advance(by: 10)
        await sync.tick()
        #expect(await sync.exportCount == exportsAfterStart + 1)
        #expect(await published.last?.lastExport == Self.wall)
    }

    @Test func continuousTimingWritesStillExportWithinTheMaximumDelay() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let memory = MemoryLedger()
        let clock = FakeTimingClock()
        let timings = CloudSyncChannel.make(kind: .timings, as: SyncPayload.NoLyrics.self, stamp: { _ in }, payload: { await memory.ledger },
                                            adopt: { _ in CloudSyncAdoption(rejected: 0, changed: false) })
        let sync = coordinator(root, channels: [timings], clock: clock)
        await sync.start()
        let base = await sync.exportCount
        var elapsed: TimeInterval = 0
        while elapsed < 1_800 {
            await sync.markDirty(.timings)
            clock.advance(by: 120)
            elapsed += 120
            await sync.tick()
        }
        #expect(await sync.exportCount == base + 1, "每 2 分鐘就有新寫入、從不安靜 5 分鐘，30 分內仍匯出一次")
    }

    @Test func quitFlushesOnlyDirtyKinds() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let memory = MemoryLedger()
        let sync = coordinator(root, channels: [channel(memory)], clock: FakeTimingClock())
        await sync.start()
        let base = await sync.exportCount
        await sync.flushDirty()
        #expect(await sync.exportCount == base)
        await memory.set(mark("AAAA000000000009"))
        await sync.markDirty(.nolyrics)
        await sync.flushDirty()
        #expect(await sync.exportCount == base + 1)
    }

    @Test func anUnchangedRemoteFileIsNotAdoptedAgain() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let memory = MemoryLedger()
        try writeOther(root, mark("AAAA000000000002", origin: Self.other))
        let clock = FakeTimingClock()
        let sync = coordinator(root, channels: [channel(memory)], clock: clock)
        await sync.start()
        #expect(await memory.adoptCalls == 1)
        clock.advance(by: CloudSyncCoordinator.importInterval)
        await sync.tick()
        #expect(await memory.adoptCalls == 1, "同一份雜湊不再採用")
        try writeOther(root, mark("AAAA000000000003", origin: Self.other))
        clock.advance(by: CloudSyncCoordinator.importInterval)
        await sync.tick()
        #expect(await memory.adoptCalls == 2)
        #expect(await memory.ledger["AAAA000000000003"] != nil)
    }

    @Test func anAdoptionThatChangesLocalDataSchedulesAnExport() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let memory = MemoryLedger()
        let clock = FakeTimingClock()
        let sync = coordinator(root, channels: [channel(memory)], clock: clock)
        await sync.start()
        let base = await sync.exportCount
        try writeOther(root, mark("AAAA000000000004", origin: Self.other))
        clock.advance(by: CloudSyncCoordinator.importInterval)
        await sync.tick()
        clock.advance(by: 11)
        await sync.tick()
        #expect(await sync.exportCount == base + 1, "聯集轉出")
    }

    @Test func importingNeverWritesTheOtherWritersFolder() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeOther(root, mark("AAAA000000000002", origin: Self.other))
        let theirs = root.appendingPathComponent("Sync/\(Self.other)/nolyrics.json")
        let before = try Data(contentsOf: theirs)
        let memory = MemoryLedger()
        await memory.set(mark("AAAA000000000001"))
        await coordinator(root, channels: [channel(memory)], clock: FakeTimingClock()).start()
        #expect(try Data(contentsOf: theirs) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Sync/\(Self.other)").path) == ["nolyrics.json"])
    }

    @Test func aReadThatOutlivesTheDeadlineIsDiscarded() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = AsyncGate()
        let applied = Applied()
        let slow = CloudSyncChannel(
            kind: .nolyrics, stamp: { _ in }, localHash: { "" }, export: { _, _ in },
            read: { _, _ in
                await gate.wait()
                return CloudSyncRead(writers: [:], hashes: [:], skipped: 0, pendingDownloads: 0, apply: { await applied.hit(); return CloudSyncAdoption(rejected: 0, changed: true) })
            }
        )
        let published = Published()
        let sync = coordinator(root, channels: [slow], clock: FakeTimingClock(), deadline: FakeTimingClock(), published: published)
        await sync.start()
        #expect(await published.last?.lastError == "readTimeout")
        await gate.open()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await applied.count == 0, "逾時後晚到的結果不採用")
    }

    @Test func whenAnotherInstanceHoldsTheLockNothingIsExported() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appendingPathComponent("local/sync.lock")
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let held = try #require(SyncLock(url: lockURL).tryAcquire(), "另一個實例拿著鎖")
        let memory = MemoryLedger()
        await memory.set(mark("AAAA000000000001"))
        await coordinator(root, channels: [channel(memory)], clock: FakeTimingClock(), lock: SyncLock(url: lockURL)).start()
        #expect(FileManager.default.fileExists(atPath: ownFile(root).path) == false)
        held.release()
        await coordinator(root, channels: [channel(memory)], clock: FakeTimingClock(), lock: SyncLock(url: lockURL)).start()
        #expect(FileManager.default.fileExists(atPath: ownFile(root).path), "放開後照常匯出")
    }

    @Test func otherWritersAndSkippedFilesAreReported() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeOther(root, mark("AAAA000000000002", origin: Self.other))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sync/NOT-A-WRITER"), withIntermediateDirectories: true)
        let published = Published()
        await coordinator(root, channels: [channel(MemoryLedger())], clock: FakeTimingClock(), published: published).start()
        let status = try #require(await published.last)
        #expect(status.otherWriters == [Self.other: Self.wall])
        #expect(status.skipped == 1)
        #expect(status.lastImport == Self.wall)
    }
}

/// 一次性放行的閘
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

actor Applied {
    private(set) var count = 0
    func hit() { count += 1 }
}

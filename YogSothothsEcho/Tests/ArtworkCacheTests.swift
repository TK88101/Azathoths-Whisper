import Foundation
import RemoteProtocol
import RemoteTransport
import Testing
import UIKit

@testable import YogSothothsEcho

// S3 T10（sprint-3-detail.md §4.6）：磁碟 LRU 索引（純值）、記憶體 LRU、封面快取的合併／撤回／stale

struct DiskLRUIndexTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func evictsLeastRecentlyUsedDownToTarget() {
        var index = DiskLRUIndex(limit: 100, target: 60)
        index.record("a", bytes: 40, at: t0)
        index.record("b", bytes: 40, at: t0 + 1)
        index.touch("a", at: t0 + 2)                     // a 變成最近使用
        index.record("c", bytes: 40, at: t0 + 3)         // 120 > 100 → 淘汰到 ≤ 60
        let victims = index.evict()
        #expect(victims == ["b", "a"])
        #expect(index.totalBytes <= 60)
        #expect(index.contains("c"))
    }

    @Test func noEvictionUnderLimit() {
        var index = DiskLRUIndex(limit: 100, target: 60)
        index.record("a", bytes: 90, at: t0)
        #expect(index.evict().isEmpty && index.totalBytes == 90)
    }

    @Test func rerecordReplacesSize() {
        var index = DiskLRUIndex(limit: 100, target: 60)
        index.record("a", bytes: 90, at: t0)
        index.record("a", bytes: 10, at: t0 + 1)
        #expect(index.totalBytes == 10)
    }

    @Test func roundTripsAsJSON() throws {
        var index = DiskLRUIndex(limit: 100, target: 60)
        index.record("a", bytes: 5, at: t0)
        let decoded = try JSONDecoder().decode(DiskLRUIndex.self, from: JSONEncoder().encode(index))
        #expect(decoded == index)
    }

    @Test func rebuildsFromFileListing() {
        let index = DiskLRUIndex.rebuilt(from: [("a", 10, t0), ("b", 20, t0 + 1)], limit: 100, target: 60)
        #expect(index.totalBytes == 30 && index.contains("a") && index.contains("b"))
    }
}

struct ImageLRUTests {
    @Test func evictsByCost() {
        var lru = MemoryLRU<String, Int>(costLimit: 10)
        lru.set("a", 1, cost: 6)
        lru.set("b", 2, cost: 6)
        #expect(lru.value(for: "a") == nil && lru.value(for: "b") == 2)
    }
}

/// 可控的封面來源：記錄呼叫、可擋住、可指定回應
final class ScriptedArtworkSource: @unchecked Sendable {
    let lock = NSLock()
    var calls = 0
    var outcome: ArtworkOutcome = .image
    var blocked = false
    var gates: [CheckedContinuation<Void, Never>] = []
    /// 第 n 次 fetch（從 1 起）丟這個錯（F-L1 R4）
    var failuresOnCall: [Int: EchoRequestError] = [:]

    static let jpeg: Data = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 0.8) { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    func fetch(albumID: String, token: String) async throws(EchoRequestError) -> ArtworkResponse {
        let (wait, outcome, failure) = lock.withLock { () -> (Bool, ArtworkOutcome, EchoRequestError?) in
            calls += 1
            return (blocked, self.outcome, failuresOnCall[calls])
        }
        if wait { await withCheckedContinuation { c in lock.withLock { gates.append(c) } } }
        if let failure { throw failure }
        switch outcome {
        case .image: return ArtworkResponse(albumID: albumID, size: .spine, outcome: .image, artworkToken: token, jpeg: Self.jpeg)
        // restart／tooLarge 只屬於 detail（CR-018），替身照樣回給 spine 以驗證被當成沒有封面
        case .none, .restart, .tooLarge: return ArtworkResponse(albumID: albumID, size: .spine, outcome: outcome, artworkToken: token, jpeg: nil)
        case .stale: return ArtworkResponse(albumID: albumID, size: .spine, outcome: .stale, artworkToken: "ffffffffffffffff", jpeg: nil)
        }
    }

    func releaseAll() { lock.withLock { () -> [CheckedContinuation<Void, Never>] in defer { gates = [] }; return gates }.forEach { $0.resume() } }
    var callCount: Int { lock.withLock { calls } }
    var waiting: Int { lock.withLock { gates.count } }
}

func eventually(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

struct ArtworkCacheTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-\(UUID().uuidString)")
    let source = ScriptedArtworkSource()

    let sleeper = CancellableSleeper()

    func cache(diskLimit: Int = 500_000, stale: @escaping @Sendable () -> Void = {}) -> ArtworkCache {
        let source = self.source
        return ArtworkCache(directory: directory, diskLimit: diskLimit, diskTarget: diskLimit * 9 / 10,
                            fetch: { (albumID, token) throws(EchoRequestError) in try await source.fetch(albumID: albumID, token: token) }, onStale: stale,
                            retry: sleeper.options)
    }

    /// F-L1 R4：busy／rateLimited 短重試（共用規則：最多 3 次、等 0.5 s、1.0 s）
    @Test func busyIsRetriedThenServed() async {
        source.lock.withLock { source.failuresOnCall = [1: .remote(.busy)] }
        #expect(await cache().image(albumID: "0000000000000001", token: "00000000000000aa") != nil)
        #expect(source.callCount == 2)
        #expect(sleeper.durations == [.milliseconds(500)])
    }

    @Test func persistentRateLimitGivesUpAfterThreeTries() async {
        source.lock.withLock { source.failuresOnCall = [1: .remote(.rateLimited), 2: .remote(.busy), 3: .remote(.rateLimited)] }
        #expect(await cache().image(albumID: "0000000000000001", token: "00000000000000aa") == nil)
        #expect(source.callCount == 3)
        #expect(sleeper.durations == [.milliseconds(500), .seconds(1)])
    }

    /// 睡眠拋錯＝nil（格子維持佔位），不再送；不承諾可取消（佇列工作 `.finishRunning`；Codex R2 高-2、R5-2）
    @Test func sleepFailureGivesNil() async {
        source.lock.withLock { source.failuresOnCall = [1: .remote(.busy)] }
        sleeper.lock.withLock { sleeper.failure = SleepFailure() }
        #expect(await cache().image(albumID: "0000000000000001", token: "00000000000000aa") == nil)
        #expect(source.callCount == 1)
    }

    @Test func fetchesOnceThenServesFromMemoryAndDisk() async throws {
        let first = cache()
        #expect(await first.image(albumID: "0000000000000001", token: "00000000000000aa") != nil)
        #expect(await first.image(albumID: "0000000000000001", token: "00000000000000aa") != nil)
        #expect(source.callCount == 1)
        let reopened = cache()                                          // 新實例＝重開 app：從磁碟讀
        #expect(await reopened.image(albumID: "0000000000000001", token: "00000000000000aa") != nil)
        #expect(source.callCount == 1)
    }

    /// 側封快甩（#6-1）：只是滑過的盒子不向 Mac 要——要上網前先等一下，等的期間被取消（盒子已離開畫面）就不送
    @Test func deferredNetworkFetchIsSkippedWhenCancelled() async {
        let c = cache()
        let task = Task { await c.image(albumID: "0000000000000001", token: "00000000000000aa", networkDelay: .seconds(5)) }
        try? await Task.sleep(for: .milliseconds(30))
        task.cancel()
        #expect(await task.value == nil)
        #expect(source.callCount == 0)
    }

    /// 記憶體與磁碟命中不等：只有要上網的才延後
    @Test func deferredFetchStillServesCacheImmediately() async {
        let warm = cache()
        _ = await warm.image(albumID: "0000000000000001", token: "00000000000000aa")
        let started = Date()
        #expect(await warm.image(albumID: "0000000000000001", token: "00000000000000aa", networkDelay: .seconds(5)) != nil)
        #expect(Date().timeIntervalSince(started) < 1)
        let delayed = await cache().image(albumID: "0000000000000002", token: "00000000000000aa", networkDelay: .milliseconds(10))
        #expect(delayed != nil && source.callCount == 2)
    }

    @Test func differentTokenMisses() async {
        let c = cache()
        _ = await c.image(albumID: "0000000000000001", token: "00000000000000aa")
        _ = await c.image(albumID: "0000000000000001", token: "00000000000000bb")
        #expect(source.callCount == 2)
    }

    @Test func staleIsNotCachedAndNotifiesOnce() async {
        source.lock.withLock { source.outcome = .stale }
        let count = Locked(0)
        let c = cache(stale: { count.withLock { $0 += 1 } })
        #expect(await c.image(albumID: "0000000000000001", token: "00000000000000aa") == nil)
        #expect(await c.image(albumID: "0000000000000001", token: "00000000000000aa") == nil)
        #expect(source.callCount == 2)
        #expect(count.withLock { $0 } >= 1)
    }

    @Test func noneIsRememberedInMemory() async {
        source.lock.withLock { source.outcome = .none }
        let c = cache()
        #expect(await c.image(albumID: "0000000000000001", token: "00000000000000aa") == nil)
        #expect(await c.image(albumID: "0000000000000001", token: "00000000000000aa") == nil)
        #expect(source.callCount == 1)
    }

    @Test func concurrentRequestsShareOneFetch() async {
        source.lock.withLock { source.blocked = true }
        let c = cache()
        async let a = c.image(albumID: "0000000000000001", token: "00000000000000aa")
        async let b = c.image(albumID: "0000000000000001", token: "00000000000000aa")
        #expect(await eventually { source.waiting == 1 })
        source.releaseAll()
        let (ia, ib) = await (a, b)
        #expect(ia != nil && ib != nil && source.callCount == 1)
    }

    @Test func oneWaiterWithdrawingDoesNotStarveTheOther() async {
        source.lock.withLock { source.blocked = true }
        let c = cache()
        let first = Task { await c.image(albumID: "0000000000000001", token: "00000000000000aa") }
        let second = Task { await c.image(albumID: "0000000000000001", token: "00000000000000aa") }
        #expect(await eventually { source.waiting == 1 })
        first.cancel()
        source.releaseAll()
        #expect(await second.value != nil)
    }

    @Test func atMostFourFetchesInFlight() async {
        source.lock.withLock { source.blocked = true }
        let c = cache()
        let tasks = (1...6).map { i in Task { await c.image(albumID: String(format: "%016llx", UInt64(i)), token: "00000000000000aa") } }
        #expect(await eventually { source.waiting == ArtworkCache.maxInFlight })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(source.waiting == ArtworkCache.maxInFlight)
        source.releaseAll()
        #expect(await eventually { source.waiting == 2 })
        source.releaseAll()
        for task in tasks { _ = await task.value }
        #expect(source.callCount == 6)
    }

    @Test func diskOverLimitEvictsOldFiles() async throws {
        let c = cache(diskLimit: ScriptedArtworkSource.jpeg.count * 3)
        for i in 1...5 { _ = await c.image(albumID: String(format: "%016llx", UInt64(i)), token: "00000000000000aa") }
        await c.flushIndex()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".jpg") }
        #expect(files.count <= 3)
    }

    @Test func corruptIndexIsRebuiltFromFiles() async throws {
        let c = cache()
        _ = await c.image(albumID: "0000000000000001", token: "00000000000000aa")
        await c.flushIndex()
        try Data("not json".utf8).write(to: directory.appendingPathComponent(ArtworkCache.indexFileName))
        let reopened = cache()
        #expect(await reopened.image(albumID: "0000000000000001", token: "00000000000000aa") != nil)
        #expect(source.callCount == 1)
    }

    @Test func fileNamesDoNotContainIDs() async throws {
        let c = cache()
        _ = await c.image(albumID: "0000000000000001", token: "00000000000000aa")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!names.contains { $0.contains("0000000000000001") })
    }
}

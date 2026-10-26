import Foundation
import Testing
import UIKit

@testable import YogSothothsEcho

// S6 T4（sprint-6-detail.md D8、§4.4）：detail 原檔單飛排程——同時只一個傳輸、高優先搶占、demand 撤銷、同 key 合併

/// 可控的傳輸替身：每個 fetch 停在閘門，等測試 complete 或被取消；記錄開始順序、取消、並發數
actor FakeTransfers {
    private(set) var started: [String] = []
    private(set) var cancelled: [String] = []
    private(set) var active = 0
    private(set) var maxActive = 0
    private var gates: [String: CheckedContinuation<Data?, Never>] = [:]
    var cache: [String: Data] = [:]

    func cached(_ albumID: String) -> Data? { cache[albumID] }

    func fetch(_ albumID: String) async -> Data? {
        started.append(albumID)
        active += 1
        maxActive = max(maxActive, active)
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                if Task.isCancelled {
                    cancelled.append(albumID)
                    continuation.resume(returning: nil)
                } else {
                    gates[albumID] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelGate(albumID) }
        }
        active -= 1
        return result
    }

    private func cancelGate(_ albumID: String) {
        guard let gate = gates.removeValue(forKey: albumID) else { return }
        cancelled.append(albumID)
        gate.resume(returning: nil)
    }

    func complete(_ albumID: String, _ data: Data? = Data([1])) {
        gates.removeValue(forKey: albumID)?.resume(returning: data)
    }

    func isWaiting(_ albumID: String) -> Bool { gates[albumID] != nil }
    /// 目前掛在閘門上的傳輸
    var waiting: [String] { gates.keys.sorted() }
    /// 失敗時的狀態（偶發紅診斷用）
    var diagnostics: String { "started=\(started) cancelled=\(cancelled) waiting=\(waiting) active=\(active)" }
}

/// 收集 request 的結果（每個 request 在自己的 Task，取消＝撤銷 demand）
actor Results {
    private(set) var values: [String: Data?] = [:]
    func set(_ key: String, _ value: Data?) { values[key] = value }
    func has(_ key: String) -> Bool { values[key] != nil }
}

struct DetailArtworkSchedulerTests {
    let fake = FakeTransfers()
    let results = Results()

    func scheduler() -> DetailArtworkScheduler {
        let fake = fake
        return DetailArtworkScheduler(cached: { id, _ in await fake.cached(id) }, fetch: { id, _ in await fake.fetch(id) })
    }

    @discardableResult
    func request(_ s: DetailArtworkScheduler, _ id: String, _ priority: DetailArtworkScheduler.Priority, as name: String? = nil,
                 token: String? = "t") -> Task<Void, Never> {
        let results = results
        return Task { await results.set(name ?? id, await s.request(albumID: id, token: token, priority: priority)) }
    }

    func eventually(_ condition: @escaping () async -> Bool) async -> Bool {
        for _ in 0..<400 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    @Test func onlyOneTransferAtATime() async {
        let s = scheduler()
        for id in ["a", "b", "c"] { request(s, id, .browse(distance: 0)) }
        #expect(await eventually { await fake.started.count == 1 })
        for round in 1...3 {
            #expect(await eventually { await fake.started.count == round })
            let current = await fake.started.last!
            #expect(await eventually { await fake.isWaiting(current) })
            await fake.complete(current)
            #expect(await eventually { await results.has(current) })
        }
        #expect(await eventually { await results.values.count == 3 })
        #expect(await fake.maxActive == 1)
        #expect(Set(await fake.started) == ["a", "b", "c"])
    }

    /// 大型 browse 傳輸進行中開唱機＝browse 被取消、唱機立即開始；之後 browse（demand 仍在）重排並完成
    @Test func turntablePreemptsBrowseAndBrowseResumes() async {
        let s = scheduler()
        request(s, "big", .browse(distance: 0))
        #expect(await eventually { await fake.isWaiting("big") })
        request(s, "tt", .turntable)
        #expect(await eventually { await fake.isWaiting("tt") })
        #expect(await fake.cancelled == ["big"])
        await fake.complete("tt")
        #expect(await eventually { await results.has("tt") })
        #expect(await eventually { await fake.isWaiting("big") })
        await fake.complete("big")
        #expect(await eventually { await results.has("big") })
        #expect(await fake.started == ["big", "tt", "big"])
        #expect(await fake.maxActive == 1)
    }

    @Test func turntablePreemptsOpened() async {
        let s = scheduler()
        request(s, "album", .opened)
        #expect(await eventually { await fake.isWaiting("album") })
        request(s, "tt", .turntable)
        #expect(await eventually { await fake.isWaiting("tt") })
        #expect(await fake.cancelled == ["album"])
    }

    /// browse 不搶占 browse；opened 搶占 browse
    @Test func preemptionFollowsTiers() async {
        let s = scheduler()
        request(s, "far", .browse(distance: 2))
        #expect(await eventually { await fake.isWaiting("far") })
        request(s, "near", .browse(distance: 0))
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await fake.cancelled.isEmpty)
        request(s, "open", .opened)
        #expect(await eventually { await fake.isWaiting("open") })
        #expect(await fake.cancelled == ["far"])
        await fake.complete("open")
        // 接著較近的 browse 先於較遠的
        #expect(await eventually { await fake.isWaiting("near") })
    }

    /// 離開可見範圍時 browse 正在傳＝在途取消、不重排
    @Test func withdrawingRunningDemandCancelsTransfer() async {
        let s = scheduler()
        let task = request(s, "a", .browse(distance: 0))
        #expect(await eventually { await fake.isWaiting("a") })
        task.cancel()
        #expect(await eventually { await fake.cancelled == ["a"] })
        #expect(await eventually { await results.has("a") })
        #expect(await results.values["a"]! == nil)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await fake.started == ["a"])
    }

    /// 被搶占後 demand 已撤回＝不重排
    @Test func preemptedThenWithdrawnIsNotRequeued() async {
        let s = scheduler()
        let browse = request(s, "b", .browse(distance: 0))
        #expect(await eventually { await fake.isWaiting("b") })
        request(s, "tt", .turntable)
        #expect(await eventually { await fake.isWaiting("tt") })
        browse.cancel()
        #expect(await eventually { await results.has("b") })
        await fake.complete("tt")
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await fake.started == ["b", "tt"])
    }

    /// 同 key 一高一低 demand、撤掉高者＝優先序降回 browse
    @Test func withdrawingHighDemandLowersPriority() async {
        let s = scheduler()
        request(s, "run", .opened)
        #expect(await eventually { await fake.isWaiting("run") })
        request(s, "k", .browse(distance: 0), as: "k-browse")
        let high = request(s, "k", .opened, as: "k-opened")
        try? await Task.sleep(for: .milliseconds(20))
        high.cancel()
        #expect(await eventually { await results.has("k-opened") })
        request(s, "other", .opened)
        try? await Task.sleep(for: .milliseconds(20))
        await fake.complete("run")
        #expect(await eventually { await fake.isWaiting("other") })
        #expect(await !fake.isWaiting("k"))
    }

    /// 有更高優先排隊時 browse 不開始
    @Test func browseWaitsForHigherWork() async {
        let s = scheduler()
        request(s, "tt", .turntable)
        #expect(await eventually { await fake.isWaiting("tt") })
        request(s, "b", .browse(distance: 0))
        request(s, "o", .opened)
        try? await Task.sleep(for: .milliseconds(20))
        await fake.complete("tt")
        #expect(await eventually { await fake.isWaiting("o") })
        #expect(await !fake.isWaiting("b"))
        await fake.complete("o")
        #expect(await eventually { await fake.isWaiting("b") })
    }

    /// 同 key（含不同優先）合併成一個傳輸，所有 demand 都拿到同一份資料
    @Test func sameKeyIsTransferredOnce() async {
        let s = scheduler()
        request(s, "x", .browse(distance: 1), as: "x1")
        request(s, "x", .opened, as: "x2")
        #expect(await eventually { await fake.isWaiting("x") })
        await fake.complete("x", Data([7]))
        #expect(await eventually { await results.values.count == 2 })
        let values = await results.values
        #expect(values["x1"]! == Data([7]) && values["x2"]! == Data([7]))
        #expect(await fake.started == ["x"])
    }

    @Test func nilTokenSendsNothing() async {
        let s = scheduler()
        request(s, "n", .turntable, token: nil)
        #expect(await eventually { await results.has("n") })
        #expect(await fake.started.isEmpty)
    }

    @Test func withdrawnBeforeStartIsNeverSent() async {
        let s = scheduler()
        request(s, "run", .turntable)
        #expect(await eventually { await fake.isWaiting("run") })
        let queued = request(s, "q", .browse(distance: 0))
        try? await Task.sleep(for: .milliseconds(20))
        queued.cancel()
        #expect(await eventually { await results.has("q") })
        await fake.complete("run")
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await fake.started == ["run"])
    }

    /// 磁碟快取命中不經排隊：別的傳輸進行中也立即回
    @Test func cacheHitBypassesQueue() async {
        await fake.setCache("hit", Data([9]))
        let s = scheduler()
        request(s, "run", .turntable)
        #expect(await eventually { await fake.isWaiting("run") })
        request(s, "hit", .browse(distance: 3))
        #expect(await eventually { await results.has("hit") })
        #expect(await results.values["hit"]! == Data([9]))
        #expect(await fake.started == ["run"])
    }

    /// 斷線：全部回 nil、在途取消。到達順序固定（偶發紅另案 s6-61-scheduler-flaky.md：兩個獨立 Task 的到達順序不保證）
    /// 情境一：a 在傳、b 在排隊 → 只取消 a，b 從未開始
    @Test func cancelAllReturnsNilToEveryone() async {
        let s = scheduler()
        request(s, "a", .turntable)
        #expect(await eventually { await fake.isWaiting("a") })
        request(s, "b", .browse(distance: 0))
        #expect(await eventually { await s.pendingDemands == 2 })
        #expect(await fake.started == ["a"])
        await s.cancelAll()
        #expect(await eventually { await results.values.count == 2 })
        #expect(await results.values.values.allSatisfy { $0 == nil })
        let done = await eventually { let (c, w) = (await fake.cancelled, await fake.waiting); return c == ["a"] && w.isEmpty }
        let state = await fake.diagnostics
        #expect(done, "\(state)")
        #expect(await fake.started == ["a"])
    }

    /// 情境二：b 在傳、a 到達搶占 b、a 在傳時斷線 → b、a 依序被取消，沒有閘門掛著
    @Test func cancelAllAfterPreemptionCancelsBoth() async {
        let s = scheduler()
        request(s, "b", .browse(distance: 0))
        #expect(await eventually { await fake.isWaiting("b") })
        request(s, "a", .turntable)
        #expect(await eventually { await fake.isWaiting("a") })
        await s.cancelAll()
        #expect(await eventually { await results.values.count == 2 })
        #expect(await results.values.values.allSatisfy { $0 == nil })
        let done = await eventually { let (c, w) = (await fake.cancelled, await fake.waiting); return c == ["b", "a"] && w.isEmpty }
        let state = await fake.diagnostics
        #expect(done, "\(state)")
        #expect(await fake.started == ["b", "a"])
    }
}

extension FakeTransfers {
    func setCache(_ albumID: String, _ data: Data) { cache[albumID] = data }
}

/// 快取命中只驗檔頭：解不開（檔頭完好、像素損毀）＝刪掉這筆、重取一次，不會永遠卡在 spine
struct DetailArtworkSchedulerImageTests {
    actor Store {
        var cached: [String: Data] = [:]
        var evicted: [String] = []
        var fetched: [String] = []
        let good: Data
        init(good: Data) { self.good = good }
        func setCached(_ id: String, _ data: Data) { cached[id] = data }
        func lookup(_ id: String) -> Data? { cached[id] }
        func evict(_ id: String) { evicted.append(id); cached[id] = nil }
        func fetch(_ id: String) -> Data? { fetched.append(id); return good }
    }

    static func png() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    @Test func undecodableCacheHitIsEvictedAndRefetched() async {
        let store = Store(good: Self.png())
        var broken = Self.png()
        broken.replaceSubrange(broken.count - 20..<broken.count - 12, with: [UInt8](repeating: 0, count: 8))   // 檔頭完好、內容壞
        await store.setCached("a", broken.prefix(40))
        let s = DetailArtworkScheduler(cached: { id, _ in await store.lookup(id) }, fetch: { id, _ in await store.fetch(id) },
                                       evict: { id, _ in await store.evict(id) })
        let image = await s.image(albumID: "a", token: "t", priority: .opened)
        #expect(image != nil)
        #expect(await store.evicted == ["a"])
        #expect(await store.fetched == ["a"])
    }

    @Test func decodableCacheHitIsUsedAsIs() async {
        let store = Store(good: Self.png())
        await store.setCached("a", Self.png())
        let s = DetailArtworkScheduler(cached: { id, _ in await store.lookup(id) }, fetch: { id, _ in await store.fetch(id) },
                                       evict: { id, _ in await store.evict(id) })
        #expect(await s.image(albumID: "a", token: "t", priority: .opened) != nil)
        #expect(await store.evicted.isEmpty)
        #expect(await store.fetched.isEmpty)
    }
}

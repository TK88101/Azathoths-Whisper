import Testing
@testable import RemoteProtocol

// S4 T1（sprint-4-detail.md §4.11）：Mac CoalescingLimiter 與 iPad ArtworkCache 的合併邏輯收斂為一份。
// 前 7 條自 MusicRemoteBridgeTests 的 CoalescingLimiterTests 原樣移入（Mac 的策略：FIFO＋全員撤回即取消）；
// 後 4 條鎖住兩個策略參數的差異。

func eventually(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

/// 測試用的可控工作：記錄呼叫次數、同時進行數、是否被取消、開始順序
actor WorkProbe {
    private(set) var calls = 0
    private(set) var running = 0
    private(set) var maxRunning = 0
    private(set) var observedCancellation = 0
    private(set) var completed = 0
    private(set) var started: [Int] = []
    private var gates: [CheckedContinuation<Void, Never>] = []

    func begin(_ value: Int) { calls += 1; running += 1; maxRunning = max(maxRunning, running); started.append(value) }
    func end(cancelled: Bool) { running -= 1; if cancelled { observedCancellation += 1 } else { completed += 1 } }
    func wait() async { await withCheckedContinuation { gates.append($0) } }
    func releaseAll() { gates.forEach { $0.resume() }; gates.removeAll() }
    var waitingCount: Int { gates.count }

    /// 工作本體：開始 → 等放行 → 回值
    nonisolated func work(_ value: Int) -> @Sendable () async -> Int? {
        { [self] in
            await begin(value)
            await wait()
            let cancelled = Task.isCancelled
            await end(cancelled: cancelled)
            return cancelled ? nil : value
        }
    }
}

typealias MacQueue = CoalescingQueue<String, Int>

func macQueue(_ limit: Int) -> MacQueue { MacQueue(maxConcurrent: limit, order: .fifo, whenAbandoned: .cancelRunning) }
func padQueue(_ limit: Int) -> MacQueue { MacQueue(maxConcurrent: limit, order: .lifo, whenAbandoned: .finishRunning) }

struct CoalescingQueueTests {
    @Test func sameKeyRunsOnceAndAllWaitersGetValue() async {
        let queue = macQueue(2)
        let probe = WorkProbe()
        // 先讓 a 登記並開始執行，再送 b：兩個 async let 的起跑順序沒有保證（b 先登記時兩者都得 8，曾偶發紅）
        async let a = queue.run("k", probe.work(7))
        #expect(await eventually { await probe.waitingCount == 1 })
        async let b = queue.run("k", probe.work(8))
        #expect(await eventually { await queue.waiterCount("k") == 2 })
        await probe.releaseAll()
        let (va, vb) = await (a, b)
        #expect(va == 7 && vb == 7)
        #expect(await probe.calls == 1)
    }

    @Test func respectsConcurrencyLimit() async {
        let queue = macQueue(2)
        let probe = WorkProbe()
        async let a = queue.run("a", probe.work(1))
        async let b = queue.run("b", probe.work(2))
        async let c = queue.run("c", probe.work(3))
        #expect(await eventually { await probe.waitingCount == 2 })
        #expect(await probe.calls == 2)
        await probe.releaseAll()
        #expect(await eventually { await probe.waitingCount == 1 })
        await probe.releaseAll()
        let values = await [a, b, c]
        #expect(values == [1, 2, 3])
        #expect(await probe.maxRunning == 2)
    }

    @Test func allWaitersCancelledBeforeStartSkipsWork() async {
        let queue = macQueue(1)
        let probe = WorkProbe()
        let blocker = Task { await queue.run("busy", probe.work(0)) }
        #expect(await eventually { await probe.waitingCount == 1 })
        let queued = Task { await queue.run("queued", probe.work(9)) }
        try? await Task.sleep(for: .milliseconds(20))
        queued.cancel()
        #expect(await queued.value == nil)
        await probe.releaseAll()
        _ = await blocker.value
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await probe.calls == 1)   // queued 的工作從未開始
    }

    @Test func oneWaiterCancellingDoesNotStarveOthers() async {
        let queue = macQueue(1)
        let probe = WorkProbe()
        // 起跑順序沒有保證：先等 first 開始執行，再送 second 並等它登記（second 先登記時會得 6，曾偶發紅）
        let first = Task { await queue.run("k", probe.work(5)) }
        #expect(await eventually { await probe.waitingCount == 1 })
        let second = Task { await queue.run("k", probe.work(6)) }
        #expect(await eventually { await queue.waiterCount("k") == 2 })
        first.cancel()
        #expect(await first.value == nil)
        await probe.releaseAll()
        #expect(await second.value == 5)
        #expect(await probe.observedCancellation == 0)
    }

    @Test func allWaitersCancelledWhileRunningCancelsWork() async {
        let queue = macQueue(1)
        let probe = WorkProbe()
        let only = Task { await queue.run("k", probe.work(5)) }
        #expect(await eventually { await probe.waitingCount == 1 })
        only.cancel()
        #expect(await only.value == nil)
        await probe.releaseAll()
        #expect(await eventually { await probe.observedCancellation == 1 })
        // 名額已釋放：下一個工作可以開始
        let next = Task { await queue.run("n", probe.work(1)) }
        #expect(await eventually { await probe.waitingCount == 1 })
        await probe.releaseAll()
        #expect(await next.value == 1)
    }

    /// 取消中的舊工作不得吞掉同鍵的新請求：新請求開新工作、拿到真值
    @Test func newWaiterAfterCancelledRunStartsFreshJob() async {
        let queue = macQueue(2)
        let probe = WorkProbe()
        let old = Task { await queue.run("k", probe.work(1)) }
        #expect(await eventually { await probe.waitingCount == 1 })
        old.cancel()
        #expect(await old.value == nil)
        let fresh = Task { await queue.run("k", probe.work(2)) }
        #expect(await eventually { await probe.waitingCount == 2 })
        await probe.releaseAll()
        #expect(await fresh.value == 2)
        #expect(await probe.calls == 2)
    }

    @Test func alreadyCancelledCallerReturnsNilImmediately() async {
        let queue = macQueue(1)
        let probe = WorkProbe()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await queue.run("k", probe.work(1))
        }
        #expect(await task.value == nil)
        #expect(await probe.calls == 0)
    }

    // MARK: 策略參數

    /// 名額滿時，等待中的工作依 FIFO（Mac）或 LIFO（iPad：後到者先送＝可視區優先）開始
    @Test(arguments: [(CoalescingQueue<String, Int>.Order.fifo, [0, 1, 2, 3]), (.lifo, [0, 3, 2, 1])])
    func orderDecidesWhichWaitingJobStartsNext(order: CoalescingQueue<String, Int>.Order, expected: [Int]) async {
        let queue = MacQueue(maxConcurrent: 1, order: order, whenAbandoned: .cancelRunning)
        let probe = WorkProbe()
        let first = Task { await queue.run("0", probe.work(0)) }
        #expect(await eventually { await probe.waitingCount == 1 })
        var later: [Task<Int?, Never>] = []
        for value in 1...3 {
            later.append(Task { await queue.run("\(value)", probe.work(value)) })
            #expect(await eventually { await queue.waiterCount("\(value)") == 1 })   // 登記完才送下一個：固定到達順序
        }
        for _ in 0..<4 {
            #expect(await eventually { await probe.waitingCount == 1 })
            await probe.releaseAll()
        }
        _ = await first.value
        for task in later { _ = await task.value }
        #expect(await probe.started == expected)
    }

    /// iPad 策略：已開始的工作在全員撤回後仍做完（副作用如寫快取發生），撤回者拿到 nil
    @Test func finishRunningKeepsStartedWorkAfterAllWaitersLeave() async {
        let queue = padQueue(1)
        let probe = WorkProbe()
        let only = Task { await queue.run("k", probe.work(5)) }
        #expect(await eventually { await probe.waitingCount == 1 })
        only.cancel()
        #expect(await only.value == nil)
        await probe.releaseAll()
        #expect(await eventually { await probe.completed == 1 })
        #expect(await probe.observedCancellation == 0)
    }

    /// iPad 策略：全員撤回、仍在跑的工作，同鍵新請求併入它（不重做）並拿到結果
    @Test func finishRunningLetsLaterWaiterJoinTheRunningJob() async {
        let queue = padQueue(1)
        let probe = WorkProbe()
        let old = Task { await queue.run("k", probe.work(5)) }
        #expect(await eventually { await probe.waitingCount == 1 })
        old.cancel()
        #expect(await old.value == nil)
        let joiner = Task { await queue.run("k", probe.work(6)) }
        #expect(await eventually { await queue.waiterCount("k") == 1 })   // joiner 已併入執行中的工作
        await probe.releaseAll()
        #expect(await joiner.value == 5)
        #expect(await probe.calls == 1)
    }

    /// 兩種策略下，尚未開始的工作在全員撤回後都直接移除
    @Test(arguments: [CoalescingQueue<String, Int>.WhenAbandoned.cancelRunning, .finishRunning])
    func notStartedWorkIsDroppedUnderEitherPolicy(policy: CoalescingQueue<String, Int>.WhenAbandoned) async {
        let queue = MacQueue(maxConcurrent: 1, order: .fifo, whenAbandoned: policy)
        let probe = WorkProbe()
        let blocker = Task { await queue.run("busy", probe.work(0)) }
        #expect(await eventually { await probe.waitingCount == 1 })
        let queued = Task { await queue.run("queued", probe.work(9)) }
        try? await Task.sleep(for: .milliseconds(20))
        queued.cancel()
        #expect(await queued.value == nil)
        await probe.releaseAll()
        _ = await blocker.value
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await probe.calls == 1)
    }
}

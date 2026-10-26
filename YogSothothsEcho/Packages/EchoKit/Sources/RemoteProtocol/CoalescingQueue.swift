import Foundation

/// 同鍵合併＋並行上限（sprint-4-detail.md §4.11；收斂 Mac CoalescingLimiter 與 iPad ArtworkCache 兩份合併邏輯）。
/// 工作由本 actor 擁有：有任何等待者就做完；被取消的等待者立即收到 nil。兩端的差異只在兩個參數：
/// - `order`：名額空出時先開始哪個等待中的工作（Mac＝FIFO；iPad＝LIFO，後到者先送＝可視區優先）
/// - `whenAbandoned`：已開始的工作在等待者全部撤回時，取消（Mac）或做完（iPad：副作用在工作閉包內，例如寫快取）。
///   尚未開始者兩種策略都直接移除。
/// 平台 IO 與快取副作用一律留在呼叫端的工作閉包裡，本型別不知道它們。
public actor CoalescingQueue<Key: Hashable & Sendable, Value: Sendable> {
    public typealias Work = @Sendable () async -> Value?

    public enum Order: Sendable { case fifo, lifo }
    public enum WhenAbandoned: Sendable { case cancelRunning, finishRunning }

    private struct Job {
        let id = UUID()
        var waiters: [UUID: CheckedContinuation<Value?, Never>] = [:]
        let work: Work
        var task: Task<Void, Never>?
    }

    private let maxConcurrent: Int
    private let order: Order
    private let whenAbandoned: WhenAbandoned
    private var jobs: [Key: Job] = [:]
    private var pending: [Key] = []
    private var running = 0

    public init(maxConcurrent: Int, order: Order, whenAbandoned: WhenAbandoned) {
        self.maxConcurrent = maxConcurrent
        self.order = order
        self.whenAbandoned = whenAbandoned
    }

    public func run(_ key: Key, _ work: @escaping Work) async -> Value? {
        let id = UUID()
        // register 在本 actor 上同步執行、早於任何取消回呼排入的工作；登記前就已取消者由 Task.isCancelled 擋下。
        // 因此取消回呼找不到等待者＝已完成，直接忽略（舊版的 cancelledEarly 集合會因此殘留，附錄 E.3 P2）
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                register(key, id: id, continuation: continuation, work: work)
            }
        } onCancel: {
            Task { await self.withdraw(key, id: id) }
        }
    }

    private func register(_ key: Key, id: UUID, continuation: CheckedContinuation<Value?, Never>, work: @escaping Work) {
        guard !Task.isCancelled else { return continuation.resume(returning: nil) }
        if jobs[key] == nil {
            jobs[key] = Job(work: work)
            pending.append(key)
        }
        jobs[key]?.waiters[id] = continuation
        startNext()
    }

    /// 該鍵目前的等待者數（測試用來確認登記已完成）
    func waiterCount(_ key: Key) -> Int { jobs[key]?.waiters.count ?? 0 }

    private func withdraw(_ key: Key, id: UUID) {
        guard let continuation = jobs[key]?.waiters.removeValue(forKey: id) else { return }
        continuation.resume(returning: nil)
        guard let job = jobs[key], job.waiters.isEmpty else { return }
        guard let task = job.task else {
            jobs[key] = nil
            pending.removeAll { $0 == key }
            return
        }
        guard whenAbandoned == .cancelRunning else { return }   // 做完；同鍵新請求可併入
        // 立即摘下，之後同鍵的新請求開新工作；執行中的名額在其 finish 時才釋放
        task.cancel()
        jobs[key] = nil
    }

    private func startNext() {
        while running < maxConcurrent, let key = order == .fifo ? pending.first : pending.last {
            if order == .fifo { pending.removeFirst() } else { pending.removeLast() }
            guard let job = jobs[key] else { continue }
            running += 1
            let jobID = job.id, work = job.work
            jobs[key]?.task = Task { [weak self] in
                let value = await work()
                await self?.finish(key, jobID: jobID, value)
            }
        }
    }

    private func finish(_ key: Key, jobID: UUID, _ value: Value?) {
        running -= 1
        // 已被摘下（全部等待者取消）的工作不得動到同鍵的新工作
        if jobs[key]?.id == jobID {
            jobs.removeValue(forKey: key)?.waiters.values.forEach { $0.resume(returning: value) }
        }
        startNext()
    }
}

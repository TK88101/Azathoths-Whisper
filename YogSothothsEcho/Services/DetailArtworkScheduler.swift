import Foundation
import UIKit

/// detail 原檔的單飛排程（sprint-6-detail.md D8、§4.4）：Mac 對同一 peer 只保留最新世代的 detail 傳輸（CR-018，新的取代舊的），
/// 瀏覽、開啟的專輯、唱機若各自直送會互相取代、重來到放棄，所以 iPad 端同時只送一個。
/// - 優先序：唱機 > 開啟中的專輯 > 瀏覽（距中心近者先）；較高層級到達時搶占正在跑的較低層級（瀏覽之間不搶占）
/// - 每次 `request` 是一個 demand；呼叫端的 Task 被取消＝撤銷。同 key 的 demand 共用一個傳輸，傳輸的優先序＝現存 demand 的最高者；
///   demand 全撤＝取消在途傳輸。被搶占的傳輸只有 demand 仍在才回佇列
/// - 只排程、回原始位元組；解碼由各端依自己的尺寸做。磁碟快取命中不經排隊
actor DetailArtworkScheduler {
    enum Priority: Sendable, Equatable {
        case browse(distance: Int), opened, turntable

        fileprivate var tier: Int {
            switch self {
            case .browse: 0
            case .opened: 1
            case .turntable: 2
            }
        }

        /// 同層級時距中心近者先
        fileprivate func outranks(_ other: Priority) -> Bool {
            if tier != other.tier { return tier > other.tier }
            if case .browse(let a) = self, case .browse(let b) = other { return a < b }
            return false
        }
    }

    typealias Lookup = @Sendable (_ albumID: String, _ token: String) async -> Data?

    private struct Key: Hashable {
        let albumID: String
        let token: String
    }

    private struct Demand {
        let priority: Priority
        let continuation: CheckedContinuation<Data?, Never>
    }

    private struct Job {
        var demands: [UUID: Demand] = [:]
        var priority: Priority? {
            demands.values.map(\.priority).reduce(nil) { best, p in best.map { p.outranks($0) ? p : $0 } ?? p }
        }
    }

    private let cached: Lookup
    private let fetch: Lookup
    /// 磁碟快取命中只驗檔頭；解不開時由 `image` 刪掉該筆再重取
    private let evict: @Sendable (_ albumID: String, _ token: String) async -> Void
    private var jobs: [Key: Job] = [:]
    /// 正在傳輸的 key 與其 Task；`serial` 擋被搶占或取消後才回來的舊結果
    private var running: (key: Key, task: Task<Void, Never>, serial: Int)?
    private var serial = 0
    /// 被搶占或取消、尚在收尾的傳輸：下一個傳輸等它結束才開始（同時只一個）
    private var windingDown: Task<Void, Never>?
    /// 取消處理先於 demand 登記到達時記在這裡，登記時直接回 nil
    private var withdrawnEarly: Set<UUID> = []

    init(cached: @escaping Lookup, fetch: @escaping Lookup,
         evict: @escaping @Sendable (_ albumID: String, _ token: String) async -> Void = { _, _ in }) {
        self.evict = evict
        self.cached = cached
        self.fetch = fetch
    }

    func request(albumID: String, token: String?, priority: Priority) async -> Data? {
        guard let token, !Task.isCancelled else { return nil }
        if let data = await cached(albumID, token) { return data }
        let key = Key(albumID: albumID, token: token), id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                enqueue(id, key: key, demand: Demand(priority: priority, continuation: continuation))
            }
        } onCancel: {
            Task { await self.withdraw(id, key: key) }
        }
    }

    /// 尚未回覆的 demand 數（測試用來確定「已排進佇列」）
    var pendingDemands: Int { jobs.values.reduce(0) { $0 + $1.demands.count } }

    /// 斷線：全部回 nil、在途取消
    func cancelAll() {
        let demands = jobs.values.flatMap(\.demands.values)
        jobs = [:]
        stopRunning()
        demands.forEach { $0.continuation.resume(returning: nil) }
    }

    private func enqueue(_ id: UUID, key: Key, demand: Demand) {
        if withdrawnEarly.remove(id) != nil {
            demand.continuation.resume(returning: nil)
            return
        }
        jobs[key, default: Job()].demands[id] = demand
        pump()
    }

    private func withdraw(_ id: UUID, key: Key) {
        guard let demand = jobs[key]?.demands.removeValue(forKey: id) else {
            withdrawnEarly.insert(id)
            return
        }
        demand.continuation.resume(returning: nil)
        if jobs[key]?.demands.isEmpty == true {
            jobs[key] = nil
            if running?.key == key { stopRunning() }
        }
        pump()
    }

    private func stopRunning() {
        guard let current = running else { return }
        current.task.cancel()
        let previous = windingDown
        windingDown = Task { await previous?.value; await current.task.value }
        running = nil
    }

    /// 選下一個：佇列中優先序最高者；正在跑的層級較低時先搶占它
    private func pump() {
        let queued = jobs.filter { $0.key != running?.key }.compactMap { key, job in job.priority.map { (key, $0) } }
        guard let best = queued.reduce(nil, { (top: (Key, Priority)?, next) in
            top.map { next.1.outranks($0.1) ? next : $0 } ?? next
        }) else { return }
        if let current = running {
            guard let currentPriority = jobs[current.key]?.priority, best.1.tier > currentPriority.tier else { return }
            stopRunning()
        }
        start(best.0)
    }

    private func start(_ key: Key) {
        serial += 1
        let mine = serial, previous = windingDown, fetch = fetch
        windingDown = nil
        let task = Task {
            await previous?.value
            let data = Task.isCancelled ? nil : await fetch(key.albumID, key.token)
            await self.finished(key, serial: mine, data: data)
        }
        running = (key, task, mine)
    }

    private func finished(_ key: Key, serial finishedSerial: Int, data: Data?) {
        guard let current = running, current.serial == finishedSerial else { return }
        running = nil
        let demands = jobs.removeValue(forKey: key)?.demands.values.map(\.continuation) ?? []
        demands.forEach { $0.resume(returning: data) }
        pump()
    }
}

extension DetailArtworkScheduler {
    /// 要原檔並在呼叫端以外解碼（唱機、開啟的專輯共用；瀏覽另有自己的尺寸與快取，見 BrowseArtwork）
    /// 解不開＝快取裡檔頭完好但內容壞了（剛傳來的都試解過）：刪掉這筆、重取一次，不會永遠停在 spine
    nonisolated func image(albumID: String, token: String?, priority: Priority) async -> UIImage? {
        guard let data = await request(albumID: albumID, token: token, priority: priority) else { return nil }
        if let image = await DetailArtworkDecoder.decoded(data) { return image }
        guard let token else { return nil }
        await evict(albumID, token)
        guard let fresh = await request(albumID: albumID, token: token, priority: priority) else { return nil }
        return await DetailArtworkDecoder.decoded(fresh)
    }
}

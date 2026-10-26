import Foundation
import Observation
import RemoteProtocol
import UIKit

/// 瀏覽封面升級（sprint-6-detail.md D7、§4.4）：側封一律先用 spine（160 px），貼在 13 吋 700–800 pt 的面上會糊；
/// 捲動停 300 ms 後對螢幕上看得到的盒子（#6-1：使用者要停下後畫面上全部清晰）依距離向排程器要 detail 原檔（`.browse(distance)`）。
/// 離開可見範圍即撤回（取消該請求的 Task＝撤銷排程器上的 demand）。
/// g 版 T5（s6-61-g-perf-wear.md §5.5）：小圖也升級（grid 512 px；原本從未升級＝「縮圖永遠糊」的根因）；rendition 進鍵，
/// 同專輯兩種可同時在途；切換展示撤回全部並換世代（舊世代不回填）；spine／grid 各一個固定位元組預算的 LRU，互不擠壓
@MainActor
@Observable
final class BrowseArtwork {
    enum Rendition: Hashable, Sendable {
        case spine, grid
        var maxPixels: Int { self == .spine ? 1024 : 512 }
        /// 一張已解碼圖的快取成本（同 `CGImage.byteCost`：寬×高×4）
        var decodedBytes: Int { maxPixels * maxPixels * 4 }
    }

    struct Candidate: Equatable { let album: AlbumSummary; let distance: Int }
    typealias Request = @Sendable (_ albumID: String, _ token: String?, _ priority: DetailArtworkScheduler.Priority) async -> Data?
    typealias Decode = @Sendable (_ data: Data, _ maxPixels: Int) async -> UIImage?

    static let settleDelay: Duration = .milliseconds(300)
    /// 側封繪製範圍（螢幕上＋兩端緩衝）取樣最多 13 吋 17 張、11 吋 18 張（`BrowseArtworkBudgetTests`）；
    /// ×2＝目前停靠與前一個不重疊停靠都放得下，滑開一屏再滑回不用重抓（s6-61-browse-lru.md）
    static let spineResident = 2 * 18
    static let spineByteLimit = spineResident * Rendition.spine.decodedBytes
    /// 小圖一屏 5×5 張 512²≈25 MiB，加約 10%
    static let gridByteLimit = 28 * 1_048_576

    /// 已解碼快取以 rendition 分開，鍵不必再帶 rendition
    private struct Key: Hashable, Sendable {
        let albumID: String
        let token: String
    }

    private struct Slot: Hashable { let albumID: String; let rendition: Rendition }

    @ObservationIgnored private let request: Request
    @ObservationIgnored private let decode: Decode
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private var decoded: [Rendition: MemoryLRU<Key, UIImage>]
    @ObservationIgnored private var settleTasks: [Rendition: Task<Void, Never>] = [:]
    /// 帶 token（換版後 token 變了要重發）與 ticket（被取消的舊請求晚到收尾時，不得清掉同一張專輯的新請求）
    @ObservationIgnored private var inFlight: [Slot: (token: String, ticket: UUID, task: Task<Void, Never>)] = [:]
    /// 切換展示即遞增：舊世代的請求完成後不回填
    @ObservationIgnored private var generation = 0
    /// 解好一張就遞增，讓讀 `image(for:)` 的視圖重畫
    private(set) var revision = 0
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var memoryWarning: NSObjectProtocol?

    /// `notifications`：測試注入私有的通知中心，免得全域記憶體警告清掉並行中其他測試的實例
    init(request: @escaping Request, decode: @escaping Decode, sleep: @escaping @Sendable (Duration) async -> Void,
         spineByteLimit: Int = BrowseArtwork.spineByteLimit, gridByteLimit: Int = BrowseArtwork.gridByteLimit,
         notifications: NotificationCenter = .default) {
        self.request = request
        self.decode = decode
        self.sleep = sleep
        self.notifications = notifications
        decoded = [.spine: MemoryLRU(costLimit: spineByteLimit), .grid: MemoryLRU(costLimit: gridByteLimit)]
        memoryWarning = notifications.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseAll() }
        }
    }

    isolated deinit {
        if let memoryWarning { notifications.removeObserver(memoryWarning) }
    }

    /// 可見範圍外的在途請求撤回；`schedules`＝捲動已停下，300 ms 後對螢幕上的盒子升級（捲動中只撤回、不排程，
    /// 否則慢速拖曳時計時會在還在捲時到期、拿過期的中心去佔唯一的傳輸）
    func update(candidates: [Candidate], visibleIDs: Set<String>, schedules: Bool = true, rendition: Rendition = .spine) {
        for (slot, entry) in inFlight where slot.rendition == rendition && !visibleIDs.contains(slot.albumID) {
            entry.task.cancel()
            inFlight[slot] = nil
        }
        settleTasks[rendition]?.cancel()
        guard schedules else { return }
        let sleep = sleep
        settleTasks[rendition] = Task { [weak self] in
            await sleep(Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.upgrade(candidates, rendition: rendition)
        }
    }

    /// 換展示（側封 ↔ 小圖）：已解碼圖兩種都清掉，峰值＝較大的那一種而非相加
    /// （切回時由停下升級從 iPad 磁碟快取重新解碼，不經 Mac）
    func switchLayout() { releaseAll() }

    /// 換展示與記憶體警告共用：撤回所有排程與在途、換世代（在途完成也不回填）、清掉兩種已解碼圖並讓視圖重讀
    /// （退回 spine 縮圖、下次停下再升級）
    private func releaseAll() {
        settleTasks.values.forEach { $0.cancel() }
        settleTasks = [:]
        inFlight.values.forEach { $0.task.cancel() }
        inFlight = [:]
        generation += 1
        decoded = decoded.mapValues { MemoryLRU(costLimit: $0.costLimit) }
        revision += 1
    }

    func image(for album: AlbumSummary, rendition: Rendition = .spine) -> UIImage? {
        _ = revision
        guard let token = album.artworkToken else { return nil }
        return decoded[rendition]?.value(for: Key(albumID: album.id, token: token))
    }

    private func upgrade(_ candidates: [Candidate], rendition: Rendition) {
        // 停在新中心：舊中心還在途、但已不在新升級範圍內的取消（瀏覽之間不搶占，否則它會佔著唯一的傳輸、還帶著過期的距離）
        let wanted = Set(candidates.map(\.album.id))
        for (slot, entry) in inFlight where slot.rendition == rendition && !wanted.contains(slot.albumID) {
            entry.task.cancel()
            inFlight[slot] = nil
        }
        for candidate in candidates {
            let album = candidate.album, slot = Slot(albumID: album.id, rendition: rendition)
            guard let token = album.artworkToken, inFlight[slot]?.token != token else { continue }
            inFlight[slot]?.task.cancel()
            let key = Key(albumID: album.id, token: token)
            guard decoded[rendition]?.value(for: key) == nil else {
                inFlight[slot] = nil
                continue
            }
            let request = request, decode = decode, ticket = UUID(), generation = generation
            let task = Task { [weak self] in
                let data = await request(album.id, token, .browse(distance: candidate.distance))
                let image = if let data, !Task.isCancelled { await decode(data, rendition.maxPixels) } else { UIImage?.none }
                self?.finished(key, slot: slot, ticket: ticket, generation: generation, image: Task.isCancelled ? nil : image)
            }
            inFlight[slot] = (token, ticket, task)
        }
    }

    private func finished(_ key: Key, slot: Slot, ticket: UUID, generation: Int, image: UIImage?) {
        if inFlight[slot]?.ticket == ticket { inFlight[slot] = nil }
        guard let image, generation == self.generation else { return }
        decoded[slot.rendition]?.set(key, image, cost: image.cgImage?.byteCost ?? 1)
        revision += 1
    }

    /// 螢幕上看得到的盒子（不含兩端緩衝），依距中心由近到遠；排程器單飛，所以由中央往外依序變清晰
    static func candidates(albums: [AlbumSummary], offset: CGFloat, metrics: SpineCarouselMetrics) -> [Candidate] {
        guard !albums.isEmpty else { return [] }
        let center = SpineCarousel.centerIndex(offset: offset, count: albums.count, metrics: metrics)
        return SpineCarousel.onScreenRange(offset: offset, count: albums.count, metrics: metrics)
            .map { Candidate(album: albums[$0], distance: abs($0 - center)) }
            .sorted { $0.distance < $1.distance }
    }
}

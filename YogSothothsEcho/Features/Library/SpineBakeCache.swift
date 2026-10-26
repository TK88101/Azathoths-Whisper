import CoreGraphics
import RemoteProtocol
import SwiftUI
import UIKit

/// 書脊烘焙的佇列與快取（s6-61-g-perf-wear.md §5.1；Codex R1 背壓）：
/// 同時最多畫 2 張（優先序＝距中心、目前側先）；預熱換世代時，未開工且沒人在等的項目丟棄；同鍵在途去重；
/// 等待者被取消不影響共享的那次烘焙（完成照樣入快取）。快取只管去重與儲存，畫面刷新由 `SpineBakeView` 的 @State 負責
@MainActor
final class SpineBakeCache {
    typealias Render = @Sendable (SpineBake.Input) async -> CGImage?

    static let shared = SpineBakeCache()
    /// 13 吋單張約 46×1528×4≈0.28 MiB；48 MiB≈170 張（≈85 張專輯的兩側），遠大於可見數（約 10）
    static let byteLimit = 48 * 1_048_576
    static let maxConcurrent = 2

    /// 單元／Render 測試：缺圖時當場同步烘焙（ImageRenderer 不等非同步）
    var rendersSynchronously = false

    private let render: Render
    private var entries: MemoryLRU<SpineBake.Key, CGImage>
    /// 同一面（專輯、側、尺寸）最近烘好的鍵：新來源還沒烘好前先顯示它，避免換圖時閃回佔位
    private var latest: [Face: SpineBake.Key] = [:]
    private var pending: [SpineBake.Key: (input: SpineBake.Input, priority: Int)] = [:]
    private var running: Set<SpineBake.Key> = []
    /// 以等待者 ID 保存：視圖的 task 被取消（盒子離開畫面）時只撤掉它自己（Codex 實作 R1 P1）
    private var waiters: [SpineBake.Key: [UUID: CheckedContinuation<CGImage?, Never>]] = [:]
    /// 最近一輪預熱的需求
    private var wanted: Set<SpineBake.Key> = []

    private struct Face: Hashable {
        let albumID: String
        let side: CarouselSide
        let thickness: CGFloat, cover: CGFloat, scale: CGFloat

        init(_ key: SpineBake.Key) {
            albumID = key.albumID
            side = key.side
            thickness = key.thickness
            cover = key.cover
            scale = key.scale
        }
    }

    init(byteLimit: Int = SpineBakeCache.byteLimit, render: @escaping Render = { SpineBake.render($0) }) {
        self.render = render
        entries = MemoryLRU(costLimit: byteLimit)
    }

    func cached(_ key: SpineBake.Key) -> CGImage? { entries.value(for: key) }

    /// 精確的鍵沒有時，同一面最近烘好的那張（換來源期間沿用）
    func bestAvailable(_ key: SpineBake.Key) -> CGImage? {
        if let hit = entries.value(for: key) { return hit }
        return latest[Face(key)].flatMap { entries.value(for: $0) }
    }

    /// 測試同步模式：當場烘焙並入快取
    func renderNow(_ input: SpineBake.Input) -> CGImage? {
        if let hit = entries.value(for: input.key) { return hit }
        guard rendersSynchronously, let image = SpineBake.render(input) else { return nil }
        store(input.key, image)
        return image
    }

    /// 畫面要的那張：命中即回；否則以最高優先入隊並等它。等待被取消＝撤掉這個等待者，
    /// 該鍵沒人等、也不在預熱需求內就丟掉未開工的項目（已開工的照樣畫完入快取）
    func request(_ input: SpineBake.Input, priority: Int = -1) async -> CGImage? {
        if let hit = entries.value(for: input.key) { return hit }
        let key = input.key, id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { return continuation.resume(returning: nil) }
                waiters[key, default: [:]][id] = continuation
                enqueue(input, priority: priority)
                pump()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelWaiter(key, id) }
        }
    }

    private func cancelWaiter(_ key: SpineBake.Key, _ id: UUID) {
        guard let continuation = waiters[key]?.removeValue(forKey: id) else { return }
        if waiters[key]?.isEmpty == true {
            waiters[key] = nil
            if !wanted.contains(key) { pending[key] = nil }
        }
        continuation.resume(returning: nil)
    }

    /// 新一輪預熱：取代上一輪的需求；不在新需求內、未開工、沒人在等的丟棄
    func prefetch(_ requests: [SpineBakePrefetch.Request]) {
        wanted = Set(requests.map(\.input.key))
        pending = pending.filter { wanted.contains($0.key) || waiters[$0.key] != nil }
        for request in requests where entries.value(for: request.input.key) == nil {
            enqueue(request.input, priority: request.priority)
        }
        pump()
    }

    private func enqueue(_ input: SpineBake.Input, priority: Int) {
        guard !running.contains(input.key) else { return }
        let current = pending[input.key]?.priority ?? .max
        pending[input.key] = (input, min(current, priority))
    }

    private func pump() {
        while running.count < Self.maxConcurrent,
              let next = pending.min(by: { $0.value.priority < $1.value.priority }) {
            pending[next.key] = nil
            running.insert(next.key)
            let input = next.value.input, render = render
            Task.detached(priority: .utility) { [weak self] in
                let image = await render(input)
                await self?.finished(input.key, image: image)
            }
        }
    }

    private func finished(_ key: SpineBake.Key, image: CGImage?) {
        running.remove(key)
        if let image { store(key, image) }
        waiters.removeValue(forKey: key)?.values.forEach { $0.resume(returning: image) }
        pump()
    }

    private func store(_ key: SpineBake.Key, _ image: CGImage) {
        entries.set(key, image, cost: image.byteCost)
        latest[Face(key)] = key
    }
}

/// 可見盒（＋兩側各 1）的預熱需求：每張兩側都要（BoxFaces 只建目前朝向那面，翻側前反側要先烘好），
/// 優先序＝距中心 × 2，目前側 +0、反側 +1
enum SpineBakePrefetch {
    struct Request {
        let input: SpineBake.Input
        let priority: Int
    }

    @MainActor
    static func requests(albums: [AlbumSummary], range: Range<Int>, offset: CGFloat, metrics: SpineCarouselMetrics, scale: CGFloat,
                         image: (AlbumSummary) -> UIImage?) -> [Request] {
        guard !albums.isEmpty else { return [] }
        let center = SpineCarousel.centerIndex(offset: offset, count: albums.count, metrics: metrics)
        let clamped = range.clamped(to: 0..<albums.count)
        return clamped.flatMap { index -> [Request] in
            let album = albums[index], picture = image(album)
            let current = SpineCarousel.pose(u: SpineCarousel.u(index: index, offset: offset, metrics: metrics), metrics: metrics).side
            let distance = abs(index - center) * 2
            return [CarouselSide.left, .right].map { side in
                Request(input: SpineBake.input(album: album, image: picture, side: side, thickness: metrics.spine, cover: metrics.cover,
                                               scale: scale),
                        priority: distance + (side == current ? 0 : 1))
            }
        }
    }
}

/// 貼一張書脊烘焙圖；未烘好時先貼同一面最近的那張，再沒有就是佔位色
struct SpineBakeView: View {
    let input: SpineBake.Input
    @State private var baked: (key: SpineBake.Key, image: CGImage)?

    var body: some View {
        let cache = SpineBakeCache.shared
        let shown = baked.flatMap { $0.key == input.key ? $0.image : nil } ?? cache.renderNow(input) ?? cache.bestAvailable(input.key)
        Group {
            if let shown {
                Image(decorative: shown, scale: input.key.scale).resizable()
            } else {
                let c = input.placeholder
                Color(red: c.r, green: c.g, blue: c.b)
            }
        }
        .allowsHitTesting(false)
        .task(id: input.key) {
            guard cache.cached(input.key) == nil else { return }
            if let image = await cache.request(input) { baked = (input.key, image) }
        }
    }
}
